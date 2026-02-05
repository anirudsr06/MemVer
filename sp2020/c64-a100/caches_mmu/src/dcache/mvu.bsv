package mvu;
    import FIFOF::*;
    import FIFO::*;
    import GetPut::*;
    import Assert::*;
    import dcache_types::*;
    import hcache::*;
    `include "dcache.defines"
    
    // Configuration constants
    typedef 8 BurstLen;

    interface Ifc_mvu;
        // Upstream (Cache Side)
        interface Put#(DCache_mem_readreq#(`paddr)) put_cache_read_req;
        interface Get#(DCache_mem_readresp#(`dbuswidth)) get_cache_read_resp;

        // Downstream (Memory Side)
        interface Get#(DCache_mem_readreq#(`paddr)) get_mem_read_req;
        interface Put#(DCache_mem_readresp#(`dbuswidth)) put_mem_read_resp;

        method Action ma_enable(Bool en);
    endinterface

    (* synthesize *)
    module mkmvu(Ifc_mvu);
        FIFOF#(DCache_mem_readreq#(`paddr)) ff_req_from_cache <- mkFIFOF;
        FIFOF#(DCache_mem_readreq#(`paddr)) ff_req_to_mem    <- mkFIFOF;
        FIFOF#(DCache_mem_readresp#(`dbuswidth)) ff_resp_from_mem <- mkFIFOF;
        FIFOF#(DCache_mem_readresp#(`dbuswidth)) ff_resp_to_cache <- mkFIFOF;

        Reg#(Bool) rg_mvu_enabled <- mkReg(True);
        Reg#(Maybe#(DCache_mem_readreq#(`paddr))) rg_pending_req <- mkReg(tagged Invalid);
        
        // Accumulator for 8 beats (8 bytes each) = 64-byte leaf
        Reg#(Bit#(HashWidth)) rg_leaf_accumulator <- mkReg(0);
        Reg#(UInt#(4)) rg_beat_count <- mkReg(0);
        Reg#(Bool) rg_from_protected_space <- mkReg(False);
        Ifc_HCache hcache <- mkHCache;

        // Forward Request to Memory
        rule rl_forward_request(ff_req_from_cache.notEmpty && !isValid(rg_pending_req));
            let req = ff_req_from_cache.first;
            ff_req_from_cache.deq;

            rg_from_protected_space <= hcache.is_protected(req.address);
            rg_beat_count <= 0;
            rg_pending_req <= tagged Valid req;
            ff_req_to_mem.enq(req);
        endrule

        // Accumulate and Verify on Last Beat and ensure no more than 8 beats
        rule rl_verify_accumulate(ff_resp_from_mem.notEmpty &&& rg_pending_req matches tagged Valid .req);
            let resp = ff_resp_from_mem.first;
            ff_resp_from_mem.deq;

            if (rg_from_protected_space) begin
                let current_data = truncate(resp.data);
                let next_acc = rg_leaf_accumulator ^ current_data;

                if (rg_mvu_enabled) begin
                    if (resp.last) begin

                        dynamicAssert(rg_beat_count == fromInteger(valueOf(BurstLen) - 1), "More bursts than expected!");
                        // Final Hash for the 64-byte block (Leaf Node)
                        $display("[MVU] Verification Phase | Addr: %h", req.address);
                        $display("[MVU] Final Accumulated Hash (L1 Parent): %h", next_acc);
                        
                        let expected_hash <- hcache.get_expected_hash(req.address);
                        case (expected_hash) matches
                            tagged Invalid: begin
                                hcache.update_hash(req.address, next_acc);
                            end
                            tagged Valid .h: begin
                                dynamicAssert(h == next_acc, "Memory Verification Failed");
                            end
                        endcase

                        rg_leaf_accumulator <= 0; // Reset for next burst
                        rg_pending_req <= tagged Invalid;
                        rg_beat_count <= 0;
                        rg_from_protected_space <= False;
                    end 
                    else begin
                        rg_leaf_accumulator <= next_acc;
                        rg_beat_count <= rg_beat_count+1;
                        $display("[MVU] Accumulating Beat... Current XOR: %h", next_acc);
                    end
                end
            end
            if (!rg_from_protected_space && resp.last) begin
                rg_pending_req <= tagged Invalid;
                rg_beat_count <= 0;
                rg_leaf_accumulator <= 0;
            end

            ff_resp_to_cache.enq(resp);
        endrule

        interface put_cache_read_req = toPut(ff_req_from_cache);
        interface get_cache_read_resp = toGet(ff_resp_to_cache);
        interface get_mem_read_req = toGet(ff_req_to_mem);
        interface put_mem_read_resp = toPut(ff_resp_from_mem);
        
        method Action ma_enable(Bool en);
            rg_mvu_enabled <= en;
        endmethod

    endmodule
endpackage
