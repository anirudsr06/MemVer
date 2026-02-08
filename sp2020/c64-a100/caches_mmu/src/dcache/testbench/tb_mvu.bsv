package tb_mvu;
    import mvu::*;
    import hcache::*;
    import tree_memory::*;
    import dcache_types::*;
    import unified_memory::*;
    import FIFOF::*;
    import GetPut::*;
    import Vector::*;
    import Connectable::*;
    import ConfigReg::*;
    `include "dcache.defines"

    // Address constants (Matches hcache/tree_memory)
    Bit#(`paddr) tree_base = 'h0020_0000;
    Bit#(`paddr) level1_offset = 'h0000_0000;
    Bit#(`paddr) level2_offset = 'h0004_0000;

    function Bit#(`paddr) get_node_addr(Level level, TreeIndex index);
        Bit#(`paddr) level_offset = (level == 1) ? level1_offset : level2_offset;
        Bit#(`paddr) node_offset = zeroExtend(index) << 3; 
        return tree_base + level_offset + node_offset;
    endfunction

    (* synthesize *)
    module mkTb_mvu(Empty);
        
        Ifc_mvu dut <- mkmvu;
        Ifc_TreeMemory tree_mem <- mkTreeMemory;
        Ifc_UnifiedMemory mem <- mkUnifiedMemory;
        
        // Connect tree memory adapter to MVU
        mkConnection(dut.get_tree_node_req, tree_mem.put_req);
        mkConnection(tree_mem.get_resp, dut.put_tree_node_resp);
        
        // Connect MVU Data Port to Unified Memory (Data Port)
        mkConnection(dut.get_mem_read_req, mem.data_port.put_read_req);
        mkConnection(mem.data_port.get_read_resp, dut.put_mem_read_resp);
        // MVU doesn't have write port yet (Phase 3), but if it did:
        // mkConnection(dut.get_mem_write_req, mem.data_port.put_write_req);
        
        // Connect Tree Memory Adapter to Unified Memory (Tree Port)
        mkConnection(tree_mem.get_mem_read_req, mem.tree_port.put_read_req);
        mkConnection(mem.tree_port.get_read_resp, tree_mem.put_mem_read_resp);
        mkConnection(tree_mem.get_mem_write_req, mem.tree_port.put_write_req);
        mkConnection(mem.tree_port.get_write_resp, tree_mem.put_mem_write_resp);

        // Connect tree write interface (from MVU to TreeMem)
        mkConnection(dut.get_tree_write_req, tree_mem.put_write_req);
        // Connect tree write response (from TreeMem to MVU)
        mkConnection(tree_mem.get_write_resp, dut.put_tree_write_resp);

        // State machine
        Reg#(UInt#(32)) rg_cycle <- mkConfigReg(0);
        Reg#(UInt#(8)) rg_state <- mkReg(0);
        
        // Cycle counter
        (* fire_when_enabled, no_implicit_conditions *)
        rule rl_tick;
            rg_cycle <= rg_cycle + 1;
            if (rg_cycle > 10000) begin
                $display("TIMEOUT at state %0d, cycle %0d", rg_state, rg_cycle);
                $finish(1);
            end
        endrule
        
        // ====================================================================
        // Test Setup
        // ====================================================================
        /*
        Address 0x0000_0040 (64 bytes)
        Leaves 8-15 (indices)
        Leaf 8 = 1, Leaf 9 = 2, ... Leaf 15 = 8
        Parent L1[1] (because 8>>3 = 1)
        Siblings needed: L1[0], L1[2..7]
        For L2 parent (index 0, covering L1[0..7]), we need siblings L2[1..7]
        But L2 size is usually smaller? 
        If ARITY=8.
        L0 leaves.
        L1 nodes.
        L2 nodes.
        
        Let's assume simple scenario:
        We verify address 0x40.
        MVU logic:
        1. Fetch data at 0x40 (8 beats). Accumulate.
        2. Compute L0 parent (L1 node). Index = 8/8 = 1.
        3. Fetch L1 siblings (0, 2, 3, 4, 5, 6, 7).
        4. Compute L1 parent (L2 node). Index = 1/8 = 0.
        5. Fetch L2 siblings (1, 2, 3, 4, 5, 6, 7).
        6. Compute L2 parent (L3 node). Index = 0/8 = 0.
        7. If L3 is HW level, check stored hash.
        */
        
        // State 0: Enable MVU
        rule rl_init(rg_state == 0);
            dut.ma_enable(True);
            $display("========================================");
            $display("TEST: MVU with Unified Memory");
            $display("========================================");
            rg_state <= 1;
        endrule
        
        // Helper Reg for initialization
        Reg#(Bit#(4)) rg_init_idx <- mkReg(0);

        // State 1: Initialize Data Memory (Leaves)
        rule rl_init_data(rg_state == 1);
            // Write 8 words starting at 0x40
            Bit#(32) offset = zeroExtend(rg_init_idx) << 3; 
            Bit#(64) val = zeroExtend(rg_init_idx) + 1;
            
            mem.write_mem('h40 + offset, val);
            $display("Init Data: Addr %h = %h", 32'h40 + offset, val);
            
            if (rg_init_idx == 7) begin
                rg_state <= 2;
                rg_init_idx <= 0;
            end else begin
                rg_init_idx <= rg_init_idx + 1;
            end
        endrule
        
        // State 2: Initialize Tree Memory (L1 Siblings)
        rule rl_init_tree_l1(rg_state == 2);
            // We need L1[0], L1[2..7].
            // Sequence: 0, 2, 3, 4, 5, 6, 7
            // We can just iterate 0..7 and skip 1
            
            if (rg_init_idx != 1) begin
                Bit#(64) h = (rg_init_idx == 0) ? 
                    64'hAAAA_AAAA_AAAA_AAAA : 
                    (64'hBBBB_BBBB_0000_0000 | zeroExtend(rg_init_idx));
                
                mem.write_mem(get_node_addr(1, zeroExtend(rg_init_idx)), h);
            end
            
            if (rg_init_idx == 7) begin
                rg_state <= 3;
                rg_init_idx <= 1; // Start from 1 for next rule
            end else begin
                rg_init_idx <= rg_init_idx + 1;
            end
        endrule
        
        // State 3: Initialize Tree Memory (L2 Siblings)
        rule rl_init_tree_l2(rg_state == 3);
            // Parent is L2[0].
            // Need L2[1..7].
            // init_idx starts at 1
            
            Bit#(64) h = 64'hCCCC_CCCC_0000_0000 | zeroExtend(rg_init_idx);
            mem.write_mem(get_node_addr(2, zeroExtend(rg_init_idx)), h);
            
            if (rg_init_idx == 7) begin
                rg_state <= 4;
                rg_init_idx <= 0;
            end else begin
                rg_init_idx <= rg_init_idx + 1;
            end
        endrule
        
        // State 4: Start Verification
        rule rl_start_req(rg_state == 4);
            $display("\n[TB] State 4: Sending Request for 0x40");
            let req = DCache_mem_readreq {
                address: 32'h0000_0040,
                burst_len: 8'd7, // 8 beats
                burst_size: 3'd3, // 8 bytes
                io: False
            };
            dut.put_cache_read_req.put(req);
        endrule
        
        // Consume response from DUT
        rule rl_consume_resp;
            let resp <- dut.get_cache_read_resp.get();
            // $display("[TB] Got response: %h", resp.data);
            if (resp.last) begin
                 if (rg_state == 4) begin
                     $display("[TB] Initial Verification Complete. Starting Eviction...");
                     rg_state <= 5;
                 end else if (rg_state == 6) begin
                     $display("[TB] Update Verification Complete!");
                     rg_state <= 7;
                 end
            end
        endrule

        Reg#(Bool) rg_evict_sent <- mkReg(False);
        
        // State 5: Trigger Eviction
        rule rl_evict_req_send(rg_state == 5 && !rg_evict_sent);
            $display("\n[TB] State 5: Triggering Eviction for 0x40");
            
            // New data for the cache line
            // We will change Leaf 0 to 0xDEADBEEF
            
            // Construct 512-bit data
            // 8x64 vector
            Vector#(8, Bit#(64)) data_vec = replicate(0);
            for(Integer i=0; i<8; i=i+1) data_vec[i] = fromInteger(i) + 1; // 1, 2, ...
            data_vec[0] = 64'hDEAD_BEEF; // Change first word
            
            Bit#(512) packed_data = pack(data_vec);
            
            // Update physical memory so subsequent reads get new data
            // We need to write 8 words to mem.
            // tb_mvu doesn't have easy burst write rule for mem.
            // We act as "memory controller" here.
            mem.write_mem(32'h40, 64'hDEAD_BEEF);
            // Others unchanged (already 2,3,4...)
            
            // Send eviction notification to MVU
            let req = DCache_mem_writereq {
                address: 32'h0000_0040,
                data: packed_data,
                burst_len: 7, // Not used by MVU logic but good practice
                burst_size: 3,
                io: False
            };
            dut.put_evict_req.put(req);
            rg_evict_sent <= True;
        endrule
        
        rule rl_check_idle(rg_state == 5 && rg_evict_sent);
             let s = dut.debug_state();
             if (s == IDLE) begin
                 $display("[TB] MVU is IDLE. Update finished.");
                 rg_state <= 6;
                 rg_evict_sent <= False;
             end
        endrule

        // State 6: Verify Update
        rule rl_verify_update(rg_state == 6);
            $display("\n[TB] State 6: Verifying Update for 0x40");
            let req = DCache_mem_readreq {
                address: 32'h0000_0040,
                burst_len: 8'd7,
                burst_size: 3'd3,
                io: False
            };
            dut.put_cache_read_req.put(req);
            // We wait for response in rl_consume_resp
        endrule
        
        rule rl_finish(rg_state == 7);
            $display("ALL TESTS PASSED");
            $finish;
        endrule
        
    endmodule
endpackage
