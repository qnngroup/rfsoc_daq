`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"
// import mem_layout_pkg::flash_signal;
module dac_intf_tb #(parameter MEM_SIZE, parameter DATA_WIDTH, parameter BATCH_SIZE, parameter DMA_DATA_WIDTH, parameter MAX_DAC_BURST_SIZE)
					   (input wire ps_clk,dac_clk,
					   	input wire dac_intf_rdy, pwl_rdy,
					   	input wire[BATCH_SIZE-1:0][DATA_WIDTH-1:0] dac_batch,
					   	input wire[$clog2(DATA_WIDTH)-1:0] scale_factor_out,
					   	input wire[$clog2(MAX_DAC_BURST_SIZE):0] dac_bs_out, halt_counter,
					  	input wire valid_dac_batch,
					   	output logic ps_rst, dac_rst, 
						output logic[MEM_SIZE-1:0] fresh_bits,
						output logic[MEM_SIZE-1:0][DATA_WIDTH-1:0] read_resps,
						output logic[$clog2(DATA_WIDTH)-1:0] scale_factor_in,
						output logic[$clog2(MAX_DAC_BURST_SIZE):0] dac_bs_in,
						output logic halt,
						Axis_IF dma);

	localparam BATCH_WIDTH = BATCH_SIZE*DATA_WIDTH;					   
	int period_len;	
	int expc_wave [$];


	task automatic init();
		{dma.valid, dma.last, dma.data} <= 0;
		{read_resps, scale_factor_in, dac_bs_in, fresh_bits, halt} <= 0;
		fork 
			begin `flash_signal(ps_rst,ps_clk); end 
			begin `flash_signal(dac_rst, dac_clk); end 
		join_none 
	endtask 

	task automatic notify_dac(logic[$clog2(MEM_SIZE)-1:0] id);
		fresh_bits[id] <= 1; 
		@(posedge ps_clk);
		while (~dac_intf_rdy) @(posedge ps_clk);
		fresh_bits[id] <= 0; 
	endtask 
	
	task automatic send_rand_samples(inout sim_util_pkg::debug debug);
		logic[BATCH_SIZE-1:0][DATA_WIDTH-1:0] expected;
		for (int i = 0; i < BATCH_SIZE; i++) expected[i] = 16'hBEEF+i;	
		for (int i = `PS_SEED_BASE_ID; i < `PS_SEED_VALID_ID; i++) read_resps[i] <= 16'hBEEF+(i-`PS_SEED_BASE_ID);
		read_resps[`PS_SEED_VALID_ID] <= 1; 
		for (int i = `PS_SEED_BASE_ID; i <= `PS_SEED_VALID_ID; i++) notify_dac(i); 
		while (~valid_dac_batch) @(posedge dac_clk);
		for (int i = 0; i < BATCH_SIZE; i++) debug.disp_test_part(i,dac_batch[i] == expected[i], $sformatf("Error on random wave sample #%0d: expected %0d got %0d",i, expected[i], dac_batch[i]));
		while (~dac_intf_rdy) @(posedge ps_clk);	
	endtask 

	task automatic send_trig_wave(inout sim_util_pkg::debug debug, input int samples_to_check);	
		int starting_val = 0;
		logic[BATCH_SIZE-1:0][DATA_WIDTH-1:0] expected = 0;			
		notify_dac(`TRIG_WAVE_ID);
		for (int n = 0; n < samples_to_check; n++) begin
			while (~valid_dac_batch) @(posedge dac_clk);
			for (int i = 0; i < BATCH_SIZE; i++) expected[i] = starting_val+i;
			starting_val+=BATCH_SIZE; 
			for (int i = 0; i < BATCH_SIZE; i++) debug.disp_test_part(i,dac_batch[i] == expected[i], $sformatf("Error on triangle wave sample #%0d: expected %0d got %0d",n, expected[i], dac_batch[i]));
			@(posedge dac_clk);
		end
		while (~dac_intf_rdy) @(posedge ps_clk);
	endtask


	function void clear_wave();
		while (expc_wave.size() > 0) expc_wave.pop_back();
		period_len = 0;
	endfunction

	task automatic halt_dac();
		`flash_signal(halt,ps_clk);
		while (valid_dac_batch) @(posedge dac_clk);
		while (~dac_intf_rdy) @(posedge ps_clk);
	endtask 

	task automatic send_buff(input logic[DMA_DATA_WIDTH-1:0] dma_buff [$]);
		int delay_timer; 
		halt_dac(); 
		while (~pwl_rdy) @(posedge dac_clk); 
		for (int i = 0; i < dma_buff.size(); i++) begin
			dma.valid <= 1; 
			dma.data <= dma_buff[i]; 
			if (i == dma_buff.size()-1) dma.last <= 1; 
			@(posedge dac_clk); 
			while (~dma.ready) @(posedge dac_clk); 
			{dma.valid,dma.last} <= 0; 
			@(posedge dac_clk);
			delay_timer = $urandom_range(0,10);
			repeat(delay_timer) @(posedge dac_clk);				
		end
		{dma.valid,dma.last} <= 0; 
		@(posedge dac_clk);		
	endtask 

	task automatic send_pwl_wave();
		logic[DMA_DATA_WIDTH-1:0] dma_buff [$];
		clear_wave();
		dma_buff = {64'd281469822763018, 64'd18445055228534718486, 64'd1688850576113697, 64'd2533275506245648, 64'd3096222954225680, 64'd2251798024093729, 64'd4294967316, 64'd3096214006398988, 64'd18445618163065290760, 64'd18442521951393087512, 64'd18444492276230062145, 64'd2533277124591620, 64'd3096216153882634, 64'd18};
		expc_wave = {0,0,0,0,0,0,0,0,0,2,4,6,8,10,10,9,9,8,8,7,7,6,6,5,4,4,3,3,2,2,1,1,0,0,-1,-1,-2,-3,-3,-4,-4,-5,-5,-6,-6,-7,-7,-8,-9,-10,-10,-11,-11,-12,-12,-13,-13,-14,-14,-15,-12,-10,-7,-5,-2,0,3,5,8,10,9,8,7,6,5,4,3,2,1,0,1,1,2,2,2,3,3,4,4,4,5,5,6,6,7,7,7,7,8,8,9,9,10,10,10,10,10,10,10,9,9,9,9,8,8,8,8,8,8,7,7,7,7,7,7,6,6,6,5,4,3,2,1,-1,-2,-3,-4,-5,-6,-5,-4,-2,-1,0};
		send_buff(dma_buff);
		period_len = expc_wave.size()/BATCH_SIZE;
	endtask  	

	task automatic send_step_pwl_wave();
		logic[DMA_DATA_WIDTH-1:0] dma_buff [$];
		clear_wave();
		dma_buff = {64'd1407374883553280030, 64'd1407643473628102658, 64'd562949953421312030, 64'd563223267960160258, 64'd28147497671065633};
		expc_wave = {100,100,100,100,100,100,100,100,100,100,100,100,100,100,100,100,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000};
		send_buff(dma_buff);
		period_len = expc_wave.size()/BATCH_SIZE;
	endtask 				   

	task automatic check_pwl_wave(inout sim_util_pkg::debug debug, input int periods_to_check);
		int expc_wave_tmp [$];
		int samples_seen,periods_seen,expc_sample;
		bit do_print;
		periods_seen = 0; 
		notify_dac(`RUN_PWL_ID);
		@(posedge ps_clk);
		repeat(periods_to_check) begin
			expc_wave_tmp = expc_wave;
			samples_seen = 0; 
			if (periods_to_check > 1) debug.displayc($sformatf("\nPeriod %0d",periods_seen), .msg_color(sim_util_pkg::BLUE), .msg_verbosity(sim_util_pkg::DEBUG));
			for (int i = 0; i < period_len; i++) begin
				while (~valid_dac_batch) @(posedge dac_clk); 
				for (int j = 0; j < BATCH_SIZE; j++) begin 
					expc_sample = expc_wave_tmp.pop_back();
					debug.disp_test_part(1+samples_seen, $signed(dac_batch[j]) == expc_sample,$sformatf("Error on %0dth sample: Expected %0d, Got %0d",samples_seen, expc_sample, $signed(dac_batch[j])));
					samples_seen++;
				end 
				@(posedge dac_clk); 
			end
			periods_seen++;
		end
	endtask 

	task automatic send_dac_configs(int delay_range[2]);
		@(posedge ps_clk);
		scale_factor_in <= $urandom_range(1,15);
		if (delay_range[1] > 0) repeat($urandom_range(delay_range[0],delay_range[1])) @(posedge ps_clk); 
		dac_bs_in <= $urandom_range(1,`MAX_DAC_BURST_SIZE);
		@(posedge ps_clk);
		while (~dac_intf_rdy && (dac_bs_in != dac_bs_out) || (scale_factor_in != scale_factor_out)) @(posedge ps_clk); 
		{scale_factor_in, dac_bs_in} <= 0;
		@(posedge ps_clk) 
		while (~dac_intf_rdy && (dac_bs_in != dac_bs_out) || (scale_factor_in != scale_factor_out)) @(posedge ps_clk);
	endtask 

	task automatic scale_check(inout sim_util_pkg::debug debug, int scale_factor);
		int expc_wave_tmp [$] = expc_wave;
		halt_dac();
		@(posedge ps_clk);
		scale_factor_in <= scale_factor;
		for (int i = 0; i < expc_wave_tmp.size(); i++) expc_wave.push_front(expc_wave.pop_back()>>scale_factor);
		@(posedge ps_clk);
		while (scale_factor_in != scale_factor_out) @(posedge ps_clk); 
		check_pwl_wave(debug,1);
		expc_wave = expc_wave_tmp;
		scale_factor_in <= 0; 
		while (scale_factor_in != scale_factor_out) @(posedge ps_clk); 
	endtask

	task automatic burst_size_check(inout sim_util_pkg::debug debug, int bs, int test_part);
		int batch_cntr;
		halt_dac();
		dac_bs_in <= bs;
		@(posedge ps_clk);
		while (dac_bs_in != dac_bs_out) @(posedge ps_clk); 
		notify_dac(`RUN_PWL_ID);
		@(posedge dac_clk);
		while (~valid_dac_batch) @(posedge dac_clk);
		while (valid_dac_batch) begin
			batch_cntr++;
			@(posedge dac_clk);
		end 
		debug.disp_test_part(test_part, batch_cntr == halt_counter && halt_counter == bs ,$sformatf("Expected to see %0d batches. TB counted %0d and dac_intf counted %0d",bs, batch_cntr, halt_counter));
	endtask

endmodule 

`default_nettype wire

