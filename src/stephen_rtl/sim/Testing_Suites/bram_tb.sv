`default_nettype none
`timescale 1ns / 1ps
`include "mem_layout.svh"

module bram_tb();
    logic clk,rst;
    logic nxt, rdy;
    logic[31:0] bram_out; 
    logic go; 

    bram_test_top 
    test_top(.clk(clk), .rst(rst),
              .nxt(nxt), .rdy(rdy),
              .bram_out(bram_out));

    always begin
        #5;  
        clk = !clk;
    end
    always_ff @(posedge clk) begin
        if (rst) nxt <= 0;
        else begin
            if (rdy && go) nxt <= 1;
            else nxt <= 0;
        end
    end
    initial begin
        $dumpfile("bram_tb.vcd");
        $dumpvars(0,bram_tb); 
        clk = 0;
        rst = 0;
        go = 0;
        #10;
        `flash_sig(rst);
        while (~rdy) #10; 
        #300;
        go = 1;
        #50; go = 0;
        #100 go = 1; 
        #200 go = 0; 
        #10; go = 1; 
        #5000;
        $finish;
    end 

endmodule 

`default_nettype wire

