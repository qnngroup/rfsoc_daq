set_property -dict { PACKAGE_PIN AP5   IOSTANDARD LVCMOS18 } [get_ports sck]; # ADCIO_00
set_property -dict { PACKAGE_PIN AP6   IOSTANDARD LVCMOS18 } [get_ports sdi]; # ADCIO_01
set_property -dict { PACKAGE_PIN AR7   IOSTANDARD LVCMOS18 } [get_ports { cs_n[0] }]; # ADCIO_03
set_property -dict { PACKAGE_PIN AV7   IOSTANDARD LVCMOS18 } [get_ports { cs_n[1] }]; # ADCIO_04
set_property -dict { PACKAGE_PIN AU7   IOSTANDARD LVCMOS18 } [get_ports { cs_n[2] }]; # ADCIO_05
set_property -dict { PACKAGE_PIN AV8   IOSTANDARD LVCMOS18 } [get_ports { cs_n[3] }]; # ADCIO_06
set_property -dict { PACKAGE_PIN AU8   IOSTANDARD LVCMOS18 } [get_ports { cs_n[4] }]; # ADCIO_07
set_property -dict { PACKAGE_PIN AT6   IOSTANDARD LVCMOS18 } [get_ports { cs_n[5] }]; # ADCIO_08
set_property -dict { PACKAGE_PIN AT7   IOSTANDARD LVCMOS18 } [get_ports { cs_n[6] }]; # ADCIO_09
set_property -dict { PACKAGE_PIN AU5   IOSTANDARD LVCMOS18 } [get_ports { cs_n[7] }]; # ADCIO_10
set_property -dict { PACKAGE_PIN AU3   IOSTANDARD LVCMOS18 } [get_ports { ADCIO[12] }];
set_property -dict { PACKAGE_PIN AU4   IOSTANDARD LVCMOS18 } [get_ports { ADCIO[13] }];
set_property -dict { PACKAGE_PIN AV5   IOSTANDARD LVCMOS18 } [get_ports { ADCIO[14] }];
set_property -dict { PACKAGE_PIN AV6   IOSTANDARD LVCMOS18 } [get_ports { ADCIO[15] }];
set_property -dict { PACKAGE_PIN AU1   IOSTANDARD LVCMOS18 } [get_ports { ADCIO[16] }];
set_property -dict { PACKAGE_PIN AU2   IOSTANDARD LVCMOS18 } [get_ports { ADCIO[17] }];
set_property -dict { PACKAGE_PIN AV2   IOSTANDARD LVCMOS18 } [get_ports { ADCIO[18] }];
set_property -dict { PACKAGE_PIN AV3   IOSTANDARD LVCMOS18 } [get_ports { ADCIO[19] }];
