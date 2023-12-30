`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module lfsr_tb();
  logic clk,rst;
    logic[15:0] seed, sample_out; 
    LFSR #(.DATA_WIDTH(16)) 
    lfsr(.clk(clk), .rst(rst),
         .seed(seed),
         .sample_out(sample_out));

    always begin
        #5;  
        clk = !clk;
    end

    initial begin
        $dumpfile("lfsr.vcd");
        $dumpvars(0,lfsr_tb); 
        clk = 1;
        rst = 0;
        seed = -1;
        #10 rst = 1; #15 rst = 0; #10
        #5000
        $finish;
    end 

endmodule 



`default_nettype wire
