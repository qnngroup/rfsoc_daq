`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module stw_tb();
    localparam BURST_SIZE = 5;

    logic clk, rst, clk_enable; 

    logic [`A_BUS_WIDTH-1:0] waddr_packet;
    logic [`WD_BUS_WIDTH-1:0] wdata_packet;
    logic waddr_valid_in, wdata_valid_in;
    logic[`WD_DATA_WIDTH-1:0] wdata;
    logic[`A_DATA_WIDTH-1:0] waddr;
    logic waddr_send,wdata_send,w_send;

    logic[`BATCH_WIDTH-1:0] dac_batch;
    logic[`SAMPLE_WIDTH-1:0] first_sample; 
    logic valid_dac_batch;
    logic pl_rstn;

    int scale; 
    axi_transmit  #(.BUS_WIDTH(`A_BUS_WIDTH), .DATA_WIDTH(`A_DATA_WIDTH)) 
    w_addr_ps_transmitter(.clk(clk), .rst(rst),
                          .data_to_send(waddr),
                          .send(waddr_send),
                          .device_rdy(1'b1),
                          .axi_packet(waddr_packet),
                          .valid_pack(waddr_valid_in));

    axi_transmit  #(.BUS_WIDTH(`WD_BUS_WIDTH), .DATA_WIDTH(`WD_DATA_WIDTH)) 
    w_data_ps_transmitter(.clk(clk), .rst(rst),
                          .data_to_send(wdata),
                          .send(wdata_send),
                          .device_rdy(1'b1),
                          .axi_packet(wdata_packet),
                          .valid_pack(wdata_valid_in));

    top_level tl (.clk(clk),
                  .sys_rst(rst),
                  .dac0_rdy(1'b1),
                  .waddr_packet(waddr_packet),
                  .waddr_valid_packet(waddr_valid_in),
                  .wdata_packet(wdata_packet),
                  .wdata_valid_packet(wdata_valid_in),
                  .ps_wresp_rdy(1'b1),      // in
                  .dac_batch(dac_batch),    // out
                  .valid_dac_batch(valid_dac_batch)); 

    assign waddr_send = w_send; 
    assign wdata_send = w_send; 
    assign first_sample = dac_batch[`SAMPLE_WIDTH-1:0];

    always begin
        #5;  
        clk = !clk;
    end

    initial begin
        $dumpfile("stw_tb.vcd");
        $dumpvars(0,stw_tb); 
        clk = 1;
        rst = 0;
        waddr = 0;
        wdata = 0; 
        w_send = 0; 
        #100;
        `flash_sig(rst); 
        #100;

        waddr = `ILA_BURST_SIZE_ADDR;
        wdata = BURST_SIZE;
        `flash_sig(w_send); 
        #20;
        waddr = `TRIG_WAVE_ADDR;
        wdata = 1; 
        `flash_sig(w_send);

        #1000;
        waddr = `DAC_HLT_ADDR;
        wdata = 1;
        `flash_sig(w_send); 
        #10; 
        waddr = `ILA_BURST_SIZE_ADDR;
        wdata = 0;
        `flash_sig(w_send); 
        #10
        waddr = `TRIG_WAVE_ADDR;
        wdata = 1; 
        `flash_sig(w_send);
        #1000; 

        for (scale = 0; scale < 20; scale++) begin
            waddr = `SCALE_DAC_OUT_ADDR;
            wdata = scale;
            `flash_sig(w_send); 
            #10000;
        end 
        #1000;

        $finish;
    end 

endmodule 

`default_nettype wire
