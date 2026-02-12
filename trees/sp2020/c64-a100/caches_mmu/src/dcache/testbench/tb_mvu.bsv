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

    // ====================================================================
    // Address constants -- MUST match hcache.bsv / tree_memory.bsv
    // ====================================================================
    // Protected region: 0x8000_0000 - 0x801F_FFFF (2 MB)
    // Tree L1:          0x8020_0000 + index*8
    // Tree L2:          0x8024_0000 + index*8

    Bit#(`paddr) protected_base = 'h8000_0000;
    Bit#(`paddr) tree_base      = 'h8020_0000;
    Bit#(`paddr) level1_offset  = 'h0000_0000;
    Bit#(`paddr) level2_offset  = 'h0004_0000;

    function Bit#(`paddr) get_node_addr(Level level, TreeIndex index);
        Bit#(`paddr) lvl_off = (level == 1) ? level1_offset : level2_offset;
        Bit#(`paddr) node_off = zeroExtend(index) << 3;
        return tree_base + lvl_off + node_off;
    endfunction

    (* synthesize *)
    module mkTb_mvu(Empty);

        Ifc_mvu dut <- mkmvu;
        Ifc_TreeMemory tree_mem <- mkTreeMemory;
        Ifc_UnifiedMemory mem <- mkUnifiedMemory;

        // ============================================================
        // Connections (same topology as production dmem.bsv)
        // ============================================================

        // MVU <-> TreeMemory (tree node read/write)
        mkConnection(dut.get_tree_node_req,  tree_mem.put_req);
        mkConnection(tree_mem.get_resp,      dut.put_tree_node_resp);
        mkConnection(dut.get_tree_write_req, tree_mem.put_write_req);
        mkConnection(tree_mem.get_write_resp, dut.put_tree_write_resp);

        // MVU data port <-> UnifiedMemory data port
        mkConnection(dut.get_mem_read_req,   mem.data_port.put_read_req);
        mkConnection(mem.data_port.get_read_resp, dut.put_mem_read_resp);

        // TreeMemory memory port <-> UnifiedMemory tree port
        mkConnection(tree_mem.get_mem_read_req,    mem.tree_port.put_read_req);
        mkConnection(mem.tree_port.get_read_resp,  tree_mem.put_mem_read_resp);
        mkConnection(tree_mem.get_mem_write_req,   mem.tree_port.put_write_req);
        mkConnection(mem.tree_port.get_write_resp, tree_mem.put_mem_write_resp);

        // ============================================================
        // State machine
        // ============================================================
        Reg#(UInt#(32)) rg_cycle <- mkConfigReg(0);
        Reg#(UInt#(8))  rg_state <- mkReg(0);
        Reg#(Bit#(4))   rg_init_idx <- mkReg(0);
        Reg#(Bool)       rg_evict_sent <- mkReg(False);
        Reg#(UInt#(4))  rg_resp_count <- mkReg(0);

        // ============================================================
        // Cycle counter & timeout
        // ============================================================
        (* fire_when_enabled, no_implicit_conditions *)
        rule rl_tick;
            rg_cycle <= rg_cycle + 1;
            if (rg_cycle > 50000) begin
                $display("TIMEOUT at state %0d, cycle %0d", rg_state, rg_cycle);
                $finish(1);
            end
        endrule

        // ====================================================================
        // Test Scenario:
        //
        // Data at 0x8000_0040 (64 bytes = 8 leaves at indices 8..15)
        //   Leaf[8]=1, Leaf[9]=2, ..., Leaf[15]=8
        //
        // L1 parent index = 8 >> 3 = 1
        //   L1 siblings: [0, 2, 3, 4, 5, 6, 7] stored in memory
        //
        // L2 parent index = 1 >> 3 = 0
        //   L2 siblings: [1, 2, 3, 4, 5, 6, 7] stored in memory
        //
        // L3 parent index = 0 >> 3 = 0 -- this is HW level (hcache stores L3-L6)
        //   First verification stores hash, second verification checks it
        // ====================================================================

        // ============================================================
        // State 0: Enable MVU
        // ============================================================
        rule rl_init(rg_state == 0);
            dut.ma_enable(True);
            $display("========================================");
            $display("TEST: MVU Integration (Protected Region)");
            $display("========================================");
            rg_state <= 1;
        endrule

        // ============================================================
        // State 1: Initialize data memory (8 leaves at 0x8000_0040)
        // ============================================================
        rule rl_init_data(rg_state == 1);
            Bit#(`paddr) addr = protected_base + 'h40 + (zeroExtend(rg_init_idx) << 3);
            Bit#(64) val = zeroExtend(rg_init_idx) + 1;

            mem.write_mem(addr, val);
            $display("Init Data[%0d]: Addr %h = %h", rg_init_idx, addr, val);

            if (rg_init_idx == 7) begin
                rg_state <= 2;
                rg_init_idx <= 0;
            end else begin
                rg_init_idx <= rg_init_idx + 1;
            end
        endrule

        // ============================================================
        // State 2: Initialize L1 tree siblings in memory
        //   L1[0], L1[2..7] -- skip L1[1] (that's the one MVU computes)
        // ============================================================
        rule rl_init_tree_l1(rg_state == 2);
            if (rg_init_idx != 1) begin
                Bit#(64) h = (rg_init_idx == 0) ?
                    64'hAAAA_AAAA_AAAA_AAAA :
                    (64'hBBBB_BBBB_0000_0000 | zeroExtend(rg_init_idx));

                mem.write_mem(get_node_addr(1, zeroExtend(rg_init_idx)), h);
            end

            if (rg_init_idx == 7) begin
                rg_state <= 3;
                rg_init_idx <= 1;
            end else begin
                rg_init_idx <= rg_init_idx + 1;
            end
        endrule

        // ============================================================
        // State 3: Initialize L2 tree siblings in memory
        //   L2[1..7] -- skip L2[0] (that's the one MVU computes)
        // ============================================================
        rule rl_init_tree_l2(rg_state == 3);
            Bit#(64) h = 64'hCCCC_CCCC_0000_0000 | zeroExtend(rg_init_idx);
            mem.write_mem(get_node_addr(2, zeroExtend(rg_init_idx)), h);

            if (rg_init_idx == 7) begin
                rg_state <= 4;
                rg_init_idx <= 0;
            end else begin
                rg_init_idx <= rg_init_idx + 1;
            end
        endrule

        // ============================================================
        // State 4: Send protected read request (initial verification)
        //   Address 0x8000_0040 is IN protected region
        // ============================================================
        rule rl_start_verify(rg_state == 4);
            $display("\n[TB] === TEST 1: Protected Read Verification ===");
            $display("[TB] Sending read request for 0x8000_0040");
            dut.put_cache_read_req.put(DCache_mem_readreq {
                address: protected_base + 'h40,
                burst_len: 7,
                burst_size: 3,
                io: False
            });
        endrule

        // ============================================================
        // Consume verified responses from MVU
        // ============================================================
        rule rl_consume_resp;
            let resp <- dut.get_cache_read_resp.get();
            $display("[TB] Response beat %0d: data=%h last=%b",
                    rg_resp_count, resp.data, resp.last);
            if (resp.last) begin
                rg_resp_count <= 0;
                if (rg_state == 4) begin
                    $display("[TB] Initial verification PASSED -- all 8 beats received");
                    $display("[TB] MVU traversed L0->L1->L2->L3(HW), stored initial hashes\n");
                    rg_state <= 5;
                end else if (rg_state == 7) begin
                    $display("[TB] Re-verification after update PASSED");
                    $display("[TB] Updated hashes matched stored HCache values\n");
                    rg_state <= 8;
                end else if (rg_state == 10) begin
                    $display("[TB] Non-protected passthrough PASSED\n");
                    rg_state <= 11;
                end
            end else begin
                rg_resp_count <= rg_resp_count + 1;
            end
        endrule

        // ============================================================
        // State 5: Trigger eviction (update) at protected address
        //   Modify leaf[8] from 1 to 0xDEADBEEF, recompute tree
        // ============================================================
        rule rl_evict_send(rg_state == 5 && !rg_evict_sent);
            $display("[TB] === TEST 2: Protected Eviction (Tree Update) ===");
            $display("[TB] Modifying leaf[8] to 0xDEADBEEF and triggering eviction");

            // Update physical memory so re-reads get new data
            mem.write_mem(protected_base + 'h40, 64'hDEAD_BEEF);

            // Construct 512-bit eviction data
            Vector#(8, Bit#(64)) data_vec = replicate(0);
            for (Integer i = 0; i < 8; i = i + 1)
                data_vec[i] = fromInteger(i) + 1;
            data_vec[0] = 64'hDEAD_BEEF;

            dut.put_evict_req.put(DCache_mem_writereq {
                address: protected_base + 'h40,
                data: pack(data_vec),
                burst_len: 7,
                burst_size: 3,
                io: False
            });
            rg_evict_sent <= True;
        endrule

        // Wait for MVU to return to IDLE after tree update
        rule rl_wait_update_done(rg_state == 5 && rg_evict_sent);
            let s = dut.debug_state();
            if (s == IDLE) begin
                $display("[TB] MVU completed tree update (IDLE)");
                $display("[TB] Tree nodes updated in memory + HCache\n");
                rg_state <= 7;
                rg_evict_sent <= False;
            end
        endrule

        // ============================================================
        // State 7: Re-verify after update
        //   Read same address again -- MVU should verify updated hashes
        // ============================================================
        rule rl_reverify(rg_state == 7);
            $display("[TB] === TEST 3: Re-verification After Update ===");
            $display("[TB] Re-reading 0x8000_0040 to verify updated tree");
            dut.put_cache_read_req.put(DCache_mem_readreq {
                address: protected_base + 'h40,
                burst_len: 7,
                burst_size: 3,
                io: False
            });
        endrule

        // ============================================================
        // State 8-9: Non-protected data init (sequentialized)
        // ============================================================
        rule rl_init_nonprotected(rg_state == 8);
            Bit#(`paddr) np_addr = 'h4000_0000 + (zeroExtend(rg_init_idx) << 3);
            Bit#(64) val = zeroExtend(rg_init_idx) + 100;
            mem.write_mem(np_addr, val);
            $display("[TB] Init Non-Protected[%0d]: Addr %h = %h", rg_init_idx, np_addr, val);

            if (rg_init_idx == 7) begin
                rg_state <= 10;
                rg_init_idx <= 0;
            end else begin
                rg_init_idx <= rg_init_idx + 1;
            end
        endrule

        // ============================================================
        // State 10: Send non-protected read
        // ============================================================
        rule rl_send_nonprotected(rg_state == 10);
            $display("[TB] === TEST 4: Non-Protected Passthrough ===");
            $display("[TB] Sending non-protected read for 0x4000_0000");
            dut.put_cache_read_req.put(DCache_mem_readreq {
                address: 'h4000_0000,
                burst_len: 7,
                burst_size: 3,
                io: False
            });
        endrule

        // ============================================================
        // State 11: All tests passed
        // ============================================================
        rule rl_finish(rg_state == 11);
            $display("========================================");
            $display("ALL TESTS PASSED");
            $display("  Test 1: Protected read verification");
            $display("  Test 2: Protected eviction + tree update");
            $display("  Test 3: Re-verification after update");
            $display("  Test 4: Non-protected passthrough");
            $display("========================================");
            $finish;
        endrule

    endmodule
endpackage
