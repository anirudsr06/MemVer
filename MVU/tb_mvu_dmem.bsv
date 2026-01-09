package tb_mvu_dmem;
  import FIFOF::*;
  import FIFO::*;
  import GetPut::*;
  import Connectable::*;
  import StmtFSM::*;
  import Vector::*;
  
  import dcache_types::*;
  import dmem::*;
  `include "dcache.defines"
`ifdef supervisor
  import common_tlb_types::*;
`endif

  // Simulated Memory Module
  interface Ifc_sim_memory;
    interface Put#(DCache_mem_readreq#(`paddr)) put_read_req;
    interface Get#(DCache_mem_readresp#(`dbuswidth)) get_read_resp;
  endinterface

  (*synthesize*)
  module mk_sim_memory(Ifc_sim_memory);
    
    FIFOF#(DCache_mem_readreq#(`paddr)) ff_read_req <- mkFIFOF;
    FIFOF#(DCache_mem_readresp#(`dbuswidth)) ff_read_resp <- mkFIFOF;
    
    Reg#(Bit#(8)) rg_burst_count <- mkReg(0);
    Reg#(DCache_mem_readreq#(`paddr)) rg_current_req <- mkReg(?);
    
    rule rl_handle_read_request(ff_read_req.notEmpty && rg_burst_count == 0);
      let req = ff_read_req.first;
      ff_read_req.deq;
      
      rg_current_req <= req;
      rg_burst_count <= req.burst_len + 1;
      
      $display("===============================================================");
      $display("[SIM_MEMORY] @%0t: Received Read Request", $time);
      $display("             Address: 0x%08h", req.address);
      $display("             Burst Length: %0d beats", req.burst_len + 1);
      $display("===============================================================");
    endrule
    
    rule rl_generate_response(rg_burst_count > 0);
      Bit#(`dbuswidth) simulated_data = {rg_current_req.address[31:0], 
                                          rg_current_req.address[31:0]};
      simulated_data = simulated_data + zeroExtend(rg_burst_count);
      
      Bool is_last = (rg_burst_count == 1);
      
      let resp = DCache_mem_readresp {
        data: simulated_data,
        last: is_last,
        err: False
      };
      
      ff_read_resp.enq(resp);
      rg_burst_count <= rg_burst_count - 1;
      
      $display("[SIM_MEMORY] @%0t: Sending Response Beat %0d, Data: 0x%016h", 
               $time, rg_current_req.burst_len + 2 - rg_burst_count, simulated_data);
    endrule
    
    interface put_read_req = toPut(ff_read_req);
    interface get_read_resp = toGet(ff_read_resp);
  endmodule

  (*synthesize*)
  module mk_tb_mvu_dmem(Empty);
    
    Ifc_dmem dmem <- mkdmem(0 `ifdef pmp , replicate(0), replicate(0) `endif );
    Ifc_sim_memory sim_memory <- mk_sim_memory;
    
    mkConnection(dmem.get_read_mem_req, sim_memory.put_read_req);
    mkConnection(sim_memory.get_read_resp, dmem.put_read_mem_resp);
    
    Reg#(Bit#(32)) rg_test_count <- mkReg(0);
    Reg#(Bool) rg_test_done <- mkReg(False);
    Reg#(Bool) rg_cache_enable <- mkReg(True);
    
    // *** ALWAYS-ENABLED RULES (Outside FSM) ***
    (* fire_when_enabled, no_implicit_conditions *)
    rule rl_always_curr_priv;
      dmem.ma_curr_priv(2'b11);  // Machine mode - MUST fire every cycle
    endrule
    
    (* fire_when_enabled, no_implicit_conditions *)
    rule rl_always_cache_enable;
      dmem.ma_cache_enable(rg_cache_enable);  // MUST fire every cycle
    endrule
    
  `ifdef supervisor
    (* fire_when_enabled, no_implicit_conditions *)
    rule rl_always_satp;
      dmem.ma_satp_from_csr(0);  // Bare mode - MUST fire every cycle
    endrule
    
    (* fire_when_enabled, no_implicit_conditions *)
    rule rl_always_mstatus;
      dmem.ma_mstatus_from_csr(0);  // MUST fire every cycle
    endrule
    
    // Handle TLB requests
    rule rl_provide_tlb_response;
      let req <- dmem.get_req_to_ptw.get();
      dmem.put_resp_from_ptw.put(PTWalk_tlb_response{
        pte: truncate(req.address),
        trap: False,
        cause: 0,
        levels: 0
      });
      $display("[TB] TLB: Identity mapping for 0x%h", req.address);
    endrule
  `endif
    
    Stmt test_sequence = 
    seq
      $display("\n===============================================================");
      $display("||       MVU-DMEM Integration Testbench Started            ||");
      $display("===============================================================\n");
      
      $display("[TB] Cache enabled, privilege mode: Machine");
      
      delay(20);
      
      $display("\n===============================================================");
      $display("|| TEST 1: Load Request (Expected Cache Miss)              ||");
      $display("===============================================================");
      
      action
        Bit#(`vaddr) test_addr1 = 'h1000;
        let req = DMem_request {
          address: test_addr1,
          epochs: 0,
          size: 3'b010,
          fence: False,
          access: 2'b00,
          writedata: 0
          `ifdef atomic
            , atomic_op: 0
          `endif
          `ifdef supervisor
            , sfence: False
            , ptwalk_req: False
            , ptwalk_trap: False
          `endif
        };
        dmem.put_core_req.put(req);
        $display("[TB] @%0t: Load request sent to 0x%08h", $time, test_addr1);
      endaction
      
      $display("[TB] @%0t: Waiting for response...", $time);
      
      action
        let resp <- dmem.get_core_resp.get();
        $display("\n[TB] @%0t: *** RECEIVED RESPONSE ***", $time);
        $display("     Data: 0x%016h", resp.word);
        $display("     Trap: %b", resp.trap);
        if (resp.trap) begin
          $display("     Cause: 0x%h", resp.cause);
          $display("     TEST 1 FAILED");
        end
        else
          $display("     TEST 1 PASSED");
      endaction
      
      delay(10);
      
      $display("\n===============================================================");
      $display("|| All Tests Completed                                      ||");
      $display("===============================================================\n");
      
      rg_test_done <= True;
    endseq;
    
    FSM test_fsm <- mkFSM(test_sequence);
    
    rule rl_start_test(rg_test_count == 0);
      test_fsm.start;
      rg_test_count <= 1;
    endrule
    
    rule rl_finish_test(rg_test_done);
      $display("[TB] Testbench completed at time %0t", $time);
      $finish(0);
    endrule
    
  endmodule

endpackage

