`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"
// import mem_layout_pkg::flash_signal;
module bram_intf_tb #(parameter DATA_WIDTH, parameter BRAM_DEPTH)
					   (input wire clk,
						input wire[DATA_WIDTH-1:0] line_out,
						input wire valid_line_out,
						input wire[$clog2(BRAM_DEPTH)-1:0] generator_addr,
						input wire write_rdy,
						output logic rst, 
					    output logic [$clog2(BRAM_DEPTH)-1:0] addr,
						output logic[DATA_WIDTH-1:0] line_in,
						output logic we, en, 
						output logic generator_mode, rst_gen_mode, 
						output logic next);
	logic clk2; 
	assign clk2 = clk; 
	
	task automatic init();
		{addr,line_in,we,en,generator_mode,rst_gen_mode,next} <= 0;
		flash_signal(rst,clk2);
	endtask  
	
endmodule 

`default_nettype wire

