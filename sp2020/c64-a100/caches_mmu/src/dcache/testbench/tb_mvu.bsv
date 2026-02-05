package tb_mvu;

import StmtFSM::*;
import FIFO::*;
import GetPut::*;
import mvu::*;
import Vector::*;
import dcache_types::*;

module mkTbMVU(Empty);

    let mvu <- mkmvu;

    Bit#(`paddr) test_addr = 'h0000_0040; // protected & aligned

    Vector#(8, Bit#(64)) beats =
        unpack(512'h0000000000000008_0000000000000007_0000000000000006_0000000000000005_0000000000000004_0000000000000003_0000000000000002_0000000000000001);

    Bit#(64) expected_xor =
        64'h1 ^ 64'h2 ^ 64'h3 ^ 64'h4 ^
        64'h5 ^ 64'h6 ^ 64'h7 ^ 64'h8;

    Reg#(UInt#(4)) i <- mkReg(0);

    Stmt test =
    seq
        $display("\n=== MVU LEAF TEST START ===");

        // Send cache miss request
        mvu.put_cache_read_req.put(
            DCache_mem_readreq {
                address: test_addr,
                burst_len: 8
            }
        );

        // MVU should forward it to memory
        action
            let req <- mvu.get_mem_read_req.get;
            $display("Forwarded request addr=%h", req.address);
        endaction
        // Send 8 beats from memory
        repeat (8)
            seq
                action
                    mvu.put_mem_read_resp.put(
                        DCache_mem_readresp {
                            data: zeroExtend(beats[i]),
                            last: (i == 7),
                            err: False
                        }
                    );
                endaction

                action
                    let resp <- mvu.get_cache_read_resp.get;
                    $display("Cache received beat %0d data=%h", i, resp.data);
                endaction

                action
                    i <= i + 1;
                endaction
            endseq

        $display("Expected XOR = %h", expected_xor);
        $display("=== MVU LEAF TEST COMPLETE ===");
        $finish;
    endseq;

    mkAutoFSM(test);

endmodule

endpackage
