`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"

module bram_intf_test();
	localparam TIMEOUT = 1000;
	localparam TEST_NUM = 12*2; //12 with oscillating rdy, 12 with constant ready
	localparam int PS_CLK_RATE_HZ = 100_000_000;
	always #(0.5s/PS_CLK_RATE_HZ) clk = ~clk;
logic clk, rst; 
	initial begin
        $dumpfile("bram_intf_test.vcd");
        $dumpvars(0,bram_intf_test); 
        {clk,rst} = 0;
     	repeat (20) @(posedge clk);
        debug.displayc($sformatf("\n\n### TESTING %s ###\n\n",debug.get_test_name()));
     	debug.timeout_watcher(clk,TIMEOUT);
        repeat (5) @(posedge clk);
        `flash_signal(rst,clk);        
       	repeat (20) @(posedge clk);
       	#500;
       	$finish;
    end 
endmodule 

`default_nettype wire

