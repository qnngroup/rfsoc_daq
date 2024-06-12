`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"
// import mem_layout_pkg::flash_signal;
module pwl_tb #(parameter SAMPLE_WIDTH, parameter DMA_DATA_WIDTH, parameter BATCH_SIZE)
					   (input wire clk,
					   	input wire valid_batch, 
					   	input wire[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] batch,
					   	output logic rst, 
					   	output logic halt, run_pwl,
					    Axis_IF dma);
	int period_len; 
	int expc_wave [$];
	logic clk2;
	assign clk2 = clk; 
	task automatic init();
		{halt, run_pwl} <= 0;
		{dma.data,dma.valid,dma.last} <= 0;
		`flash_signal(rst,clk2);
	endtask 

	function void clear_wave();
		while (expc_wave.size() > 0) expc_wave.pop_back();
		period_len = 0;
	endfunction

	function void reverse_wave();
		int expc_wave_tmp [$];
		while (expc_wave.size() > 0) expc_wave_tmp.push_back(expc_wave.pop_back());
	    expc_wave = expc_wave_tmp;
	endfunction

	task automatic halt_pwl();
		run_pwl <= 0;
		`flash_signal(halt,clk2);
	endtask

	task automatic send_buff(input logic[DMA_DATA_WIDTH-1:0] dma_buff [$], input bit osc_rdy = 0, input int range[1:0] = {0,5});
		int delay_timer; 
		dma.valid <= 1; 
		for (int i = 0; i < dma_buff.size(); i++) begin
			dma.data <= dma_buff[i]; 
			if (i == dma_buff.size()-1) dma.last <= 1; 
			@(posedge clk); 
			while (~dma.ready) @(posedge clk); 
			if (osc_rdy) begin 
				{dma.valid,dma.last} <= 0; 
				@(posedge clk);
				delay_timer = $urandom_range(range[0],range[1]);
				repeat(delay_timer) @(posedge clk);				
			end 
		end
		{dma.valid,dma.last} <= 0; 
		@(posedge clk);		
	endtask 

	task automatic send_single_batch(input bit is_sparse); 
		logic[DMA_DATA_WIDTH-1:0] dma_buff [$];
		clear_wave();
		if (is_sparse) begin
			dma_buff = {64'd36936744993};
			expc_wave = {129,120,111,103,94,86,77,68,60,51,43,34,25,17,8,0};
		end else begin 
			dma_buff = {64'd8589934608, 64'd4503850882957316, 64'd37717504071565320, 64'd4294967298, 64'd281474976710658};
			expc_wave = {1,0,34,67,100,133,74,16,14,12,10,8,6,4,2,0};
		end 
		send_buff(dma_buff);
		period_len = 1; 
	endtask 

	task automatic check_pwl_wave(inout sim_util_pkg::debug debug, input int periods_to_check);
		int expc_wave_tmp [$];
		int samples_seen,periods_seen,expc_sample;
		periods_seen = 0; 
		run_pwl <= 1; 
		@(posedge clk);
		repeat(periods_to_check) begin
			expc_wave_tmp = expc_wave;
			samples_seen = 0; 
			for (int i = 0; i < period_len; i+=BATCH_SIZE) begin
				while (~valid_batch) @(posedge clk); 
				for (int j = 0; j < BATCH_SIZE; j++) begin 
					expc_sample = expc_wave_tmp.pop_back();
					debug.disp_test_part(2+periods_seen+samples_seen, $signed(batch[j]) == expc_sample,$sformatf("Error on %0dth sample: Expected %0d, Got %0d",samples_seen, expc_sample, $signed(batch[j])));
					samples_seen++;
					@(posedge clk); 
				end 
			end
			periods_seen++;
		end
	endtask 

	task automatic send_pwl_wave(input bit osc_rdy = 0, input int range[1:0] = {0,5});
		//coords = [(0,0), (-6,5),(6,16),(10,40),(0,64),(10,74), (-15, 84), (10,130), (0,135)]
		logic[DMA_DATA_WIDTH-1:0] dma_buff [$];
		clear_wave();
		expc_wave = {0,-1,-2,-3,-4,-6,-5,-4,-3,-2,-1,0,1,2,3,4,6,6,6,6,6,6,7,7,7,7,7,7,8,8,8,8,8,8,8,8,8,8,9,9,10,10,10,9,9,8,8,8,7,7,7,6,6,5,5,5,4,4,3,3,2,2,2,1,0,1,2,3,4,5,6,7,8,9,10,8,5,3,0,-2,-5,-7,-10,-12,-15,-15,-14,-14,-13,-13,-12,-12,-11,-11,-10,-10,-9,-9,-8,-8,-7,-7,-6,-6,-5,-5,-4,-4,-3,-2,-2,-1,-1,0,0,1,1,2,2,3,4,4,5,5,6,6,7,7,8,8,10,8,6,4,2,0,0,0,0,0,0,0,0,0};
		dma_buff = {64'd281469822763018, 64'd18445055228534718486, 64'd1688850576113697, 64'd2251800529534992, 64'd3096222954225680, 64'd2251798024093729, 64'd4294967316, 64'd3096214006398988, 64'd18445618163065290760, 64'd18442521951393087512, 64'd18444210801253351489, 64'd2251802147880964, 64'd3096216153882634, 64'd18};
		send_buff(dma_buff, osc_rdy, range);
		period_len = expc_wave.size()/BATCH_SIZE;
	endtask  					   
	

endmodule 

`default_nettype wire

