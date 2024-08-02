`timescale 1ns / 1ps
module ps_interface(
                    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ps_clk CLK" *)
                    (* X_INTERFACE_PARAMETER = "FREQ_HZ 149998505, ASSOCIATED_BUSIF \
                      ps_axi" *)
                    input wire ps_clk,
                    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ps_rstn RST" *)
                    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
                    input wire ps_rstn, 
                    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 dac_clk CLK" *)
                    (* X_INTERFACE_PARAMETER = "FREQ_HZ 384000000, ASSOCIATED_BUSIF \
                      dac:\
                      pwl" *)
                    input wire dac_clk, 
                    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 dac_rstn RST" *)
                    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
                    input wire dac_rstn, 
                    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 pl_rstn RST" *)
                    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
                    output wire pl_rstn,

                    //DAC OUTPUT INTERFACE
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 dac TDATA" *)
                    output wire[255:0] dac_tdata,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 dac TVALID" *)
                    output wire        dac_tvalid, 
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 dac TREADY" *)
                    input  wire        dac_tready, 
                    output wire        rtl_dac_valid,

                    //PS AXI-LITE INTERFACE
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi ARADDR" *)
                    input  wire[31:0] ps_axi_araddr, 
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi ARPROT" *)
                    input  wire[2:0]  ps_axi_arprot,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi ARVALID" *)
                    input  wire       ps_axi_arvalid,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi ARREADY" *)
                    output wire       ps_axi_arready,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi RDATA" *)
                    output wire[31:0] ps_axi_rdata,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi RRESP" *)
                    output wire[1:0]  ps_axi_rresp,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi RVALID" *)
                    output wire       ps_axi_rvalid,  
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi RREADY" *)
                    input  wire       ps_axi_rready,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi AWADDR" *)
                    input  wire[31:0] ps_axi_awaddr,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi AWPROT" *)
                    input  wire[2:0]  ps_axi_awprot,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi AWVALID" *)
                    input  wire       ps_axi_awvalid,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi AWREADY" *)
                    output wire       ps_axi_awready,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi WDATA" *)
                    input  wire[31:0] ps_axi_wdata,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi WSTRB" *)
                    input  wire[3:0]  ps_axi_wstrb,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi WVALID" *)
                    input  wire       ps_axi_wvalid,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi WREADY" *)
                    output wire       ps_axi_wready,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi BRESP" *)
                    output wire[1:0] ps_axi_bresp,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi BVALID" *)
                    output wire      ps_axi_bvalid,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi BREADY" *)
                    input  wire      ps_axi_bready,

                    //PWL DMA INTERFACE
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 pwl TDATA" *)
                    input wire[63:0] pwl_tdata,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 pwl TKEEP" *)
                    input wire[7:0] pwl_tkeep,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 pwl TLAST" *)
                    input wire pwl_tlast, 
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 pwl TVALID" *)
                    input wire pwl_tvalid,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 pwl TREADY" *)
                    output wire pwl_tready);
    wire[255:0] dac_data; 
    
   assign ps_axi_arready = ps_axi_arvalid; 
   assign ps_axi_awready = ps_axi_awvalid;
   assign ps_axi_wready = ps_axi_wvalid;
   assign dac_tdata = (rtl_dac_valid)? dac_data : 0; 
   assign dac_tvalid = 1;  
    
    top_level tl(.ps_clk(ps_clk),.ps_rst(~ps_rstn), .dac_clk(dac_clk),.dac_rst(~dac_rstn), .pl_rstn(pl_rstn),
                 .raddr_packet(ps_axi_araddr),   .raddr_valid_packet(ps_axi_arvalid),
                 .waddr_packet(ps_axi_awaddr),   .waddr_valid_packet(ps_axi_awvalid),
                 .wdata_packet(ps_axi_wdata),    .wdata_valid_packet(ps_axi_wvalid),
                 .ps_wresp_rdy(ps_axi_bready),   .ps_read_rdy(ps_axi_rready),        .dac0_rdy(dac_tready),      
                 .dac_batch(dac_data),            .valid_dac_batch(rtl_dac_valid),
                 .wresp_out(ps_axi_bresp),       .rresp_out(ps_axi_rresp),           .wresp_valid_out(ps_axi_bvalid),
                 .rdata_packet(ps_axi_rdata),    .rdata_valid_out(ps_axi_rvalid),
                 .pwl_tdata(pwl_tdata[47:0]),     .pwl_tlast(pwl_tlast),     .pwl_tvalid(pwl_tvalid),     .pwl_tready(pwl_tready));

endmodule 
