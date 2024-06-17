`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"
// import mem_layout_pkg::flash_signal;
module adc_intf_tb #(parameter MEM_SIZE, parameter DATA_WIDTH)
					(input wire clk,
					 output logic rst, 
					 output logic[MEM_SIZE-1:0] fresh_bits,
					 output logic[MEM_SIZE-1:0][DATA_WIDTH-1:0] read_resps,
					 Axis_IF.stream_in bufft, 
					 Axis_IF.stream_out buffc, 
					 Axis_IF.stream_out cmc, 
					 Axis_IF.stream_out sdc);

	task automatic init(); 
		{sdc.ready, cmc.ready, buffc.ready} <= 0;
		{bufft.valid, bufft.data, bufft.last} <= 0; 
		{fresh_bits,read_resps} <= 0; 
	endtask

	
endmodule 

`default_nettype wire

