`default_nettype none
`timescale 1ns / 1ps
`include "mem_layout.svh"

module bramint_tb();
    localparam DATA_WIDTH = 32;
    localparam BRAM_DEPTH = 501;
    localparam BRAM_DELAY = 3;

    logic clk,rst;
    logic next, valid_line_out, write_rdy;
    logic we, en;
    logic generator_mode, rst_gen_mode; 
    logic[$clog2(BRAM_DEPTH)-1:0] addr,generator_addr; 
    logic[DATA_WIDTH-1:0] line_in,line_out;
    logic[31:0] bram_out; 
    logic test;
    logic go; 
    enum logic[1:0] {IDLE, SAVE_LINES, READ_LINES} bramTestState;

    bram_interface #(.DATA_WIDTH(DATA_WIDTH), .BRAM_DEPTH(BRAM_DEPTH), .BRAM_DELAY(BRAM_DELAY))
    DUT(.clk(clk), .rst(rst),
        .addr(addr),
        .line_in(line_in),
        .we(we), .en(en),
        .generator_mode(generator_mode), .rst_gen_mode(rst_gen_mode),
        .next(next),
        .line_out(line_out),
        .generator_addr(generator_addr),
        .valid_line_out(valid_line_out),
        .write_rdy(write_rdy));

    always begin
        #5;  
        clk = !clk;
    end

    assign test = (valid_line_out)? line_out == generator_addr+100 : 0; 
    always_ff @(posedge clk) begin
        if (rst) begin
            {generator_mode, addr,next} <= 0;
            line_in <= 100; 
            {we, en} <= 3;
            bramTestState <= SAVE_LINES; 
        end else begin
            case(bramTestState)
                IDLE: begin
                    if (go) bramTestState <= SAVE_LINES;
                end 
                SAVE_LINES: begin
                    if (addr == BRAM_DEPTH-1) begin
                        addr <= 0; 
                        {we,en} <= 0;
                        generator_mode <= 1; 
                        bramTestState <= READ_LINES; 
                    end else begin
                        line_in <= line_in + 1;
                        addr <= addr + 1; 
                    end
                end 
                READ_LINES: begin
                    next <= (valid_line_out && go); 
                    if (rst_gen_mode) bramTestState <= IDLE;
                end 
            endcase 
        end
    end
    initial begin
        $dumpfile("bramint_tb.vcd");
        $dumpvars(0,bramint_tb); 
        clk = 0;
        rst = 0;
        go = 0;
        rst_gen_mode = 0;
        #10;
        `flash_sig(rst);
        while(bramTestState != READ_LINES) #10;
        #5000;
        `flash_sig(go);
        #300;
        go = 1;
        #4000;
        go = 0;
        #30;
        go = 1;
        #40;
        go = 0;
        #100;
        go = 1;
        #5000;
        $finish;
    end 

endmodule 

`default_nettype wire

