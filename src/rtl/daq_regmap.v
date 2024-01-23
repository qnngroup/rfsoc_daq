// daq_regmap.v - Reed Foster
// DAQ toplevel with register map interface for configuring signal chain submodules

`timescale 1ns/1ps
module daq_regmap (
  input s_axi_ps_clk, // 150 MHz
  input s_axi_ps_aresetn,

  input [31:0]  s_axi_ps_araddr,
  input [31:0]  s_axi_ps_arprot,
  input         s_axi_ps_arvalid,
  output        s_axi_ps_arready,

  input [31:0]  s_axi_ps_awaddr,
  input [31:0]  s_axi_ps_awprot,
  input         s_axi_ps_awvalid,
  output        s_axi_ps_awready,

  input         s_axi_ps_bready,
  output [1:0]  s_axi_ps_bresp,
  output        s_axi_ps_bvalid,

  input         s_axi_ps_rready,
  output [31:0] s_axi_ps_rdata,
  output [1:0]  s_axi_ps_rresp,
  output        s_axi_ps_rvalid,

  input [31:0]  s_axi_ps_wdata,
  input [31:0]  s_axi_ps_wstrb,
  input         s_axi_ps_wvalid,
  output        s_axi_ps_wready,

  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 adc_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s00_axis_adc:s02_axis_adc" *)
  input s0_axis_adc_aclk, // 256 MHz
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 adc_rst RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input s0_axis_adc_aresetn,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s00_axis_adc TDATA" *)
  input [255:0] s00_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s00_axis_adc TVALID" *)
  input         s00_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s00_axis_adc TREADY" *)
  output        s00_axis_adc_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s02_axis_adc TDATA" *)
  input [255:0] s02_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s02_axis_adc TVALID" *)
  input         s02_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s02_axis_adc TREADY" *)
  output        s02_axis_adc_tready,

  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 dac_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF m00_axis_dac:m01_axis_dac" *)
  input m0_axis_dac_clk, // 384 MHz
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 dac_rst RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input m0_axis_dac_resetn,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m00_axis_dac TDATA" *)
  output [255:0]  m00_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m00_axis_dac TVALID" *)
  output          m00_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m00_axis_dac TREADY" *)
  input           m00_axis_dac_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m01_axis_dac TDATA" *)
  output [255:0]  m01_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m01_axis_dac TVALID" *)
  output          m01_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m01_axis_dac TREADY" *)
  input           m01_axis_dac_tready
);

endmodule
