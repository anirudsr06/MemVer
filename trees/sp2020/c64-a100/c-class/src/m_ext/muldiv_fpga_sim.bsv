//See LICENSE.iitm for license details
/* 

Author: Neel Gala
Email id: neelgala@gmail.com
Details:

--------------------------------------------------------------------------------------------------
*/
package muldiv_fpga_sim;
  
  interface Ifc_multiplier#(numeric type width);
    (*always_ready, always_enabled*)
    method Action iA (Bit#(width) a);
    (*always_ready, always_enabled*)
    method Action iB (Bit#(width) b);
    (*always_enabled*)
    method Bit#(TMul#(width, 2)) oP();
  endinterface:Ifc_multiplier

  module mkmultiplier(Ifc_multiplier#(width))
    provisos (Add#(a__, width, TMul#(width, 2))) ;
    Reg#(Bit#(TMul#(width, 2))) reg_a <- mkReg(0);
    Reg#(Bit#(TMul#(width, 2))) reg_b <- mkReg(0);

    method Action iA (Bit#(width) a);
      reg_a<= zeroExtend(a);
    endmethod
    method Action iB (Bit#(width) b);
      reg_b<=zeroExtend(b);
    endmethod
    method Bit#(TMul#(width, 2)) oP();
     return reg_a*reg_b; 
    endmethod
  endmodule
endpackage
