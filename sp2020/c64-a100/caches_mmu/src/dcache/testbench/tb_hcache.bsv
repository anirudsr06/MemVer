package tb_hcache;

import StmtFSM::*;
import hcache::*;
import Vector::*;

module mkTbHCache(Empty);

  // Instantiate DUT
  let hc <- mkHCache;

  // Test addresses (cache-line aligned)
  Bit#(`paddr) addr0    = 'h0000_0040; // protected
  Bit#(`paddr) addr1    = 'h0000_0080; // different line
  Bit#(`paddr) addr_bad = 'h0030_0000; // outside protected range

  Bit#(64) hashA = 64'hAAAA_AAAA_AAAA_AAAA;
  Bit#(64) hashB = 64'hBBBB_BBBB_BBBB_BBBB;

  // ------------------------------------------------------------
  // Expect Invalid
  // ------------------------------------------------------------
  function Action expectInvalid(Bit#(`paddr) addr);
    return action
      let res <- hc.get_expected_hash(addr);
      case (res) matches
        tagged Invalid:
          $display("OK: addr %h correctly Invalid", addr);
        tagged Valid .h:
          $fatal(1, "ERROR: addr %h expected Invalid, got %h", addr, h);
      endcase
    endaction;
  endfunction

  // ------------------------------------------------------------
  // Expect Valid(hash)
  // ------------------------------------------------------------
  function Action expectValid(Bit#(`paddr) addr, Bit#(64) exp);
    return action
      let res <- hc.get_expected_hash(addr);
      case (res) matches
        tagged Valid .h:
          if (h == exp)
            $display("OK: addr %h hash %h", addr, h);
          else
            $fatal(1, "ERROR: addr %h hash mismatch exp=%h got=%h", addr, exp, h);
        tagged Invalid:
          $fatal(1, "ERROR: addr %h expected Valid(%h)", addr, exp);
      endcase
    endaction;
  endfunction

  // ------------------------------------------------------------
  // Main test FSM
  // ------------------------------------------------------------
  Stmt test =
  seq
    $display("\n=== HCACHE UNIT TEST START ===");

    // 1. Empty cache
    expectInvalid(addr0);
    expectInvalid(addr1);

    // 2. Write hashA to addr0
    $display("\nWriting hashA to addr0");
    hc.update_hash(addr0, hashA);

    expectValid(addr0, hashA);
    expectInvalid(addr1);

    // 3. Overwrite same address
    $display("\nOverwriting addr0 with hashB");
    hc.update_hash(addr0, hashB);

    expectValid(addr0, hashB);

    // 4. Out-of-range behavior
    $display("\nWriting out-of-range address");
    hc.update_hash(addr_bad, hashA);

    expectInvalid(addr_bad);
    expectValid(addr0, hashB); // must remain intact

    $display("\n Checking if memory bounds hold");
    expectValid(addr_bad, hashA);
    
    $display("\n=== HCACHE UNIT TEST PASSED ===");
    $finish;
  endseq;

  mkAutoFSM(test);

endmodule

endpackage
