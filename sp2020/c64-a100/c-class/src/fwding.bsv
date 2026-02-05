//See LICENSE.iitm for license details
/*

Author: Neel Gala
Email id: neelgala@gmail.com
Details:

--------------------------------------------------------------------------------------------------
*/
package fwding;
  import ccore_types::*;
  `include "ccore_params.defines"
  import GetPut::*;
  import BUtils::*;
  `include "Logger.bsv"

  interface Ifc_fwding;
    (*always_ready, always_enabled*)
    method Action fwd_from_pipe3 (FwdType fwd);
    (*always_ready, always_enabled*)
    method Action fwd_from_pipe4_first (FwdType fwd);
    method ActionValue#(Tuple2#(Bool,Bit#(ELEN))) read_rs1(Bit#(ELEN) val, Bit#(5) addr
                                                  `ifdef spfpu , RFType rftype `endif );
    method ActionValue#(Tuple2#(Bool,Bit#(ELEN))) read_rs2(Bit#(ELEN) val, Bit#(5) addr
                                                  `ifdef spfpu , RFType rftype `endif );
  `ifdef spfpu
    method ActionValue#(Tuple2#(Bool,Bit#(ELEN))) read_rs3(Bit#(ELEN) val, Bit#(5) addr, RFType rftype);
  `endif
  endinterface

  function Tuple2#(Bool, Bit#(ELEN)) forward_data (Bit#(ELEN) rfval, Bit#(5) addr,
                                              `ifdef spfpu  RFType rftype, `endif
                                                FwdType youngest,
                                                FwdType youngestp1);
    if (youngest.valid && youngest.addr == addr `ifdef spfpu && youngest.rftype == rftype `endif )
      return tuple2(youngest.available, youngest.data);
    else if (youngestp1.valid && youngestp1.addr == addr
                                              `ifdef spfpu && youngestp1.rftype == rftype `endif )
      return tuple2(youngestp1.available, youngestp1.data);
    else
      return tuple2(True, rfval);
  endfunction

  (*synthesize*)
  module mkfwding#(parameter Bit#(XLEN) hartid) (Ifc_fwding);
    Wire#(FwdType) wr_from_pipe3        <- mkWire();
    Wire#(FwdType) wr_from_pipe4_first  <- mkWire();
    method ActionValue#(Tuple2#(Bool,Bit#(ELEN))) read_rs1(Bit#(ELEN) val, Bit#(5) addr
                                                              `ifdef spfpu , RFType rftype `endif );
      return forward_data(val, addr, `ifdef spfpu rftype, `endif  wr_from_pipe3,
                                                                  wr_from_pipe4_first);
    endmethod
    method ActionValue#(Tuple2#(Bool,Bit#(ELEN))) read_rs2(Bit#(ELEN) val, Bit#(5) addr
                                                              `ifdef spfpu , RFType rftype `endif );
      return forward_data(val, addr, `ifdef spfpu rftype, `endif  wr_from_pipe3,
                                                                  wr_from_pipe4_first);
    endmethod
  `ifdef spfpu
    method ActionValue#(Tuple2#(Bool,Bit#(ELEN))) read_rs3(Bit#(ELEN) val, Bit#(5) addr
                                                              `ifdef spfpu , RFType rftype `endif );
      return forward_data(val, addr, `ifdef spfpu rftype, `endif  wr_from_pipe3,
                                                                  wr_from_pipe4_first);
    endmethod
  `endif
    method Action fwd_from_pipe3 (FwdType fwd);
      `logLevel( fwding, 2, $format("[%2d]FWDING: from PIPE3: ",hartid,fshow(fwd)))
      wr_from_pipe3 <= fwd;
    endmethod
    method Action fwd_from_pipe4_first (FwdType fwd);
      `logLevel( fwding, 2, $format("[%2d]FWDING: from PIPE4-first: ",hartid,fshow(fwd)))
      wr_from_pipe4_first<= fwd;
    endmethod
  endmodule
endpackage
