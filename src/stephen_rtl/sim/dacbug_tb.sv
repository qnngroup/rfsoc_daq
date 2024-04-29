`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module dacbug_tb();
    localparam COUNT_WIDTH = 32;
    localparam BURST_SIZE = 11;

    logic clk, rst, clk_enable; 
    logic[COUNT_WIDTH-1:0] count; 

    logic [`A_BUS_WIDTH-1:0] waddr_packet;
    logic [`WD_BUS_WIDTH-1:0] wdata_packet;
    logic waddr_valid_in, wdata_valid_in;
    logic[`WD_DATA_WIDTH-1:0] wdata;
    logic[`A_DATA_WIDTH-1:0] waddr;
    logic waddr_send,wdata_send,wSend;

    logic[`BATCH_WIDTH-1:0] dac_batch;
    logic valid_dac_batch;
    logic dac0_rdy;
    logic pl_rstn;

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
                  .dac0_rdy(dac0_rdy),
                  .waddr_packet(waddr_packet),
                  .waddr_valid_packet(waddr_valid_in),
                  .wdata_packet(wdata_packet),
                  .wdata_valid_packet(wdata_valid_in),
                  .ps_wresp_rdy(1'b1),      // in
                  .dac_batch(dac_batch),    // out
                  .valid_dac_batch(valid_dac_batch)); 

    counter #(.COUNTER_WIDTH(COUNT_WIDTH))
    cnt(.clk(clk),
        .rst(rst),
        .clk_enable(valid_dac_batch),
        .count(count));

    assign waddr_send = wSend; 
    assign wdata_send = wSend; 
    enum logic[1:0] {HIGH, ALTERNATE, DONE} drdyState; 
    
    always_ff @(posedge clk) begin
        if (rst) begin
            drdyState <= HIGH; 
            dac0_rdy <= 1; 
        end else begin
            case(drdyState)
                HIGH: begin
                    if (dac0_rdy == 0) dac0_rdy <= 1; 
                    if (count >= 1 && count < BURST_SIZE) begin
                        drdyState <= ALTERNATE; 
                        dac0_rdy <= 0;
                    end 
                    else if (count >= BURST_SIZE) drdyState <= DONE;
                end 

                ALTERNATE: begin
                    drdyState <= HIGH; 
                    dac0_rdy <= 1;
                end 
            endcase
        end
    end
    always begin
        #5;  
        clk = !clk;
    end
    initial begin
        $dumpfile("dacbug.vcd");
        $dumpvars(0,dacbug_tb); 
        clk = 1;
        rst = 0;
        waddr = 0;
        wdata = 0; 
        wSend = 0; 
        #100;
        `flash_sig(rst); 
        #100;

        waddr = `ILA_BURST_SIZE_ADDR;
        wdata = BURST_SIZE;
        `flash_sig(wSend); 
        #20;
        waddr = `TRIG_WAVE_ADDR;
        wdata = 1; 
        `flash_sig(wSend); 

        while(count < BURST_SIZE-3) #10; 

        #1000; 
        waddr = `TRIG_WAVE_ADDR;
        wdata = 1; 
        `flash_sig(wSend);

        #1000; 

        $finish;
    end 

endmodule 

`default_nettype wire
