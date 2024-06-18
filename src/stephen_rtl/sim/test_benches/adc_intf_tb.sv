`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"
// import mem_layout_pkg::flash_signal;

module adc_intf_tb #(parameter MEM_SIZE, parameter DATA_WIDTH)
					(input wire clk, adc_rdy,
					 output logic rst, 
					 output logic[MEM_SIZE-1:0] fresh_bits,
					 output logic[MEM_SIZE-1:0][DATA_WIDTH-1:0] read_resps,
					 Axis_IF.stream_in bufft, 
					 Axis_IF.stream_out buffc, 
					 Axis_IF.stream_out cmc, 
					 Axis_IF.stream_out sdc);
	logic clk2; 
	logic[DATA_WIDTH-1:0] wd_list [$];
	assign clk2 = clk;

	task automatic init(); 
		{sdc.ready, cmc.ready, buffc.ready} <= 0;
		{bufft.valid, bufft.data, bufft.last} <= 0; 
		{fresh_bits,read_resps} <= 0;
		`flash_signal(rst,clk) 
	endtask

	task automatic populate_wd_list(input int size);
		logic[DATA_WIDTH-1:0] val; 
		for (int i = 0; i < size; i++) begin
			val = (size > 1 && i == size-1)? 1 : $urandom(); 
			wd_list.push_back(val); 
		end
	endtask 

	task automatic write_addr(input int start_i, input bit write_all = 1);
		int i = start_i;
		while (wd_list.size() > 0) begin
			fresh_bits[i] <= 1; 
			read_resps[i] <= wd_list.pop_front(); 
			i++; 
			if (~write_all) @(posedge clk); 
		end
		if (write_all) @(posedge clk); 
		while (~adc_rdy) @(posedge clk); 
		fresh_bits <= {MEM_SIZE{1'b0}};
	endtask 

endmodule 

`default_nettype wire

