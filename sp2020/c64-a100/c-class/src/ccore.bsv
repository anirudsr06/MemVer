//See LICENSE.iitm for license details
/*

Author : Neel Gala
Email id : neelgala@gmail.com
Details:

--------------------------------------------------------------------------------------------------
*/
package ccore;

  //=================== Interface and module for a ccore - master on the AXI4 fabric ============= //
  // project related imports
	import Semi_FIFOF:: *;
	import AXI4_Types:: *;
	import AXI4_Fabric:: *;
  import riscv:: * ;
  import ccore_types:: * ;
  import FIFOF::*;
  import dcache_types :: *;
  import icache_types :: * ;
  import Assert ::*;
  import imem::*;
  import dmem::*;
`ifdef supervisor
  `ifdef RV64
    import ptwalk_rv64::*;
  `else
    import ptwalk_rv32::*;
  `endif
`endif
  `include "ccore_params.defines"
  `include "Logger.bsv"

  `define Mem_master_num 0

  // package imports
	import Connectable 				:: *;
  import GetPut:: *;
  import BUtils::*;

`ifdef debug
  import debug_types::*;
`endif

`ifdef supervisor
  typedef enum {None, IWalk, DWalk} PTWState deriving(Bits, Eq, FShow);
`endif
  typedef enum {Request, Response} TxnState deriving(Bits, Eq, FShow);

  interface Ifc_ccore_axi4;
		interface AXI4_Master_IFC#(`paddr, ELEN, USERSPACE) master_d;
		interface AXI4_Master_IFC#(`paddr, ELEN, USERSPACE) master_i;
    interface Put#(Bit#(1)) sb_clint_msip;
    interface Put#(Bit#(1)) sb_clint_mtip;
    interface Put#(Bit#(64)) sb_clint_mtime;
    interface Put#(Bit#(1)) sb_externalinterrupt;
  `ifdef rtldump
    interface Get#(DumpType) io_dump;
  `endif
  `ifdef debug
    interface Hart_Debug_Ifc debug_server;
  `endif
  endinterface : Ifc_ccore_axi4

  (*synthesize*)
  `ifdef supervisor
    (*preempts="dtlb_req_to_ptwalk, itlb_req_to_ptwalk"*)
    (*preempts="core_req_mkConnectionGetPut, ptwalk_req_mkConnectionGetPut"*)
  `endif
  `ifdef itim
    (*conflict_free="handle_itim_write_resp, handle_nc_write_resp"*)
  `endif
  module mkccore_axi4#(Bit#(`vaddr) resetpc, parameter Bit#(XLEN) hartid)(Ifc_ccore_axi4);
    String core = "";
    let vaddr = valueOf(`vaddr);
    let paddr = valueOf(`paddr);
    Ifc_riscv riscv <- mkriscv(resetpc, hartid);
