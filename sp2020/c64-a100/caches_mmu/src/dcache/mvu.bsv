/*
Implements recursive verification from leaves to root with on-demand sibling fetching.

Architecture:
1. On cache miss: Fetch 64-byte cache line (8 leaves)
2. Compute hashes for these 8 leaves
3. Compute parent hash from these 8 children
4. Fetch 7 sibling nodes from memory (the other children at this level)
5. Compute next level parent
6. Repeat until reaching HCache levels
7. Verify against stored hash or store if first time
8. Continue to root

Memory Interface:
- Data fetches: Standard cache line requests
- Tree node fetches: Special requests for sibling nodes
*/

package mvu;
    import FIFOF::*;
    import FIFO::*;
    import GetPut::*;
    import Assert::*;
    import Vector::*;
    import dcache_types::*;
    import hcache::*;
    `include "dcache.defines"

    typedef 8 Arity;        // 8 children per parent
    typedef 64 HashWidth;
    typedef Bit#(4) Level;
    typedef Bit#(18) TreeIndex;

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
        ACCUMULATING,      // Collecting 8 beats to form leaves
        COMPUTE_L0_PARENT, // Hash the 8 leaves together
        FETCH_SIBLINGS,    // Request siblings from memory
        WAIT_SIBLINGS,     // Wait for sibling response
        COMPUTE_PARENT,    // Hash current level's 8 nodes
        CHECK_PARENT,      // Verify against stored or store new
        UPDATE_NODE,       // Write new hash to memory/storage
        WAIT_UPDATE_ACK,   // Wait for write completion
        PROPAGATE_UP,      // Move to next level
        VERIFY_ROOT,       // Final root check
        COMPLETE,
        FORWARD_TO_CACHE   // Done
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

        // Leaf accumulation (8 leaves from cache line)
        Reg#(Vector#(Arity, Bit#(HashWidth))) rg_leaves <- mkReg(replicate(0));
        Reg#(UInt#(4)) rg_beat_count <- mkReg(0);

        // Current verification path
        Reg#(Level) rg_current_level <- mkReg(0);
        Reg#(TreeIndex) rg_current_index <- mkReg(0);
        
        // Current node group (8 siblings at current level)
        Reg#(Vector#(Arity, Bit#(HashWidth))) rg_node_group <- mkReg(replicate(0));
        Reg#(Vector#(Arity, Bool)) rg_node_valid <- mkReg(replicate(False));
        Reg#(Bit#(HashWidth)) rg_computed_parent <- mkReg(0);

        Reg#(Vector#(Arity, DCache_mem_readresp#(`dbuswidth))) rg_buffered_responses <- mkReg(replicate(?));
        Reg#(UInt#(4)) rg_forward_beat <- mkReg(0);

        Ifc_HCache hcache <- mkHCache;

        // Hash function: XOR all 8 children (placeholder for real hash)
        function Bit#(HashWidth) compute_hash(Vector#(Arity, Bit#(HashWidth)) children);
            Bit#(HashWidth) result = 0;
            for (Integer i = 0; i < valueOf(Arity); i = i + 1)
                result = result ^ children[i];
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

        //=====================================================
        // RULE: Handle Eviction Request (Start Update)
        //=====================================================
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
                Vector#(Arity, Bit#(HashWidth)) leaves = unpack(req.data);
                rg_leaves <= leaves;
                
                rg_state <= COMPUTE_L0_PARENT;
                
                $display("[MVU] UPDATE START: Eviction at addr=%h, base_leaf_idx=%0d", 
                        req.address, leaf_idx);
            end else begin
                $display("[MVU] Ignoring eviction at %h (not protected)", req.address);
            end
        endrule

        //=====================================================
        // RULE: Forward request to memory
        //=====================================================
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
                rg_leaves <= replicate(0);
                rg_state <= ACCUMULATING;
                
                $display("[MVU] Start verification: addr=%h, base_leaf_idx=%0d", 
                        req.address, leaf_idx);
            end else begin
                rg_from_protected <= False;
            end
            
            rg_pending_req <= tagged Valid req;
            ff_req_to_mem.enq(req);
        endrule

        //=====================================================
        // RULE: Accumulate leaves from memory responses
        //=====================================================
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
                
                Vector#(Arity, Bit#(HashWidth)) leaves = rg_leaves;
                leaves[rg_beat_count] = leaf_hash;
                rg_leaves <= leaves;
                
                Vector#(Arity, DCache_mem_readresp#(`dbuswidth)) buffered = rg_buffered_responses;
                buffered[rg_beat_count] = resp;
                rg_buffered_responses <= buffered;

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

        //=====================================================
        // RULE: Compute Level 0 parent from 8 leaves
        //=====================================================
        rule rl_compute_l0_parent(rg_state == COMPUTE_L0_PARENT);

            let parent_hash = compute_hash(rg_leaves);

            // Parent index: base_leaf_index / 8
            TreeIndex parent_idx = rg_base_leaf_index >> 3;

            $display("[MVU] L0 parent[%0d] = %h (from leaves %0d-%0d)",
                    parent_idx, parent_hash,
                    rg_base_leaf_index, rg_base_leaf_index + 7);

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

        //=====================================================
        // RULE: Request sibling nodes from memory
        //=====================================================
        rule rl_fetch_siblings(rg_state == FETCH_SIBLINGS);
            if (hcache.is_hw_level(rg_current_level)) begin
                // We're at HW level
                $display("[MVU] Reached HW level %0d", rg_current_level);
                if (rg_is_update)
                    rg_state <= UPDATE_NODE;
                else
                    rg_state <= CHECK_PARENT;
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

        //=====================================================
        // RULE: Receive sibling nodes from memory
        //=====================================================
        rule rl_wait_siblings(rg_state == WAIT_SIBLINGS);
            let resp = ff_tree_resp.first;
            ff_tree_resp.deq;
            
            // Merge received siblings with our computed node
            Vector#(Arity, Bit#(HashWidth)) group = rg_node_group;
            Vector#(Arity, Bool) valid = rg_node_valid;
            
            for (Integer i = 0; i < valueOf(Arity); i = i + 1) begin
                if (resp.valid[i]) begin
                    // If update mode, we overwrite OLD hash at our pos with NEW hash
                    // But in UPDATE mode, rg_node_group ALREADY has correct new hash at our_pos
                    // Siblings are neighbors. Masks ensure we don't overwrite neighbors?
                    // But we requested all siblings EXCEPT our position usually?
                    // Actually mask usage is optional in current tree_memory.
                    // But group[i] overwrites.
                    // Important: Don't overwrite our computed hash with old hash from memory!
                    // In Verification, it doesn't matter (should match).
                    // In Update, it DOES matter.
                    // Currently `child_position` logic ensures `valid[pos]` is True.
                    // If memory returns data for our pos, we should IGNORE it?
                    // `tree_memory` fetches 8 nodes.
                    // `resp` has all 8.
                    // Our `rg_node_group` has our calculated node at `pos`.
                    
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

        //=====================================================
        // RULE: Compute parent hash from 8 siblings
        //=====================================================
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

        //=====================================================
        // RULE: Check/store parent hash
        //=====================================================
        rule rl_check_parent(rg_state == CHECK_PARENT);
            if (hcache.is_hw_level(rg_current_level)) begin
                // Check against stored hash
                let stored <- hcache.get_hash(rg_current_level, rg_current_index);
                
                case (stored) matches
                    tagged Invalid: begin
                        // First time - store it
                        hcache.set_hash(rg_current_level, rg_current_index, rg_computed_parent);
                        $display("[MVU] Stored new hash at L%0d[%0d]", 
                                rg_current_level, rg_current_index);
                    end
                    tagged Valid .h: begin
                        // Verify against stored
                        dynamicAssert(h == rg_computed_parent, 
                                    "Hash mismatch");
                        $display("[MVU] Hash verified at L%0d[%0d]", 
                                rg_current_level, rg_current_index);
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

        //=====================================================
        // RULE: Update Node (Write Back)
        //=====================================================
        rule rl_update_node(rg_state == UPDATE_NODE);
            if (hcache.is_hw_level(rg_current_level)) begin
                // Update HW hash
                hcache.set_hash(rg_current_level, rg_current_index, rg_computed_parent);
                $display("[MVU] UPDATE: Updated HW Hash at L%0d[%0d] = %h", 
                        rg_current_level, rg_current_index, rg_computed_parent);
                
                // Check root after HW update
                if (rg_current_level >= hcache.get_tree_height()) begin
                    rg_state <= COMPLETE;
                end else begin
                    rg_state <= PROPAGATE_UP;
                end
            end else begin
                // Write to tree memory
                ff_tree_write.enq(TreeNodeWrite {
                    level: rg_current_level,
                    index: rg_current_index,
                    hash: rg_computed_parent
                });
                $display("[MVU] UPDATE: Wrote Tree Node L%0d[%0d] = %h", 
                        rg_current_level, rg_current_index, rg_computed_parent);
                
                // Wait for acknowledgment
                rg_state <= WAIT_UPDATE_ACK;
            end
        endrule

        //=====================================================
        // RULE: Wait for Write Acknowledgment
        //=====================================================
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

        //=====================================================
        // RULE: Propagate to next level
        //=====================================================
        rule rl_propagate_up(rg_state == PROPAGATE_UP);
            TreeIndex next_index = rg_current_index >> 3; // Parent index
            Level next_level = rg_current_level + 1;
            
            // Setup node group for next level
            Vector#(Arity, Bit#(HashWidth)) group = replicate(0);
            Vector#(Arity, Bool) valid = replicate(False);
            Bit#(3) pos = child_position(rg_current_index);
            group[pos] = rg_computed_parent;
            valid[pos] = True;
            
            rg_current_level <= next_level;
            rg_current_index <= next_index;
            rg_node_group <= group;
            rg_node_valid <= valid;
            
            $display("[MVU] Propagating to L%0d[%0d]", next_level, next_index);
            rg_state <= FETCH_SIBLINGS;
        endrule

        //=====================================================
        // RULE: Verify root
        //=====================================================
        rule rl_verify_root(rg_state == VERIFY_ROOT);
            if (rg_trusted_root != 0) begin
                dynamicAssert(rg_computed_parent == rg_trusted_root,
                            "ROOT VERIFICATION FAILED!");
                $display("[MVU] ROOT VERIFIED: %h", rg_computed_parent);
            end else begin
                $display("[MVU] Root computed (no trusted root set): %h", rg_computed_parent);
            end
            
            rg_state <= COMPLETE;
        endrule

        //=====================================================
        // RULE: Complete verification
        //=====================================================
        rule rl_complete(rg_state == COMPLETE);
            $display("[MVU] Operation complete\n");
            
            if (rg_is_update) begin
                 rg_state <= IDLE;
                 rg_is_update <= False;
            end else begin
                 rg_state <= FORWARD_TO_CACHE;
            end
            
            rg_pending_req <= tagged Invalid;
            rg_from_protected <= False;
        endrule

        //=====================================================
        // RULE: Forward unprotected responses
        //=====================================================
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

        //=====================================================
        // RULE: Forward buffered responses to cache after verification
        //=====================================================
        rule rl_forward_verified(rg_state == FORWARD_TO_CACHE);
            let resp = rg_buffered_responses[rg_forward_beat];
            ff_resp_to_cache.enq(resp);
            
            $display("[MVU] Forwarding verified beat %0d to cache", rg_forward_beat);
            
            if (resp.last) begin
                rg_state <= IDLE;
                rg_pending_req <= tagged Invalid;
                rg_from_protected <= False;
                rg_forward_beat <= 0;
            end else begin
                rg_forward_beat <= rg_forward_beat + 1;
            end
        endrule
        
        //=====================================================
        // Interface
        //=====================================================
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
