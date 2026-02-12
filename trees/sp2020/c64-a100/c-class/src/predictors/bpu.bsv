//See LICENSE.iitm for license details
/* 

Author: Neel Gala
Email id: neelgala@gmail.com
Details:

--------------------------------------------------------------------------------------------------
*/
package bpu;
  `ifdef gshare_nc
    import gshare_nc :: * ;
  `elsif gshare_fa_c
    import gshare_fa_c :: * ;
  `elsif gshare_fa_nc
    import gshare_fa_nc :: * ;
  `elsif gshare_c
    import gshare_c :: * ;
  `elsif bimodal_c
    import bimodal_c :: *;
  `else
    import bimodal_nc :: *;
  `endif

  (*synthesize*)
  module mkbpu(Ifc_bpu);
    let ifc();
  `ifdef gshare_nc
    mkgshare_nc _temp(ifc);
  `elsif gshare_fa_c
    mkgshare_fa_c _temp(ifc);
  `elsif gshare_fa_nc
    mkgshare_fa_nc _temp(ifc);
  `elsif gshare_c
    mkgshare_c _temp(ifc);
  `elsif bimodal_c
    mkbimodal_c _temp(ifc);
  `else
    mkbimodal_nc _temp(ifc);
  `endif
    return (ifc);
  endmodule

endpackage