`ifdef supervisor
  `ifdef RV64
    Ifc_ptwalk_rv64#(`asidwidth) ptwalk <- mkptwalk_rv64;
  `else
    Ifc_ptwalk_rv32#(`asidwidth) ptwalk <- mkptwalk_rv32;
  `endif
    Reg#(PTWState) rg_ptw_state <- mkReg(None);
`endif
		AXI4_Master_Xactor_IFC #(`paddr, ELEN, USERSPACE) fetch_xactor <- mkAXI4_Master_Xactor;
		AXI4_Master_Xactor_IFC #(`paddr, ELEN, USERSPACE) memory_xactor <- mkAXI4_Master_Xactor;
  `ifdef dcache
    Reg#(Bit#(8)) rg_burst_count <- mkReg(0);
    Reg#(Bit#(TLog#(TMul#(TMul#(`dwords, 8), `dblocks)))) rg_shift_amount <- mkReg(`dwords * 8 );
  `endif
    let curr_priv = riscv.mv_curr_priv;
  `ifdef debug
    Reg#(Maybe#(Bit#(DXLEN))) rg_abst_response <- mkReg(tagged Invalid); // registered container for responses
    Reg#(Bool) rg_debug_waitcsr <- mkReg(False);
    Reg#(Bit#(1)) rg_has_reset <- mkReg(0);
    let csr_response = riscv.mv_resp_to_core;
  `endif

  `ifdef pmp
	  let lv_pmp_cfg = riscv.mv_pmp_cfg;
	  let lv_pmp_adr = riscv.mv_pmp_addr;
  `endif

	  Ifc_imem imem <- mkimem(truncate(hartid) `ifdef pmp ,lv_pmp_cfg, lv_pmp_adr `endif );
	  Ifc_dmem dmem <- mkdmem(truncate(hartid) `ifdef pmp ,lv_pmp_cfg, lv_pmp_adr `endif );

	  mkConnection(imem.get_core_resp, riscv.inst_response); // imem integration
	  mkConnection(imem.put_core_req , riscv.instr_req);
	  mkConnection(dmem.mv_storebuffer_empty, riscv.storebuffer_empty);
	  mkConnection(dmem.mv_cache_available, riscv.cache_is_available);
	  mkConnection(dmem.mv_cacheable_store, riscv.store_is_cached);
    let core_req <- mkConnection(dmem.put_core_req, riscv.memory_request);
	  mkConnection(dmem.get_core_resp, riscv.memory_response); // dmem integration
	`ifdef dcache
	  mkConnection(dmem.mv_commit_store_ready, riscv.ma_cache_ready);
	`endif
	  rule rl_handle_imem_line_request;
	  	let request <- imem.get_read_mem_req.get;
	  	AXI4_Rd_Addr#(`paddr, 0) imem_request = AXI4_Rd_Addr {araddr : truncate(request.address),
        aruser: ?, arlen : request.burst_len, arsize : request.burst_size, arburst : 'b10,
        arid : zeroExtend(pack(request.io)), arprot:{1'b1, 1'b0, curr_priv[1]} }; // arburst : 00 - FIXED 01 - INCR 10 - WRAP
	    fetch_xactor.i_rd_addr.enq(imem_request);
	  	`logLevel( core, 1, $format("[%2d]CORE : IMEM Line Requesting ",hartid, fshow(imem_request)))
	  endrule

	  rule rl_handle_imem_line_resp;
	    let fab_resp <- pop_o (fetch_xactor.o_rd_data);
	  	Bool bus_error = !(fab_resp.rresp == AXI4_OKAY);
      imem.put_read_mem_resp.put(ICache_mem_readresp{data   : truncate(fab_resp.rdata),
                                                 last   : fab_resp.rlast,
                                                 err    : bus_error});
	  	`logLevel( core, 1, $format("[%2d]CORE : IMEM Line Response ",hartid, fshow(fab_resp)))
	  endrule

  `ifdef icache
    rule rl_map_imem_enable;
		  imem.ma_cache_enable(unpack(riscv.mv_cacheenable[0]));
    endrule
	`endif

	`ifdef dtim
	  /*doc:rule: */
	  rule rl_connect_dtim_memorymap_csrs;
	    dmem.ma_dtim_memory_map(truncate(riscv.mv_csr_dtim_base), truncate(riscv.mv_csr_dtim_bound));
	  endrule
	`endif
	`ifdef itim
	  /*doc:rule: */
	  rule rl_connect_itim_memorymap_csrs;
	    imem.ma_itim_memory_map(truncate(riscv.mv_csr_itim_base), truncate(riscv.mv_csr_itim_bound));
	  endrule
	`endif
    rule rl_map_dmem_enable;
		  dmem.ma_cache_enable(unpack(riscv.mv_cacheenable[1]));
    endrule
    rule rl_initiate_store(tpl_2(riscv.initiate_store));
      dmem.ma_perform_store(pack(tpl_1(riscv.initiate_store)));
    endrule

    Reg#(Maybe#(AXI4_Rd_Addr#(`paddr, 0))) rg_read_line_req <- mkReg(tagged Invalid);
    Reg#(Maybe#(Bit#(`paddr))) wr_write_req <- mkReg(tagged Invalid);

    // Currently it is possible that the cache can generate a write - request followed by a
    // read - request, but the fabric (due to contention) latches the read first to the slave followed
    // by the write - req. This could lead to wrong behavior. To avoid this it is necessary to ensure
    // that if a write - request has been initiated no read - requests should be latched unless the
    // write - response has arrived.
    // The contraint is fullilled using the register wr_write_req which holds the current address of
    // the line being written to the fabric on a eviction
    rule rl_handle_dmem_line_read_request(rg_read_line_req matches tagged Invalid);
      Bool perform_req = True;
	  	let req <- dmem.get_read_mem_req.get;
	  	AXI4_Rd_Addr#(`paddr, 0) dmem_request = AXI4_Rd_Addr {araddr : truncate(req.address), aruser: ?,
        arlen : req.burst_len, arsize : req.burst_size, arburst : 'b10, // arburst : 00 - FIXED 01 - INCR 10 - WRAP
        arid : zeroExtend(pack(req.io)) ,arprot:{1'b0, 1'b0, curr_priv[1]} }; 
    `ifdef dcache
      if(wr_write_req matches tagged Valid .waddr) begin
        if((waddr>>(`dwords + `dblocks )) == (req.address>>(`dwords + `dblocks ) ))begin
          perform_req = False;
          rg_read_line_req <= tagged Valid dmem_request;
          `logLevel( core, 1, $format("[%2d]CORE: Delaying Request: ",hartid,fshow(req)))
        end
      end
    `endif
      if(perform_req)  begin
   	    memory_xactor.i_rd_addr.enq(dmem_request);
        `logLevel( core, 1, $format("[%2d]CORE : DMEM Line Requesting ",hartid, fshow(dmem_request)))
      end
	  endrule

  `ifdef dcache
    rule rl_handle_delayed_read(rg_read_line_req matches tagged Valid .r &&& 
                                  wr_write_req matches tagged Invalid);
  	  memory_xactor.i_rd_addr.enq(r);
      `logLevel( core, 1, $format("[%2d]CORE : DMEM Delayed Line Requesting ",hartid, fshow(r)))
      rg_read_line_req <= tagged Invalid;
    endrule
  `endif

	  rule rl_handle_dmem_line_resp;
	    let fab_resp <- pop_o (memory_xactor.o_rd_data);
			let lv_data= fab_resp.rdata;
	  	Bool bus_error = !(fab_resp.rresp == AXI4_OKAY);
      dmem.put_read_mem_resp.put(DCache_mem_readresp{data:truncate(lv_data),
                                                 last:fab_resp.rlast,
                                                 err :bus_error});
      `logLevel( core, 1, $format("[%2d]CORE : DMEM Line Response ",hartid, fshow(fab_resp)))
	  endrule

    rule rl_handle_dmem_write_request `ifdef dcache (rg_burst_count == 0) `endif ;
      let req = dmem.mv_write_mem_req_rd;
    `ifdef dcache
  	  Bit#(TDiv#(ELEN, 8)) write_strobe = '1;
      if(req.burst_len > 0)
        rg_burst_count <= rg_burst_count + 1;
      else begin
        dmem.ma_write_mem_req_deq;
      end
    `else
      if(req.burst_size == 0)
        req.data = duplicate(req.data[7 : 0]);
      else if(req.burst_size == 1)
        req.data = duplicate(req.data[15 : 0]);
      else if(req.burst_size == 2)
        req.data = duplicate(req. data[31 : 0]);
  	  Bit#(TDiv#(ELEN, 8)) write_strobe = req.burst_size == 0?'b1 :
                                          req.burst_size == 1?'b11 :
                                          req.burst_size == 2?'hf : '1;

      Bit#(TAdd#(1, TDiv#(ELEN, 32))) byte_offset = truncate(req.address);
  	  if(req.burst_size != 3)// 8 - bit write;
  	  	write_strobe = write_strobe<<byte_offset;
      dmem.ma_write_mem_req_deq;
    `endif

		  AXI4_Wr_Addr#(`paddr, 0) aw = AXI4_Wr_Addr {awaddr : truncate(req.address), awuser : 0,
        awlen : req.burst_len, awsize : zeroExtend(req.burst_size[1 : 0]), awburst : 'b01,
        awid : zeroExtend(pack(req.io)), awprot:{1'b0, 1'b0, curr_priv[1]} }; // arburst : 00 - FIXED 01 - INCR 10 - WRAP

  	  let w  = AXI4_Wr_Data {wdata : truncate(req.data), wstrb : write_strobe,
                             wlast : req.burst_len == 0, 
                             wid : zeroExtend(pack(req.io))};
	    memory_xactor.i_wr_addr.enq(aw);
		  memory_xactor.i_wr_data.enq(w);
      `logLevel( core, 1, $format("[%2d]CORE : DMEM Line Write Addr : Request ",hartid, fshow(aw)))
      if(req.burst_len != 0 )
        wr_write_req <= tagged Valid req.address;
    endrule

  `ifdef dcache
    rule rl_dmem_burst_write_data(rg_burst_count != 0);
      Bool last = rg_burst_count == fromInteger(`dblocks - 1 );
      let req = dmem.mv_write_mem_req_rd;
      req.data = req.data >> rg_shift_amount;
  	  let w  = AXI4_Wr_Data {wdata : truncate(req.data), wstrb : '1, wlast : last,
                             wid : zeroExtend(pack(req.io))};
      Bit#(TAdd#(TAdd#(TLog#(`dwords), 1), 3)) shift = {`dwords, 3'b0};
      if(last) begin
        rg_burst_count <= 0;
        rg_shift_amount <= (`dwords * 8);
        wr_write_req <= tagged Invalid;
        dmem.ma_write_mem_req_deq;
      end
      else begin
        rg_shift_amount <= rg_shift_amount + (`dwords * 8);
        rg_burst_count <= rg_burst_count + 1;
      end
		  memory_xactor.i_wr_data.enq(w);
      `logLevel( core, 1, $format("[%2d]CORE : DMEM Write Data: %h rg_burst_count: %d last: %b \
rg_shift_amount:%d",hartid, req.data, rg_burst_count, last, rg_shift_amount))
    endrule
  `endif

    rule handle_dmem_line_write_resp;
      let response <- pop_o(memory_xactor.o_wr_resp);
	  	let bus_error = !(response.bresp == AXI4_OKAY);
    `ifdef dcache
      if (response.bid == 0)
  	  	dmem.put_write_mem_resp.put(bus_error);
      else
    `endif
	  	riscv.write_resp(tagged Valid tuple2(pack(bus_error),?));
      `logLevel( core, 1, $format("[%2d]CORE : DMEM Write Line Response ",hartid, fshow(response)))
    endrule

`ifdef dcache
  `ifdef itim 
    rule handle_dmem_itim_read_response;
	  	let response <- imem.get_mem_read_itim_resp.get;
	  	Bool bus_error = response.err;
      dmem.put_nc_read_resp.put(DCache_mem_readresp{data:zeroExtend(response.data),
                                                last:True,
                                                err :bus_error});
      `logLevel( core, 1, $format("[%2d]CORE : DMEM ITIM Response ",hartid, fshow(response)))
	  endrule
    rule handle_itim_write_resp;
	  	let response <- imem.get_mem_write_itim_resp.get;
	  	Bool bus_error = response;
	  	riscv.write_resp(tagged Valid tuple2(pack(bus_error),?));
      `logLevel( core, 1, $format("[%2d]CORE : ITIM Memory Write Response ",hartid, fshow(response)))
    endrule
  `endif
`endif
	  mkConnection(imem.ma_curr_priv, curr_priv);
	  mkConnection(dmem.ma_curr_priv, curr_priv);
  `ifdef supervisor
	  mkConnection(imem.ma_satp_from_csr,riscv.mv_csr_satp);
	  mkConnection(dmem.ma_satp_from_csr, riscv.mv_csr_satp);
	  mkConnection(dmem.ma_mstatus_from_csr, riscv.mv_csr_mstatus);
    mkConnection(ptwalk.ma_satp_from_csr,riscv.mv_csr_satp);
    mkConnection(ptwalk.ma_curr_priv, curr_priv);
    mkConnection(ptwalk.ma_mstatus_from_csr, riscv.mv_csr_mstatus);
    rule itlb_req_to_ptwalk(rg_ptw_state == None);
      let req <- imem.get_request_to_ptw.get();
      ptwalk.from_tlb.put(req);
      rg_ptw_state <= IWalk;
    endrule
    rule ptwalk_resp_to_itlb(rg_ptw_state == IWalk);
      let resp <- ptwalk.to_tlb.get();
      imem.put_response_frm_ptw.put(resp);
      rg_ptw_state <= None;
    endrule
    rule dtlb_req_to_ptwalk(rg_ptw_state == None);
      let req <- dmem.get_req_to_ptw.get();
      ptwalk.from_tlb.put(req);
      rg_ptw_state <= DWalk;
    endrule

    rule ptwalk_resp_to_dtlb(rg_ptw_state == DWalk);
      let resp <- ptwalk.to_tlb.get();
      dmem.put_resp_from_ptw.put(resp);
      rg_ptw_state <= None;
    endrule
    let ptwalk_req <- mkConnection(dmem.put_core_req, ptwalk.request_to_cache);
    mkConnection(dmem.get_ptw_resp, ptwalk.response_frm_cache);
    mkConnection(dmem.get_hold_req, ptwalk.hold_req);
  `endif

`ifdef perfmonitors
  `ifdef icache
    mkConnection(riscv.ma_icache_counters,imem.mv_icache_perf_counters);
  `endif
  `ifdef dcache
    mkConnection(riscv.ma_dcache_counters,dmem.mv_dcache_perf_counters);
  `endif
  `ifdef supervisor
    mkConnection(riscv.ma_itlb_counters,imem.mv_itlb_perf_counters);
    mkConnection(riscv.ma_dtlb_counters,dmem.mv_dtlb_perf_counters);
  `endif
`endif   
  
  // TODO: remove this with new clint
`ifdef supervisor
  rule rl_pulldown_seip;
    riscv.ma_set_seip(0);
  endrule:rl_pulldown_seip
`endif
  `ifdef debug
    rule rl_wait_for_csr_response(rg_debug_waitcsr && !isValid(rg_abst_response));
      if (csr_response.hit) begin
        rg_abst_response <= tagged Valid csr_response.data;
        rg_debug_waitcsr <= False;
      end
      else
        rg_debug_waitcsr <= True;
    endrule
    rule rl_indicate_has_reset;
      rg_has_reset <= 1;
    endrule
  `endif

    interface sb_clint_msip = interface Put
  	  method Action put(Bit#(1) intrpt);
        riscv.ma_clint_msip(intrpt);
      endmethod
    endinterface;
    interface sb_clint_mtip = interface Put
      method Action put(Bit#(1) intrpt);
        riscv.ma_clint_mtip(intrpt);
      endmethod
    endinterface;
    interface sb_clint_mtime = interface Put
  		method Action put (Bit#(64) c_mtime);
        riscv.ma_clint_mtime(c_mtime);
      endmethod
    endinterface;
    interface sb_externalinterrupt = interface Put
      method Action put(Bit#(1) intrpt);
        riscv.ma_set_meip(intrpt);
      endmethod
    endinterface;
		interface master_i = fetch_xactor.axi_side;
		interface master_d = memory_xactor.axi_side;
    `ifdef rtldump
      interface io_dump = riscv.dump;
    `endif
  `ifdef debug
    interface debug_server = interface Hart_Debug_Ifc

      method Action   abstractOperation(AbstractRegOp cmd)if (!(isValid(rg_abst_response)) 
                                                              && !rg_debug_waitcsr );
        if(cmd.address < zeroExtend(14'h1000))begin // Explot address bits to optimize this filter
          riscv.ma_debug_access_csrs(cmd);
          if (csr_response.hit)
            rg_abst_response <= tagged Valid zeroExtend(csr_response.data);
          else
            rg_debug_waitcsr <= True;
        end
        else if(cmd.address < `ifdef spfpu 'h1040 `else 'h1020 `endif )begin
          let lv_resp <- riscv.debug_access_gprs(cmd);
          rg_abst_response <= tagged Valid zeroExtend(lv_resp);
        end
        else begin
          rg_abst_response <= tagged Valid zeroExtend(32'h00000000);
        end
      endmethod

      method ActionValue#(Bit#(DXLEN)) abstractReadResponse if (isValid(rg_abst_response) );
        rg_abst_response <= tagged Invalid;
        return validValue(rg_abst_response);
      endmethod

      method haltRequest = riscv.ma_debug_halt_request;

      method resumeRequest = riscv.ma_debug_resume_request;

      method dm_active = riscv.ma_debugger_available;

      method is_halted = riscv.mv_core_is_halted();

      method is_unavailable = ~(riscv.mv_core_debugenable & rg_has_reset);

      method Action hartReset(Bit#(1) hart_reset_v); // Change to reset type // Signal TO Reset HART -Active HIGH
        noAction;
      endmethod

      method has_reset = rg_has_reset;
    endinterface;
  `endif
  endmodule : mkccore_axi4

endpackage
