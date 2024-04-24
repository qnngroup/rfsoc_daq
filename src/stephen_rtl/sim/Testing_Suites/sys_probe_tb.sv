`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module sys_probe_tb();
    logic clk,rst;
    logic[`A_BUS_WIDTH-1:0] raddr_packet, waddr_packet;
    logic[`WD_BUS_WIDTH-1:0] rdata_packet, wdata_packet;
    logic[`DMA_DATA_WIDTH-1:0] pwl_data;
    logic[3:0] pwl_tkeep;
    logic pwl_last, pwl_rdy, pwl_valid; 
    logic raddr_valid_packet, waddr_valid_packet, wdata_valid_packet, rdata_valid_out, wresp_valid_out, rresp_valid_out;
    logic ps_wresp_rdy,ps_read_rdy; 
    logic[1:0] wresp_out, rresp_out; 
    logic[(`BATCH_WIDTH)-1:0] dac_batch;
    logic valid_dac_batch, dac0_rdy;
    logic pl_rstn;
    logic[12:0] testReg; 

    top_level tl(.clk(clk), .sys_rst(rst),
                 .dac0_rdy(dac0_rdy),
                 .dac_batch(dac_batch),
                 .valid_dac_batch(valid_dac_batch),
                 .pl_rstn(pl_rstn),
                 .raddr_packet(raddr_packet),
                 .raddr_valid_packet(raddr_valid_packet),
                 .waddr_packet(waddr_packet),
                 .waddr_valid_packet(waddr_valid_packet),
                 .wdata_packet(wdata_packet),
                 .wdata_valid_packet(wdata_valid_packet),
                 .ps_wresp_rdy(ps_wresp_rdy),
                 .ps_read_rdy(ps_read_rdy),
                 .wresp_out(wresp_out),
                 .rresp_out(rresp_out),
                 .wresp_valid_out(wresp_valid_out),
                 .rresp_valid_out(rresp_valid_out),
                 .rdata_packet(rdata_packet),
                 .rdata_valid_out(rdata_valid_out),
                 .pwl_tdata(pwl_data),
                 .pwl_tkeep(pwl_tkeep),
                 .pwl_tlast(pwl_last),
                 .pwl_tvalid(pwl_valid),
                 .pwl_tready(pwl_rdy));

    localparam NUM_OF_POINTS = 60; 
    enum logic[1:0] {IDLE, SEND, WRESP_WAIT} pwlTestState;
    logic[NUM_OF_POINTS-1:0][`DMA_DATA_WIDTH-1:0] dma_buff; 
    logic[$clog2(NUM_OF_POINTS):0] dma_i; 
    logic send_dma_data; 

    assign dma_buff = {48'h744000000000, 48'h724d3592ffe5, 48'h70fb385dfffe, 48'h6fbb3b28fffe, 48'h6e693ddafffe, 48'h6d1740a5fffe, 48'h6bc54370fffe, 48'h6a85463bfffe, 48'h693348edfffe, 48'h67e14bb8fffe, 48'h668f4e83fffe, 48'h654f514efffe, 48'h63fd5419fffe, 48'h5ae37ffffffb, 48'h5ad142bd0367, 48'h59b44f03fff5, 48'h58515797fffa, 48'h56ed602bfffa, 48'h50e16628ffff, 48'h4b2f51b40004, 48'h457c3d410004, 48'h40d42d170003, 48'h3fb728e70004, 48'h3a812e63ffff, 48'h3a0514730036, 48'h345200000004, 48'h342f2fc9fea2, 48'h33473b28fff3, 48'h32ee4555ffe3, 48'h32954f82ffe3, 48'h324e5996ffdc, 48'h322b63dcffb5, 48'h3167655bfffe, 48'h30a366dbfffe, 48'h2e11597c0005, 48'h2d2a6390fff5, 48'h2c316da3fff6, 48'h29697737fffd, 48'h28a66c71000e, 48'h27d061c4000d, 48'h25f059160005, 48'h246962aafffa, 48'h22e16c57fffa, 48'h21e8771dfff5, 48'h21d6670e00e4, 48'h21c556fe00f2, 48'h20ba4d6a0009, 48'h1f7a56fefff8, 48'h1e396092fff8, 48'h1cf96a25fff8, 48'h19807406fffd, 48'h17b169d90006, 48'h15e35fac0006, 48'h141455650006, 48'h12464b380006, 48'h1066410b0005, 48'hdc233c60005, 48'h92c30af0001, 48'h4962d970001, 48'ha};
    assign pwl_data = dma_buff[dma_i]; 
    assign pwl_tkeep = 0; 
    assign pwl_last = dma_i == NUM_OF_POINTS-1; 
    assign ps_wresp_rdy = 1; 
    assign ps_read_rdy = 1; 
    assign dac0_rdy = 1; 

    always_ff @(posedge clk) begin
        if (rst) begin
            {raddr_packet, waddr_packet, wdata_packet} <= 0;
            {raddr_valid_packet, waddr_valid_packet, wdata_valid_packet} <= 0; 
            pwlTestState <= IDLE; 
            {dma_i,pwl_valid} <= 0;
            testReg <= 0;
        end else begin
            testReg <= testReg+1;
            if (waddr_valid_packet) {waddr_valid_packet, wdata_valid_packet} <= 0; 
            case(pwlTestState)
                IDLE: begin
                    if (send_dma_data) begin
                        pwlTestState <= WRESP_WAIT; 
                        waddr_packet <= `PWL_PREP_ADDR; 
                        wdata_packet <= 1; 
                        {waddr_valid_packet, wdata_valid_packet} <= 3; 
                        pwl_valid <= 1; 
                    end 
                end 
                WRESP_WAIT: begin
                    if (wresp_valid_out && wresp_out == `OKAY) pwlTestState <= SEND;
                end 
                SEND: begin
                    if (pwl_valid && pwl_rdy) begin
                        if (dma_i == NUM_OF_POINTS-1) begin
                            {dma_i,pwl_valid} <= 0;
                            pwlTestState <= IDLE; 
                            $display("Done Sending");
                        end else begin 
                            dma_i <= dma_i + 1; 
                            $write("%c[1;32m",27); 
                            $write(".%0d.",dma_i);
                            $write("%c[0m",27); 
                        end 
                    end
                end 
            endcase
        end
    end

    always begin
        #5;  
        clk = !clk;
    end

    initial begin
        $dumpfile("sys_probe_tb.vcd");
        $dumpvars(0,sys_probe_tb); 
        clk = 1;
        rst = 0;
        send_dma_data = 0;
        `flash_sig(rst) 
        #100;
        `flash_sig(send_dma_data) 
        #100;
        while (pwlTestState != IDLE) #10;
        #50000;
        $finish;
    end 

endmodule 

`default_nettype wire

