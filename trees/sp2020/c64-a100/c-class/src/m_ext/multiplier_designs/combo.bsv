//See LICENSE.iitm for license details
/*
Author : Neel Gala
Email id : neelgala@gmail.com
Details: This module implements the multiplier for RISC-V. It expects the operands and funct3
arguments to be provided. This module uses the signedmul bsvwrapper to perform the multiplication.
The signedmul module is chosen since it provides benefits in area and frequency when performing asic
synthesis.

Additionaly, this module has been parameterized for retiming. The parameter MULSTAGES defines
the number of regsiters placed at the inputs. This allows for the synthesizer to retime the circuit
by moving around the registers within the combo blocks. Both FPGA and ASIC synthesizers support this
feature.

--------------------------------------------------------------------------------------------------
*/
package combo;

  import signedmul:: *;
  import DReg :: *;
  import ccore_types :: *;
  import Vector :: * ;
  `include "ccore_params.defines"
  `include "Logger.bsv"

  interface Ifc_combo_mul;
    (*always_ready*)
		method Action ma_inputs(Bit#(XLEN) in1, Bit#(XLEN) in2, Bit#(3) funct3
                                                                `ifdef RV64, Bool word32 `endif );
		method XBoxOutput mv_output;//returning the result
	endinterface

  (*synthesize*)
  module mkcombo_mul(Ifc_combo_mul);

    String mul = "";

    Vector#(`MULSTAGES, Reg#(Bit#(TAdd#(1, XLEN))))  rg_op1  <- replicateM(mkReg(0));
    Vector#(`MULSTAGES, Reg#(Bit#(TAdd#(1, XLEN))))  rg_op2  <- replicateM(mkReg(0));
    Reg#(Bit#(3))     rg_fn3  <- mkReg(0);
  `ifdef RV64
    Reg#(Bool)        rg_word <- mkReg(False);
  `endif
    Vector#(`MULSTAGES, Reg#(Bool))  rg_valid  <- replicateM(mkDReg(False));

    Ifc_signedmul#(TAdd#(XLEN, 1), TAdd#(XLEN, 1)) signed_mul <- mksignedmul();

    Wire#(Bit#(XLEN)) wr_result <- mkWire();

    rule rl_perform_mul;

      for(Integer i = `MULSTAGES - 1; i>0 ; i = i-1) begin
        rg_op1[i] <= rg_op1[i - 1];
        rg_op2[i] <= rg_op2[i - 1];
        rg_valid[i] <= rg_valid[i-1];
      end

      signed_mul.ia(rg_op1[`MULSTAGES - 1]);
      signed_mul.ib(rg_op2[`MULSTAGES - 1]);
      Bool lv_upperbits = unpack(|rg_fn3[1 : 0]);

      let out = signed_mul.oc;

      Bit#(XLEN) default_out;
      if(lv_upperbits)
        default_out = pack(out)[valueOf(TMul#(2, XLEN)) - 1 : valueOf(XLEN)];
      else
        default_out = pack(out)[valueOf(XLEN) - 1:0];

      `ifdef RV64
        if(rg_word)
          default_out = signExtend(default_out[31 : 0]);
      `endif

      wr_result <= default_out;

    endrule


		method Action ma_inputs(Bit#(XLEN) in1, Bit#(XLEN) in2, Bit#(3) funct3
                                                              `ifdef RV64, Bool word32 `endif );

      Bit#(1) sign1 = funct3[1]^funct3[0];
      Bit#(1) sign2 = pack(funct3[1 : 0] == 1);
      rg_op1[0] <= unpack({sign1 & in1[valueOf(XLEN) - 1], in1});
      rg_op2[0] <= unpack({sign2 & in2[valueOf(XLEN) - 1], in2});
      rg_valid[0] <= True;
      rg_fn3 <= funct3;
    `ifdef RV64
      rg_word <= word32;
    `endif

    endmethod
		method XBoxOutput mv_output;//returning the result
      return XBoxOutput{ valid : rg_valid[`MULSTAGES-1], data : wr_result
                               `ifdef arith_trap ,trap:False, cause:? `endif
                               `ifdef spfpu ,fflags:0 `endif };
    endmethod

  endmodule
endpackage

