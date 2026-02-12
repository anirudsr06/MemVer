/*
Testbench to verify Shakti D-Cache Burst Operations
Just change TOP_FILE and TOP_MODULE in Makefile.inc to use this testbench

Expected behavior:
- Cache line = DBLOCKS * DWORDS
- Bus width = DBUSWIDTH bits
- On cache miss: burst_len = DBLOCKS - 1 (AXI format)
- burst_size = log2(DWORDS) 
- Total transfers = DBLOCKS bursts of (2 to the power burst_size) bytes each
*/

package burst_tb;

  import dmem::*;
  import dcache_types::*;
  import mem_config::*;
  import GetPut::*;
  import FIFOF::*;
  import BUtils ::*;
  import DReg::*;
  import RegFile::*;
  import device_common::*;
  import Vector::*;
  `include "Logger.bsv"
  import io_func :: * ;

  (*synthesize*)
  module mkburst_tb(Empty);

    let dmem <- mkdmem(0 `ifdef pmp ,unpack(0), unpack(0) `endif );

    // Memory storage for responses
    RegFile#(Bit#(19), Bit#(`dbuswidth)) data <- mkRegFileFullLoad("data.mem");

    // Tracking registers
    Reg#(Bool) rg_test_started <- mkReg(False);
    Reg#(Maybe#(DCache_mem_readreq#(32))) read_mem_req <- mkReg(tagged Invalid);
    Reg#(Bit#(8)) rg_read_burst_count <- mkReg(0);
    Reg#(Bit#(32)) rg_total_bytes <- mkReg(0);
    Reg#(Bool) rg_burst_verified <- mkReg(False);

    rule rl_nop;
      `logLevel( tb, 0, $format("\n"))
    endrule

    // Enable cache
    rule enable_cache;
      dmem.ma_cache_enable(True);
      dmem.ma_curr_priv('d3);
    endrule

  `ifdef supervisor
    rule tlb_csr_info;
      dmem.ma_satp_from_csr(0);
      dmem.ma_mstatus_from_csr('h0);
    endrule
  `endif

    Wire#(Bool) wr_cache_avail <- mkWire();
    rule check_cache_avail;
      wr_cache_avail <= dmem.mv_cache_available;
    endrule

    // Issue a single test request that will cause a cache miss
    rule issue_test_request(!rg_test_started && wr_cache_avail);
      let stime <- $stime;
      if(stime >= 20) begin
        dmem.put_core_req.put(DMem_request{
          address: 64'h1000,
          fence: False,
          epochs: 0,
          access: 2'b00,
          size: 3'b011,
          writedata: 0
        `ifdef atomic
          , atomic_op: 0
        `endif
        `ifdef supervisor
          , sfence: False,
          ptwalk_req: False,
          ptwalk_trap: False
        `endif
        });
        
        rg_test_started <= True;
        
        Integer dblocks = valueOf(`dblocks);
        Integer dwords = valueOf(`dwords);
        Integer dbuswidth = valueOf(`dbuswidth);
        Integer cache_line_bytes = dblocks * dwords;
        Integer bus_width_bytes = dbuswidth / 8;
        Integer expected_burst_len = dblocks - 1;
        Integer expected_burst_size = valueOf(TLog#(`dwords));
        
        $display("========================================");
        $display("D-Cache Burst Operation Test");
        $display("========================================");
        $display("TB: Issued load to address 0x1000 (will miss)");
        $display("");
        $display("Configuration:");
        $display("  DBLOCKS     = %0d", dblocks);
        $display("  DWORDS      = %0d", dwords);
        $display("  DBUSWIDTH   = %0d bits", dbuswidth);
        $display("  Cache line  = %0d bytes", cache_line_bytes);
        $display("  Bus width   = %0d bytes", bus_width_bytes);
        $display("");
        $display("Expected burst parameters:");
        $display("  burst_len   = %0d (means %0d transfers)", expected_burst_len, dblocks);
        $display("  burst_size  = %0d (means %0d bytes/transfer)", expected_burst_size, dwords);
        $display("========================================");
        $display("");
      end
    endrule

    // Capture read request and verify burst parameters
    rule capture_read_request(read_mem_req matches tagged Invalid);
      let req <- dmem.get_read_mem_req.get;
      
      if (!rg_burst_verified) begin
        $display("TB: MEMORY READ REQUEST CAPTURED");
        $display("  Address     : 0x%h", req.address);
        $display("  Burst Length: %0d", req.burst_len);
        $display("  Burst Size  : %0d", req.burst_size);
        $display("  IO          : %b", req.io);
        $display("");
        
        // Verify burst_len = DBLOCKS - 1
        Bit#(8) expected_burst_len = fromInteger(valueOf(`dblocks) - 1);
        if (req.burst_len == expected_burst_len) begin
          $display("  PASS: burst_len = %0d (expected %0d)", 
                   req.burst_len, expected_burst_len);
        end else begin
          $display("  FAIL: burst_len = %0d (expected %0d)", 
                   req.burst_len, expected_burst_len);
          $finish(1);
        end
        
        // Verify burst_size = log2(DWORDS)
        Bit#(3) expected_burst_size = fromInteger(valueOf(TLog#(`dwords)));
        if (req.burst_size == expected_burst_size) begin
          $display("  PASS: burst_size = %0d (expected %0d)", 
                   req.burst_size, expected_burst_size);
        end else begin
          $display("  FAIL: burst_size = %0d (expected %0d)", 
                   req.burst_size, expected_burst_size);
          $finish(1);
        end
        $display("");
      end
      
      read_mem_req <= tagged Valid req;
    endrule

    // Send burst read responses back to cache
    rule send_read_responses(read_mem_req matches tagged Valid .req);
      let rd_req = req;
      Bool is_last = (rg_read_burst_count == rd_req.burst_len);
      
      if(is_last) begin
        rg_read_burst_count <= 0;
        read_mem_req <= tagged Invalid;
        rg_burst_verified <= True;
      end
      else begin
        rg_read_burst_count <= rg_read_burst_count + 1;
        rg_total_bytes <= rg_total_bytes + fromInteger(valueOf(TDiv#(`dbuswidth,8)));
        
        read_mem_req <= tagged Valid (DCache_mem_readreq{
          address: (axi4burst_addrgen(rd_req.burst_len, rd_req.burst_size, 2, rd_req.address)),
          burst_len: rd_req.burst_len,
          burst_size: rd_req.burst_size,
          io: rd_req.io
        });
      end
      
      // Generate response data from memory
      let v_wordbits = valueOf(TLog#(`dwords));
      Bit#(19) index = truncate(rd_req.address >> v_wordbits);
      let dat = data.sub(truncate(index));
      Bit#(TLog#(TDiv#(`dbuswidth,8))) zeros = 0;
      Bit#(TMul#(2,TLog#(TDiv#(`dbuswidth,8)))) shift = {rd_req.address[v_wordbits-1:0], zeros};
      dat = dat >> shift;
      
      dmem.put_read_mem_resp.put(DCache_mem_readresp{
        data: dat,
        last: is_last,
        err: False
      });
      
      if (!rg_burst_verified) begin
        $display("TB: Burst beat %0d | last=%b",
                 rg_read_burst_count, is_last);
      end
      
      // When burst is complete, verify total bytes
      if (is_last && !rg_burst_verified) begin
        Bit#(32) total_bytes = rg_total_bytes + fromInteger(valueOf(TDiv#(`dbuswidth,8)));
        Bit#(32) expected_bytes = fromInteger(valueOf(`dblocks) * valueOf(`dwords));
        
        $display("");
        $display("TB: BURST COMPLETE");
        $display("  Total transfers: %0d", rg_read_burst_count + 1);
        $display("  Bytes/transfer : %0d", valueOf(TDiv#(`dbuswidth,8)));
        $display("  Total bytes    : %0d", total_bytes);
        $display("");
        
        if (total_bytes == expected_bytes) begin
          $display("  PASS: Total bytes = %0d (expected %0d)", total_bytes, expected_bytes);
          $display("");
          $display("========================================");
          $display("ALL TESTS PASSED");
          $display("========================================");
          $display("");
          $display("CONFIRMED:");
          $display("  Cache fetches %0d-byte lines using", expected_bytes);
          $display("  %0d burst transfers of %0d bytes each", 
                   valueOf(`dblocks), valueOf(TDiv#(`dbuswidth,8)));
          $display("========================================");
        end else begin
          $display("  FAIL: Total bytes = %0d (expected %0d)", total_bytes, expected_bytes);
          $display("");
          $display("========================================");
          $display("TEST FAILED");
          $display("========================================");
          $finish(1);
        end
        
        rg_total_bytes <= 0;
      end
    endrule

    // Consume core response
    rule consume_core_response(rg_test_started);
      let resp <- dmem.get_core_resp.get();
      `logLevel( tb, 0, $format("TB: Core response: data=0x%h", resp.word))
    endrule

    // End simulation after test completes
    rule end_simulation(rg_burst_verified);
      $display("");
      $display("Simulation Complete");
      $finish(0);
    endrule

  endmodule

endpackage
