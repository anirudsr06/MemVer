#set curdir [ file dirname [ file normalize [ info script ] ] ]
#source $curdir/env.tcl
#
#open_project $ip_project_dir/$ip_project.xpr
#set_property "simulator_language" "Mixed" [current_project]
#set_property "target_language" "Verilog" [current_project]


puts "\nDEBUG: Creating MIG IP for DDR3 \n"
if { [get_ips -quiet axi_ethernetlite_0] eq "" } {
    create_ip -name axi_ethernetlite -vendor xilinx.com -library ip -version 3.0 -module_name axi_ethernetlite_0
} else {
    reset_run axi_ethernetlite_0_synth_1
}

set_property -dict [list \
  CONFIG.C_INCLUDE_INTERNAL_LOOPBACK {0} \
  CONFIG.C_S_AXI_PROTOCOL {AXI4LITE} \
  CONFIG.AXI_ACLK_FREQ_MHZ {50}\
  CONFIG.MII_BOARD_INTERFACE {eth_mii} \
  CONFIG.MDIO_BOARD_INTERFACE {eth_mdio_mdc} \
  ] [get_ips axi_ethernetlite_0]
generate_target {instantiation_template} [get_ips axi_ethernetlite_0]
create_ip_run [get_ips axi_ethernetlite_0]
#launch_run axi_ethernetlite_0_synth_1
#wait_on_run axi_ethernetlite_0_synth_1
