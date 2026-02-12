package tb_mvu_dmem;
    import FIFOF::*;
    import GetPut::*;
    import Connectable::*;
    import StmtFSM::*;
    import dcache_types::*;
    import dmem::*;
    import mvu::*;
    `include "dcache.defines"

    // Mock Memory that responds with an 8-beat burst
    interface Ifc_sim_memory;
        interface Put#(DCache_mem_readreq#(`paddr)) put_read_req;
        interface Get#(DCache_mem_readresp#(`dbuswidth)) get_read_resp;
    endinterface

    module mk_sim_memory(Ifc_sim_memory);
        FIFOF#(DCache_mem_readreq#(`paddr)) ff_read_req <- mkFIFOF;
        FIFOF#(DCache_mem_readresp#(`dbuswidth)) ff_read_resp <- mkFIFOF;
        Reg#(Bit#(8)) rg_burst_count <- mkReg(0);

        rule rl_handle_req(ff_read_req.notEmpty && rg_burst_count == 0);
            let req = ff_read_req.first;
            ff_read_req.deq;
            rg_burst_count <= req.burst_len + 1;
            $display("[MEM] Received Req for %h. Starting %0d beat burst.", req.address, req.burst_len + 1);
        endrule

        rule rl_respond(rg_burst_count > 0);
            ff_read_resp.enq(DCache_mem_readresp {
                data: 64'hAAAA_BBBB_0000_0000 | extend(rg_burst_count),
                last: (rg_burst_count == 1),
                err: False
            });
            rg_burst_count <= rg_burst_count - 1;
        endrule

        interface put_read_req = toPut(ff_read_req);
        interface get_read_resp = toGet(ff_read_resp);
    endmodule

    (* synthesize *)
    module mk_tb_mvu_dmem(Empty);
        // Fixed: Added required id parameter for mkdmem
        Ifc_dmem dmem <- mkdmem(32'd0 
            `ifdef pmp
                , replicate(0), replicate(0)
            `endif
        );
        Ifc_sim_memory mem <- mk_sim_memory;

        mkConnection(dmem.get_read_mem_req, mem.put_read_req);
        mkConnection(mem.get_read_resp, dmem.put_read_mem_resp);

        Reg#(Bool) rg_done <- mkReg(False);
        Bit#(`vaddr) test_addr = 32'h80000000;

        Stmt test_seq = seq
            $display("[TB] Sending Load to Address 0x80000000...");
            action
                // Fixed: Added all required fields for DMem_request
                let req = DMem_request { 
                    address: test_addr, 
                    epochs: 0, 
                    access: 0, 
                    size: 3, 
                    writedata: 0,
                    fence: False
                    `ifdef atomic
                        , atomic_op: ?
                    `endif
                    `ifdef supervisor
                        , ptwalk_req: False,
                        ptwalk_trap: False,
                        sfence: False
                    `endif
                };
                dmem.put_core_req.put(req);
            endaction

            action
                let resp <- dmem.get_core_resp.get();
                $display("[TB] Core Received Data: %h", resp.word);
            endaction
            
            rg_done <= True;
        endseq;

        FSM test_fsm <- mkFSM(test_seq);
        
        rule rl_start_test;
            test_fsm.start();
        endrule
        
        rule rl_finish(rg_done); 
            $display("[TB] Test completed successfully");
            $finish; 
        endrule
    endmodule
endpackage
