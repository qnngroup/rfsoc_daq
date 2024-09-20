`default_nettype none
`timescale 1ns / 1ps

import mem_layout_pkg::*;
import axi_params_pkg::*;
import daq_params_pkg::*;
module ps_intf_probe();
    localparam BUFF_LEN = 14;
    logic ps_clk,ps_rst,ps_rstn;
    logic dac_clk,dac_rst,dac_rstn;
    logic[A_BUS_WIDTH-1:0] raddr_packet, waddr_packet;
    logic[WD_BUS_WIDTH-1:0] rdata_packet, wdata_packet;
    logic[2:0] ps_axi_arprot,ps_axi_awprot;
    logic[3:0] ps_axi_wstrb;
    logic[63:0] pwl_data;
    logic[7:0] pwl_tkeep;
    logic[15:0] dma_timer, timer_limit;
    logic pwl_last, pwl_valid, pwl_ready; 
    logic raddr_valid_packet, waddr_valid_packet, wdata_valid_packet, rdata_valid_out, wresp_valid_out;
    logic ps_wresp_rdy,ps_read_rdy, ps_write_rdy,ps_awrite_rdy,ps_aread_rdy; 
    logic[1:0] wresp_out, rresp_out; 
    logic[BATCH_WIDTH-1:0] dac_batch;
    logic valid_dac_batch, rtl_dac_valid, dac0_rdy;
    logic pl_rstn;
    logic[12:0] testReg; 
    logic[BUFF_LEN-1:0][DMA_DATA_WIDTH-1:0] dma_buff, dma_buff2;
    logic[13:0][6:0] delays = {7'd1, 7'd44, 7'd121, 7'd109, 7'd86, 7'd100, 7'd112, 7'd28, 7'd73, 7'd20, 7'd76, 7'd141, 7'd42, 7'd64}; 
    logic[$clog2(BUFF_LEN)-1:0] dma_i; 
    logic send_dma_data,set_seeds,run_pwl,halt_dac,run_trig;
    logic first_sent, which_period; 
    logic[DATAW-1:0] pwl_period0, pwl_period1; 
    enum logic[1:0] {IDLE_D, SEND_DMA_DATA,HOLD_CMD,DMA_WAIT} dmaState;
    enum logic[1:0] {IDLE_T, SET_SEEDS,WRESP,ERROR} dacTestState;
    enum logic {SEND_ADDR, GET_DATA} readState;

    assign dma_buff = {48'd1025, 48'd69818987317185, 48'd70368743129104, 48'd70364449210384, 48'd70364449211553, 48'd35180078433057, 48'd35180077123233, 48'd35180077121540, 48'd50242511372316, 48'd134423870374049, 48'd140737472299020, 48'd140733193388052, 48'd140733193389985, 48'd33489025}; 
    assign dma_buff2 = {48'd993, 48'd16, 48'd519690059792, 48'd5673650815137, 48'd6446744928280, 48'd6442450944008, 48'd6442450944193, 48'd257698366017, 48'd327704, 48'd38654574600, 48'd3337189458689, 48'd3440268673048, 48'd3298535407624, 48'd524481};
    assign {ps_wresp_rdy,ps_read_rdy,dac0_rdy,pwl_tkeep} = -1;
    assign ps_rstn = ~ps_rst;
    assign dac_rstn = ~dac_rst;
    assign pwl_last = dma_i == BUFF_LEN && pwl_valid;

    // ps_interface ps_interface(.ps_clk(ps_clk),.ps_rstn(ps_rstn), .pl_rstn(pl_rstn),
    //                           .dac_clk(dac_clk),.dac_rstn(dac_rstn),
    //                           .dac_tdata(dac_batch),.dac_tvalid(valid_dac_batch),.dac_tready(dac0_rdy),.rtl_dac_valid(rtl_dac_valid),
    //                           .ps_axi_araddr(raddr_packet),.ps_axi_arprot(ps_axi_arprot),.ps_axi_arvalid(raddr_valid_packet),.ps_axi_arready(ps_aread_rdy),
    //                           .ps_axi_rdata(rdata_packet),.ps_axi_rresp(rresp_out),.ps_axi_rvalid(rdata_valid_out),.ps_axi_rready(ps_read_rdy),
    //                           .ps_axi_awaddr(waddr_packet),.ps_axi_awprot(ps_axi_awprot),.ps_axi_awvalid(waddr_valid_packet),.ps_axi_awready(ps_awrite_rdy),
    //                           .ps_axi_wdata(wdata_packet),.ps_axi_wstrb(ps_axi_wstrb),.ps_axi_wvalid(wdata_valid_packet),.ps_axi_wready(ps_write_rdy),
    //                           .ps_axi_bresp(wresp_out),.ps_axi_bvalid(wresp_valid_out),.ps_axi_bready(ps_wresp_rdy),
    //                           .pwl_tdata(pwl_data),.pwl_tkeep(pwl_tkeep),.pwl_tlast(pwl_last),.pwl_tvalid(pwl_valid),.pwl_tready(pwl_ready));

    logic[(daq_params_pkg::SAMPLE_WIDTH)-1:0] x;
    logic[(2*(daq_params_pkg::SAMPLE_WIDTH))-1:0] slope; 
    logic[(daq_params_pkg::BATCH_SIZE)-1:0][(daq_params_pkg::SAMPLE_WIDTH)-1:0] intrp_batch;
    interpolater #(.SAMPLE_WIDTH(daq_params_pkg::SAMPLE_WIDTH), .BATCH_SIZE(daq_params_pkg::BATCH_SIZE))
    dut_i(.clk(dac_clk),
          .x(x), .slope(slope),
          .intrp_batch(intrp_batch));

    always begin
        #3.333333;  
        ps_clk = !ps_clk;
    end
    always begin
        #1.3020833;  
        dac_clk = !dac_clk;
    end

    initial begin
        $dumpfile("ps_intf_probe.vcd");
        $dumpvars(0,ps_intf_probe); 
        ps_clk = 0;
        dac_clk = 0;
        ps_rst = 0;
        dac_rst = 0; 
        send_dma_data = 0;
        {set_seeds,run_pwl,halt_dac,run_trig} = 0; 
        #10;
        fork 
            begin sim_util_pkg::flash_signal(dac_rst,dac_clk); end 
            begin sim_util_pkg::flash_signal(ps_rst,ps_clk); end 
        join 
        #5000;
        $finish;
    end 

endmodule 

`default_nettype wire

