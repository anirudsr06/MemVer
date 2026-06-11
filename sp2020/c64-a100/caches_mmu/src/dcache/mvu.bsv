package mvu;
    import FIFOF::*;
    import FIFO::*;
    import GetPut::*;
    import Assert::*;
    import Vector::*;
    import dcache_types::*;
    import hcache::*;
    `include "dcache.defines"

    typedef 8 Arity;
    typedef 64 HashWidth;
    typedef Bit#(4) Level;
    typedef Bit#(19) TreeIndex;

    // Request for tree nodes from memory
    typedef struct {
        Level level;
        TreeIndex base_index;  // Base index of the 8-sibling group
        Bit#(3) sibling_mask;  // Which siblings to fetch (7 of 8, excluding one we have)
    } TreeNodeReq deriving(Bits, Eq, FShow);

    // Write request for tree nodes (updates)
    typedef struct {
        Level level;
        TreeIndex index;
        Bit#(HashWidth) hash;
    } TreeNodeWrite deriving(Bits, Eq, FShow);

    // Response with tree nodes
    typedef struct {
        Vector#(Arity, Bit#(HashWidth)) hashes;
        Vector#(Arity, Bool) valid;
    } TreeNodeResp deriving(Bits, Eq);

    // Verification state
    typedef enum {
        IDLE,
        ACCUMULATING,
        COMPUTE_L0_PARENT,
        FETCH_SIBLINGS,
        WAIT_SIBLINGS,
        COMPUTE_PARENT,
        CHECK_PARENT,
        UPDATE_NODE,
        WAIT_UPDATE_ACK,
        FETCH_HCACHE_SIBLINGS,
        PROPAGATE_UP,
        VERIFY_ROOT,
        COMPLETE,
        FORWARD_TO_CACHE
    } VerifyState deriving(Bits, Eq, FShow);

interface Ifc_mvu;
    // Cache interface
    interface Put#(DCache_mem_readreq#(`paddr)) put_cache_read_req;
    interface Get#(DCache_mem_readresp#(`dbuswidth)) get_cache_read_resp;

    // Eviction interface (Write notification)
    interface Put#(DCache_mem_writereq#(`paddr, TMul#(`dblocks, TMul#(`dwords, 8)))) put_evict_req;

    // Memory interface (for data)
    interface Get#(DCache_mem_readreq#(`paddr)) get_mem_read_req;
    interface Put#(DCache_mem_readresp#(`dbuswidth)) put_mem_read_resp;

    // Tree node memory interface (for siblings)
    interface Get#(TreeNodeReq) get_tree_node_req;
    interface Put#(TreeNodeResp) put_tree_node_resp;
    interface Get#(TreeNodeWrite) get_tree_write_req;
    interface Put#(Bool) put_tree_write_resp;

    // Control
    method Action ma_enable(Bool en);
    method Action ma_set_trusted_root(Bit#(HashWidth) root);

    // Debug
    method ActionValue#(Maybe#(Bit#(HashWidth))) debug_get_hash(Level level, TreeIndex index);
    method VerifyState debug_state();
endinterface

    (* synthesize *)
    module mkmvu(Ifc_mvu);
        // FIFOs
        FIFOF#(DCache_mem_readreq#(`paddr)) ff_req_from_cache <- mkFIFOF;
        FIFOF#(DCache_mem_writereq#(`paddr, TMul#(`dblocks, TMul#(`dwords, 8)))) ff_evict_req <- mkFIFOF;
        FIFOF#(DCache_mem_readreq#(`paddr)) ff_req_to_mem <- mkFIFOF;
        FIFOF#(DCache_mem_readresp#(`dbuswidth)) ff_resp_from_mem <- mkFIFOF;
        FIFOF#(DCache_mem_readresp#(`dbuswidth)) ff_resp_to_cache <- mkFIFOF;

        FIFOF#(TreeNodeReq) ff_tree_req <- mkFIFOF;
        FIFOF#(TreeNodeResp) ff_tree_resp <- mkFIFOF;
        FIFOF#(TreeNodeWrite) ff_tree_write <- mkFIFOF;
        FIFOF#(Bool) ff_tree_write_resp <- mkFIFOF;

        // Configuration
        Reg#(Bool) rg_mvu_enabled <- mkReg(True);
        Reg#(Bit#(HashWidth)) rg_trusted_root <- mkReg(0);

        // Request tracking
        Reg#(Maybe#(DCache_mem_readreq#(`paddr))) rg_pending_req <- mkReg(tagged Invalid);
        Reg#(Bool) rg_from_protected <- mkReg(False);
        Reg#(Bool) rg_is_update <- mkReg(False);
        Reg#(TreeIndex) rg_base_leaf_index <- mkReg(0);

        // State machine
        Reg#(VerifyState) rg_state <- mkReg(IDLE);

        // Current verification path
        Reg#(Level) rg_current_level <- mkReg(0);
        Reg#(TreeIndex) rg_current_index <- mkReg(0);
        
        // Current node group (8 siblings at current level)
        Reg#(Vector#(Arity, Bit#(HashWidth))) rg_node_group <- mkReg(replicate(0));
        Reg#(Vector#(Arity, Bool)) rg_node_valid <- mkReg(replicate(False));
        Reg#(Bit#(HashWidth)) rg_computed_parent <- mkReg(0);

        // Error flag: set when hash mismatch is detected; cleared after forwarding responses
        Reg#(Bool) rg_mvu_error <- mkReg(False);

        // The hash computed for the current node at the current level.
        // This is the value that should be STORED in tree memory at the current (level, index).
        // It is separate from rg_computed_parent, which holds the PARENT's hash.
        Reg#(Bit#(HashWidth)) rg_my_node_hash <- mkReg(0);

        // Vector of registers to store leaves and buffered responses
        Vector#(Arity, Reg#(Bit#(HashWidth))) rg_leaves <- replicateM(mkReg(0));
        Vector#(Arity, Reg#(DCache_mem_readresp#(`dbuswidth))) rg_buffered_responses <- replicateM(mkReg(unpack(0)));
        Reg#(UInt#(4)) rg_beat_count <- mkReg(0);
        Reg#(UInt#(4)) rg_forward_beat <- mkReg(0);
        Reg#(Bit#(3)) rg_sibling_ptr <- mkReg(0); 

        Ifc_HCache hcache <- mkHCache;

        function Bit#(HashWidth) compute_hash(Vector#(Arity, Bit#(HashWidth)) children);
            Bit#(HashWidth) result = 0;
            for (Integer i = 0; i < valueOf(Arity); i = i + 1)
                result = result + children[i];
            return result;
        endfunction

        // Compute which child we are within parent
        function Bit#(3) child_position(TreeIndex index);
            return truncate(index); // Lower 3 bits give position in group of 8
        endfunction

        // Compute base index of sibling group
        function TreeIndex sibling_group_base(TreeIndex index);
            return (index >> 3) << 3; // Clear lower 3 bits
        endfunction

        // Rule to handle eviction request after checking whether in protected region or not
        rule rl_start_update(
            ff_evict_req.notEmpty && 
            rg_state == IDLE
        );
            let req = ff_evict_req.first;
            ff_evict_req.deq;
            
            Bool is_protected = hcache.is_protected(req.address);
            
            if (is_protected && rg_mvu_enabled) begin
                TreeIndex leaf_idx = hcache.addr_to_leaf_index(req.address);
                
                rg_is_update <= True;
                rg_base_leaf_index <= leaf_idx;
                rg_beat_count <= 0;
                
                // Extract 8 leaves from 512-bit data
                // Assuming data is vector of 8x64 bits packed
                Vector#(Arity, Bit#(HashWidth)) leaves_data = unpack(req.data);
                for (Integer i = 0; i < valueOf(Arity); i = i + 1)
                    rg_leaves[i] <= leaves_data[i];
                
                rg_state <= COMPUTE_L0_PARENT;
                
                $display("[MVU] UPDATE START: Eviction at addr=%h, base_leaf_idx=%0d", 
                        req.address, leaf_idx);
            end else begin
                $display("[MVU] Ignoring eviction at %h (not protected)", req.address);
            end
        endrule

        // Rule to forward request to fetch from memory
        rule rl_forward_request(
            ff_req_from_cache.notEmpty && 
            !isValid(rg_pending_req) &&
            rg_state == IDLE
        );
            let req = ff_req_from_cache.first;
            ff_req_from_cache.deq;

            Bool is_protected = hcache.is_protected(req.address);
            
            if (is_protected && rg_mvu_enabled) begin
                TreeIndex leaf_idx = hcache.addr_to_leaf_index(req.address);
                
                rg_from_protected <= True;
                rg_is_update <= False; // Ensure read mode
                rg_base_leaf_index <= leaf_idx;
                rg_beat_count <= 0;
                rg_mvu_error <= False; // Clear error flag for new verification session
                for (Integer i = 0; i < valueOf(Arity); i = i + 1) begin
                    rg_leaves[i] <= 0;
                    rg_buffered_responses[i] <= unpack(0);
                end
                rg_state <= ACCUMULATING;
                
                $display("[MVU] Start verification: addr=%h, base_leaf_idx=%0d", 
                        req.address, leaf_idx);
            end else begin
                rg_from_protected <= False;
            end
            
            rg_pending_req <= tagged Valid req;
            ff_req_to_mem.enq(req);
        endrule

        // Rule to accumulate (send memory request to) required nodes from memory to begin verification
        rule rl_accumulate(
            ff_resp_from_mem.notEmpty &&& 
            rg_pending_req matches tagged Valid .req &&&
            rg_state == ACCUMULATING
        );
            let resp = ff_resp_from_mem.first;
            ff_resp_from_mem.deq();

            if (rg_from_protected) begin
                // Each beat is one leaf (8 bytes)
                Bit#(HashWidth) leaf_hash = truncate(resp.data);
                
                rg_leaves[rg_beat_count] <= leaf_hash;
                rg_buffered_responses[rg_beat_count] <= resp;

                $display("[MVU] Leaf[%0d] = %h", rg_beat_count, leaf_hash);

                if (resp.last) begin
                    dynamicAssert(rg_beat_count == fromInteger(valueOf(Arity) - 1), 
                                "Expected 8 beats per cache line!");
                    rg_state <= COMPUTE_L0_PARENT;
                    rg_beat_count <= 0;
                end else begin
                    rg_beat_count <= rg_beat_count + 1;
                end
            end

            else begin
                // Forward response to cache
                ff_resp_to_cache.enq(resp);
            end

            if (resp.last && !rg_from_protected) begin
                rg_pending_req <= tagged Invalid;
                rg_state <= IDLE;
            end
        endrule

        // Rule to compute zeroth level from accumulated nodes 
        rule rl_compute_l0_parent(rg_state == COMPUTE_L0_PARENT);
            Vector#(Arity, Bit#(HashWidth)) leaves = replicate(0);
            for (Integer i = 0; i < valueOf(Arity); i = i + 1)
                leaves[i] = rg_leaves[i];

            let parent_hash = compute_hash(leaves);

            // Parent index: base_leaf_index / 8
            TreeIndex parent_idx = rg_base_leaf_index >> 3;

            $display("[MVU] L0 parent[%0d] = %h (from leaves %0d-%0d)",
                    parent_idx, parent_hash,
                    rg_base_leaf_index, rg_base_leaf_index + 7);

            // Save this node's own hash (the L1 node value)
            rg_my_node_hash <= parent_hash;

            // Setup for next level
            rg_current_level <= 1;
            rg_current_index <= parent_idx;

            // Build node group locally
            Vector#(Arity, Bit#(HashWidth)) next_group = replicate(0);
            Vector#(Arity, Bool) next_valid = replicate(False);

            Bit#(3) pos = child_position(parent_idx);
            next_group[pos] = parent_hash;
            next_valid[pos] = True;

            // Single commit per register
            rg_node_group <= next_group;
            rg_node_valid <= next_valid;

            rg_state <= FETCH_SIBLINGS;

        endrule

        // Rule to fetch siblings (send memory request) from next level stored in memory
        rule rl_fetch_siblings(rg_state == FETCH_SIBLINGS);
            if (rg_current_level >= hcache.get_tree_height()) begin
                // We are at the Root. Do not fetch siblings; there are none.
                // Go straight to checking the value we have in rg_my_node_hash.
                if (rg_is_update) 
                    rg_state <= UPDATE_NODE;
                else 
                    rg_state <= CHECK_PARENT;
            end else if (hcache.is_hw_level(rg_current_level)) begin
                rg_sibling_ptr <= 0;
                rg_state <= FETCH_HCACHE_SIBLINGS;
            end else begin
                // Need to fetch siblings from memory
                TreeIndex base_idx = sibling_group_base(rg_current_index);
                Bit#(3) our_pos = child_position(rg_current_index);
                
                $display("[MVU] Fetching siblings for L%0d[%0d], base=%0d, our_pos=%0d", 
                        rg_current_level, rg_current_index, base_idx, our_pos);
                
                ff_tree_req.enq(TreeNodeReq {
                    level: rg_current_level,
                    base_index: base_idx,
                    sibling_mask: ~(1 << our_pos) // Fetch all except our position
                });
                
                rg_state <= WAIT_SIBLINGS;
            end
        endrule

        // Rule to accumulate sibling nodes from hcache
        rule rl_collect_hcache_siblings(rg_state == FETCH_HCACHE_SIBLINGS);
            Bit#(3) our_pos = child_position(rg_current_index);
            TreeIndex base_idx = sibling_group_base(rg_current_index);

            Vector#(Arity, Bit#(HashWidth)) group = rg_node_group;
            Vector#(Arity, Bool) valid = rg_node_valid;
            
            if (rg_sibling_ptr != our_pos) begin
                let h_maybe <- hcache.get_hash(rg_current_level, base_idx + extend(rg_sibling_ptr));
                Bit#(HashWidth) h = fromMaybe(0, h_maybe);

                group[rg_sibling_ptr] = h;
                valid[rg_sibling_ptr] = True;
                
                rg_node_group <= group;
                rg_node_valid <= valid;
            end

            if (rg_sibling_ptr == 7) begin
                rg_state <= COMPUTE_PARENT;
                rg_sibling_ptr <= 0;
            end else begin
                rg_sibling_ptr <= rg_sibling_ptr + 1;
            end
        endrule

        // Rule to receive memory response for sibling nodes
        rule rl_wait_siblings(rg_state == WAIT_SIBLINGS);
            let resp = ff_tree_resp.first;
            ff_tree_resp.deq;
            
            // Merge received siblings with our computed node
            Vector#(Arity, Bit#(HashWidth)) group = rg_node_group;
            Vector#(Arity, Bool) valid = rg_node_valid;
            
            for (Integer i = 0; i < valueOf(Arity); i = i + 1) begin
                if (resp.valid[i]) begin

                    Bit#(3) our_pos = child_position(rg_current_index);
                    if (fromInteger(i) != our_pos) begin
                        group[i] = resp.hashes[i];
                        valid[i] = True;
                    end
                end
            end
            
            rg_node_group <= group;
            rg_node_valid <= valid;
            rg_state <= COMPUTE_PARENT;
        endrule

        // Rule to compute hash for next level from stored hashes
        rule rl_compute_parent(rg_state == COMPUTE_PARENT);
            // Use 0 for missing siblings (sparse tree)
            Vector#(Arity, Bit#(HashWidth)) children = rg_node_group;
            for (Integer i = 0; i < valueOf(Arity); i = i + 1) begin
                if (!rg_node_valid[i])
                    children[i] = 0;
            end
            
            let parent_hash = compute_hash(children);
            rg_computed_parent <= parent_hash;
            
            $display("[MVU] Computed parent = %h", parent_hash);
            if (rg_is_update)
                rg_state <= UPDATE_NODE;
            else
                rg_state <= CHECK_PARENT;
        endrule

        // Rule to verify parent hash with stored value
        rule rl_check_parent(rg_state == CHECK_PARENT);
            if (hcache.is_hw_level(rg_current_level)) begin
                // Check against stored hash
                let stored <- hcache.get_hash(rg_current_level, rg_current_index);
                
                case (stored) matches
                    tagged Invalid: begin
                        // First time - store it
                        hcache.set_hash(rg_current_level, rg_current_index, rg_my_node_hash);
                        $display("[MVU] Stored new hash at L%0d[%0d]", 
                                rg_current_level, rg_current_index);
                    end
                    tagged Valid .h: begin
                        // Verify against stored hash
                        if (h != rg_my_node_hash) begin //Changed this to my node hash cause h is the hash at that level
                        //The display codes are wrong below computed parent -> my node hash
                            // Signal hardware error -- will cause err=True on cache response
                            rg_mvu_error <= True;
                            $display("[MVU] HASH MISMATCH at L%0d[%0d]: stored=%h computed=%h",
                                    rg_current_level, rg_current_index, h, rg_computed_parent);
                        end else begin
                            $display("[MVU] Hash verified at L%0d[%0d]", 
                                    rg_current_level, rg_current_index);
                        end
                    end
                endcase
            end
            
            // Check if we reached root
            if (rg_current_level >= hcache.get_tree_height()) begin
                rg_state <= VERIFY_ROOT;
            end else begin
                rg_state <= PROPAGATE_UP;
            end
        endrule

        // Rule to write back to stored nodes in memory
        rule rl_update_node(rg_state == UPDATE_NODE);
            if (hcache.is_hw_level(rg_current_level)) begin
                // Update HW hash — at HW levels, rg_computed_parent holds the
                // hash of all children at this level (= this node's value).
                //Updated with my node hash since that level's node is stored there only.
                hcache.set_hash(rg_current_level, rg_current_index, rg_my_node_hash);
                $display("[MVU] UPDATE: Updated HW Hash at L%0d[%0d] = %h", 
                        rg_current_level, rg_current_index, rg_my_node_hash);
                
                // Check root after HW update
                if (rg_current_level >= hcache.get_tree_height()) begin
                    rg_state <= COMPLETE;
                end else begin
                    rg_state <= PROPAGATE_UP;
                end
            end else begin
                // Write to tree memory — use rg_my_node_hash which is the
                // hash computed for THIS level's node (NOT the parent's hash).
                ff_tree_write.enq(TreeNodeWrite {
                    level: rg_current_level,
                    index: rg_current_index,
                    hash: rg_my_node_hash
                });
                $display("[MVU] UPDATE: Wrote Tree Node L%0d[%0d] = %h", 
                        rg_current_level, rg_current_index, rg_my_node_hash);
                
                // Wait for acknowledgment
                rg_state <= WAIT_UPDATE_ACK;
            end
        endrule

        // Rule to receive write response
        rule rl_wait_update_ack(rg_state == WAIT_UPDATE_ACK);
            // Consume response
            let ack = ff_tree_write_resp.first;
            ff_tree_write_resp.deq;
            
            $display("[MVU] UPDATE: Write acknowledged");
            
            // Check root (tree logic similar to check_parent/propagate)
            if (rg_current_level >= hcache.get_tree_height()) begin
                rg_state <= COMPLETE;
            end else begin
                rg_state <= PROPAGATE_UP;
            end
        endrule

        // Rule to move to next level
        rule rl_propagate_up(rg_state == PROPAGATE_UP);
            TreeIndex next_index = rg_current_index >> 3; // Parent index
            Level next_level = rg_current_level + 1;
            
            // Setup node group for next level
            Vector#(Arity, Bit#(HashWidth)) group = replicate(0);
            Vector#(Arity, Bool) valid = replicate(False);
            Bit#(3) pos = child_position(next_index);
            group[pos] = rg_computed_parent;

            valid[pos] = True;
            
            rg_current_level <= next_level;
            rg_current_index <= next_index;
            rg_node_group <= group;
            rg_node_valid <= valid;
            rg_my_node_hash <= rg_computed_parent;
            
            $display("[MVU] Propagating to L%0d[%0d]", next_level, next_index);
            rg_state <= FETCH_SIBLINGS;
        endrule

        // Final level verification
        rule rl_verify_root(rg_state == VERIFY_ROOT);
            if (rg_trusted_root != 0) begin
                if (rg_my_node_hash != rg_trusted_root) begin
                    rg_mvu_error <= True;
                    $display("[MVU] ROOT MISMATCH: computed=%h trusted=%h",
                            rg_my_node_hash, rg_trusted_root);
                end else begin
                    $display("[MVU] ROOT VERIFIED: %h", rg_my_node_hash);
                end
            end else begin
                $display("[MVU] Root computed (no trusted root set): %h", rg_my_node_hash);
            end
            
            rg_state <= COMPLETE;
        endrule

        // Complete
        rule rl_complete(rg_state == COMPLETE);
            $display("[MVU] Operation complete (error=%b)\n", rg_mvu_error);
            
            if (rg_is_update) begin
                 rg_state <= IDLE;
                 rg_is_update <= False;
                 rg_mvu_error <= False; // Clear error after update path
            end else begin
                 rg_state <= FORWARD_TO_CACHE;
            end
            
            rg_pending_req <= tagged Invalid;
            rg_from_protected <= False;
        endrule

        // Rule to pass through unprotected data
        rule rl_forward_unprotected(
            ff_resp_from_mem.notEmpty &&& 
            rg_pending_req matches tagged Valid .req &&&
            !rg_from_protected
        );
            let resp = ff_resp_from_mem.first;
            ff_resp_from_mem.deq;
            
            ff_resp_to_cache.enq(resp);
            
            if (resp.last) begin
                rg_pending_req <= tagged Invalid;
            end
        endrule

        // Rule to forward verified data to cache
        rule rl_forward_verified(rg_state == FORWARD_TO_CACHE);
            let resp = rg_buffered_responses[rg_forward_beat];
            // If a hash mismatch was detected, poison all beats with err=True
            // so the dcache will signal a Load Access Fault to the core.
            let forwarded_resp = resp;
            if (rg_mvu_error)
                forwarded_resp = DCache_mem_readresp { data: resp.data, last: resp.last, err: True };
            ff_resp_to_cache.enq(forwarded_resp);
            
            $display("[MVU] Forwarding beat %0d to cache (err=%b)", rg_forward_beat, rg_mvu_error);
            
            if (resp.last) begin
                rg_mvu_error <= False; // Clear after forwarding all beats
                rg_state <= IDLE;
                rg_pending_req <= tagged Invalid;
                rg_from_protected <= False;
                rg_forward_beat <= 0;
            end else begin
                rg_forward_beat <= rg_forward_beat + 1;
            end
        endrule
        
        interface put_cache_read_req = toPut(ff_req_from_cache);
        interface get_cache_read_resp = toGet(ff_resp_to_cache);
        interface put_evict_req = toPut(ff_evict_req);

        interface get_mem_read_req = toGet(ff_req_to_mem);
        interface put_mem_read_resp = toPut(ff_resp_from_mem);
        
        interface get_tree_node_req = toGet(ff_tree_req);
        interface put_tree_node_resp = toPut(ff_tree_resp);
        interface get_tree_write_req = toGet(ff_tree_write);
        interface put_tree_write_resp = toPut(ff_tree_write_resp);
        
        method Action ma_enable(Bool en);
            rg_mvu_enabled <= en;
        endmethod

        method Action ma_set_trusted_root(Bit#(HashWidth) root);
            rg_trusted_root <= root;
        endmethod

        method ActionValue#(Maybe#(Bit#(HashWidth))) 
            debug_get_hash(Level level, TreeIndex index);
            let h <- hcache.get_hash(level, index);
            return h;
        endmethod

        method VerifyState debug_state();
            return rg_state;
        endmethod

    endmodule
endpackage
