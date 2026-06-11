---------------------------------------------------------------------------------
Start Writing Synthesis Report
---------------------------------------------------------------------------------

DSP Final Report (the ' indicates corresponding REG is set)
+-----------------+----------------+--------+--------+--------+--------+--------+------+------+------+------+-------+------+------+
|Module Name      | DSP Mapping    | A Size | B Size | C Size | D Size | P Size | AREG | BREG | CREG | DREG | ADREG | MREG | PREG |
+-----------------+----------------+--------+--------+--------+--------+--------+------+------+------+------+-------+------+------+
|mkmulticycle_alu | A'*B'          | 17     | 18     | -      | -      | 48     | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | PCIN>>17+A'*B' | 17     | 18     | -      | -      | 0      | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | PCIN+A'*B'     | 17     | 18     | -      | -      | 48     | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | PCIN>>17+A'*B' | 30     | 18     | -      | -      | 48     | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | A'*B'          | 17     | 17     | -      | -      | 0      | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | PCIN+A'*B'     | 17     | 18     | -      | -      | 48     | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | PCIN>>17+A'*B' | 17     | 18     | -      | -      | 0      | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | PCIN+A'*B'     | 17     | 17     | -      | -      | 48     | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | A'*B'          | 17     | 17     | -      | -      | 0      | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | PCIN+A'*B'     | 17     | 17     | -      | -      | 48     | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | PCIN>>17+A'*B' | 17     | 18     | -      | -      | 0      | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | PCIN+A'*B'     | 17     | 17     | -      | -      | 48     | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | A'*B'          | 17     | 17     | -      | -      | 48     | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | PCIN>>17+A'*B' | 17     | 17     | -      | -      | 0      | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | PCIN+A'*B'     | 17     | 17     | -      | -      | 48     | 1    | 1    | -    | -    | -     | 0    | 0    |
|mkmulticycle_alu | PCIN>>17+A'*B' | 17     | 17     | -      | -      | 48     | 1    | 1    | -    | -    | -     | 0    | 0    |
+-----------------+----------------+--------+--------+--------+--------+--------+------+------+------+------+-------+------+------+


Report BlackBoxes:
+------+-------------------+----------+
|      |BlackBox name      |Instances |
+------+-------------------+----------+
|1     |proc_sys_reset_0   |         1|
|2     |clk_divider        |         1|
|3     |mig_ddr3           |         1|
|4     |clk_converter      |         1|
|5     |axi_ethernetlite_0 |         1|
|6     |xadc_wiz_0         |         1|
+------+-------------------+----------+

Report Cell Usage:
+------+-----------------+------+
|      |Cell             |Count |
+------+-----------------+------+
|1     |axi_ethernetlite |     1|
|2     |clk_converter    |     1|
|3     |clk_divider      |     1|
|4     |mig_ddr3         |     1|
|5     |proc_sys_reset   |     1|
|6     |xadc_wiz         |     1|
|7     |BSCANE2          |     1|
|8     |BUFG             |     7|
|9     |CARRY4           |  1240|
|10    |DSP48E1          |    16|
|11    |LUT1             |   363|
|12    |LUT2             |  3251|
|13    |LUT3             |  5728|
|14    |LUT4             |  6310|
|15    |LUT5             |  8768|
|16    |LUT6             | 31531|
|17    |MUXF7            |  1166|
|18    |MUXF8            |   132|
|19    |RAM32M           |    44|
|20    |RAM64M           |   704|
|21    |RAMB18E1         |    18|
|22    |RAMB36E1         |    10|
|25    |SRL16E           |     4|
|26    |STARTUPE2        |     1|
|27    |FDCE             |  1125|
|28    |FDPE             |    93|
|29    |FDRE             | 46936|
|30    |FDSE             |   681|
|31    |IBUF             |    31|
|32    |IOBUF            |    37|
|33    |OBUF             |    11|
+------+-----------------+------+
---------------------------------------------------------------------------------
Finished Writing Synthesis Report : Time (s): cpu = 00:04:09 ; elapsed = 00:04:25 . Memory (MB): peak = 3222.707 ; gain = 1457.422 ; free physical = 547 ; free virtual = 12722
---------------------------------------------------------------------------------
