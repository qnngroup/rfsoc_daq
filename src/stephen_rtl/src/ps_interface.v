`timescale 1ns / 1ps
module ps_interface(input clk, rstn, 
                    //DAC 
                    input s10_axis_tready,
                    output[1023:0] s10_axis_tdata,
                    output s10_axis_tvalid, 
                    output dac_valid_outDB,
                    output pl_rstn, 
                    //PS 
                    input[31:0] M03_AXI_araddr,
                    input[31:0] M03_AXI_arprot,
                    input M03_AXI_arvalid,
                    input[31:0] M03_AXI_awaddr,
                    input[31:0] M03_AXI_awprot,
                    input M03_AXI_awvalid,
                    input M03_AXI_bready,
                    input M03_AXI_rready,
                    input[31:0] M03_AXI_wdata,
                    input[31:0] M03_AXI_wstrb,
                    input M03_AXI_wvalid,
                    output M03_AXI_arready,
                    output M03_AXI_awready,
                    output[1:0] M03_AXI_bresp,
                    output M03_AXI_bvalid,
                    output[31:0] M03_AXI_rdata,
                    output[1:0] M03_AXI_rresp,
                    output M03_AXI_rvalid,
                    output M03_AXI_wready,
                    // PWL DMA 
                    input [63:0] pwl_tdata,
                    input [7:0] pwl_tkeep,
                    input pwl_tlast, pwl_tvalid,
                    output pwl_tready);
                    //Sample Discriminator Config Inputs/Outputs (axi-stream)
//                    output[255:0] sdc_tdata,
//                    output[3:0] sdc_tkeep,
//                    output sdc_tlast, sdc_tvalid,
//                    input sdc_tready,
//                    //Buffer Config Inputs/Outputs (axi-stream)
//                    output[7:0] buffc_tdata,
//                    output[3:0] buffc_tkeep,
//                    output buffc_tlast, buffc_tvalid,
//                    input buffc_tready,
//                    //Channel Mux Config Inputs/Outputs (axi-stream)
//                    output[31:0] cmc_tdata,
//                    output[3:0] cmc_tkeep,
//                    output cmc_tlast, cmc_tvalid,
//                    input cmc_tready,
//                    //Buffer Timestamp Inputs/Outputs (axi-stream)
//                    input[31:0] bufft_tdata,
//                    input[3:0] bufft_tkeep,
//                    input bufft_tlast, bufft_tvalid,
//                    output bufft_tready);
    wire[1023:0] dac_data; 
    
    assign M03_AXI_arready = M03_AXI_arvalid;
    assign M03_AXI_awready = M03_AXI_awvalid;
    assign M03_AXI_wready = M03_AXI_wvalid;
    assign s10_axis_tvalid = 1; 
    assign s10_axis_tdata = (dac_valid_outDB)? dac_data : 0; 
    
    top_level tl (.clk(clk),                     .sys_rst(~rstn),                     .pl_rstn(pl_rstn), 
                  .raddr_packet(M03_AXI_araddr), .raddr_valid_packet(M03_AXI_arvalid),
                  .waddr_packet(M03_AXI_awaddr), .waddr_valid_packet(M03_AXI_awvalid),
                  .wdata_packet(M03_AXI_wdata),  .wdata_valid_packet(M03_AXI_wvalid),
                  .ps_wresp_rdy(M03_AXI_bready), .ps_read_rdy(M03_AXI_rready),        .dac0_rdy(s10_axis_tready),      
                  .dac_batch(dac_data),          .valid_dac_batch(dac_valid_outDB),
                  .wresp_out(M03_AXI_bresp),     .rresp_out(M03_AXI_rresp),           .wresp_valid_out(M03_AXI_bvalid),
                  .rdata_packet(M03_AXI_rdata),  .rdata_valid_out(M03_AXI_rvalid),
                  .pwl_tdata(pwl_tdata[47:0]),         .pwl_tkeep(pwl_tkeep),               .pwl_tlast(pwl_tlast),     .pwl_tvalid(pwl_tvalid),     .pwl_tready(pwl_tready));
//                  .sdc_tdata(sdc_tdata),         .sdc_tkeep(sdc_tkeep),               .sdc_tlast(sdc_tlast),     .sdc_tvalid(sdc_tvalid),     .sdc_tready(sdc_tready),
//                  .buffc_tdata(buffc_tdata),     .buffc_tkeep(buffc_tkeep),           .buffc_tlast(buffc_tlast), .buffc_tvalid(buffc_tvalid), .buffc_tready(buffc_tready),
//                  .cmc_tdata(cmc_tdata),         .cmc_tkeep(cmc_tkeep),               .cmc_tlast(cmc_tlast),     .cmc_tvalid(cmc_tvalid),     .cmc_tready(cmc_tready),
//                  .bufft_tdata(bufft_tdata),     .bufft_tkeep(bufft_tkeep),           .bufft_tlast(bufft_tlast), .bufft_tvalid(bufft_tvalid), .bufft_tready(bufft_tready));
endmodule 
