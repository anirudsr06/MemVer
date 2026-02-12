/*
Memory Verification Unit (MVU)
Acts as a transparent pipeline between dcache and memory fabric
*/
package mvu;
    import FIFOF::*;
    import FIFO::*;
    import GetPut::*;
    import dcache_types::*;
    `include "dcache.defines"

  // MVU Interface
    interface Ifc_mvu;
    // Upstream interfaces (connected to dcache)
    interface Put#(DCache_mem_readreq#(`paddr)) put_cache_read_req;
    interface Get#(DCache_mem_readresp#(`dbuswidth)) get_cache_read_resp;

    // Downstream interfaces (connected to memory fabric)
    interface Get#(DCache_mem_readreq#(`paddr)) get_mem_read_req;
    interface Put#(DCache_mem_readresp#(`dbuswidth)) put_mem_read_resp;

    // Control and monitoring
    method Action ma_enable(Bool en);
    method Bool mv_busy;
endinterface

(*synthesize*)
module mkmvu(Ifc_mvu);

    // FIFOs for buffering requests and responses
    FIFOF#(DCache_mem_readreq#(`paddr)) ff_req_from_cache <- mkFIFOF;
    FIFOF#(DCache_mem_readreq#(`paddr)) ff_req_to_mem <- mkFIFOF;
    FIFOF#(DCache_mem_readresp#(`dbuswidth)) ff_resp_from_mem <- mkFIFOF;
    FIFOF#(DCache_mem_readresp#(`dbuswidth)) ff_resp_to_cache <- mkFIFOF;

    // State registers
    Reg#(Bool) rg_mvu_enabled <- mkReg(True);
    Reg#(Maybe#(DCache_mem_readreq#(`paddr))) rg_pending_req <- mkReg(tagged Invalid);

    // Rule: Forward read request from cache to memory
    // Here you can add verification of the request
    rule rl_forward_request(ff_req_from_cache.notEmpty && !isValid(rg_pending_req));
        let req = ff_req_from_cache.first;
        ff_req_from_cache.deq;

      // Store request metadata for response verification
        rg_pending_req <= tagged Valid req;

      // Forward to memory
        ff_req_to_mem.enq(req);
        
       $display("===============================================================");
      $display("[MVU] @%0t: INTERCEPTED CACHE MISS REQUEST", $time);
      $display("      Address: 0x%08h", req.address);
      $display("      Burst Length: %0d beats", req.burst_len + 1);
      $display("      IO Request: %b", req.io);
      $display("      >> Forwarding to Memory...");
      $display("===============================================================");
      // $display("[MVU] Read Request - Addr: 0x%h, BurstLen: %d, IO: %b", 
      //         req.address, req.burst_len, req.io);
    endrule

    // Rule: Verify and forward response from memory to cache
    rule rl_verify_response(ff_resp_from_mem.notEmpty && isValid(rg_pending_req));
        let resp = ff_resp_from_mem.first;
        ff_resp_from_mem.deq;
        let req = validValue(rg_pending_req);

      // ============================================
      // YOUR VERIFICATION LOGIC GOES HERE
      // Example: Check integrity, decrypt, verify MAC, etc.
        Bool verification_passed = True;

        if (rg_mvu_enabled) begin
        // Add your verification function here
        // verification_passed = fn_verify_memory_data(req.address, resp.data);
            $display("===============================================================");
            $display("[MVU] @%0t: VERIFYING MEMORY RESPONSE", $time);
            $display("      Request Address: 0x%08h", req.address);
            $display("      Last Beat: %b", resp.last);
            $display("      Error Flag: %b", resp.err);
            $display("      Verification: %s", verification_passed ? "PASSED" : "FAILED");
            $display("      >> Forwarding to Cache...");
            $display("===============================================================");
            if (!verification_passed) begin
          // $display("[MVU] *** VERIFICATION FAILED *** Addr: 0x%h", req.address);
          // You can modify resp.err or take other actions
            end
        end
      // ============================================

      // Clear pending request on last beat
        if (resp.last) begin
            rg_pending_req <= tagged Invalid;
        end

      // Forward response to cache
        ff_resp_to_cache.enq(resp);

      // $display("[MVU] Response - Data: 0x%h, Last: %b, Err: %b", 
      //         resp.data, resp.last, resp.err);
    endrule

    // Upstream interfaces (from dcache)
    interface put_cache_read_req = toPut(ff_req_from_cache);
    interface get_cache_read_resp = toGet(ff_resp_to_cache);

    // Downstream interfaces (to memory)
    interface get_mem_read_req = toGet(ff_req_to_mem);
    interface put_mem_read_resp = toPut(ff_resp_from_mem);

    // Control methods
    method Action ma_enable(Bool en);
        rg_mvu_enabled <= en;
    endmethod

    method Bool mv_busy = isValid(rg_pending_req);

endmodule: mkmvu

endpackage: mvu

