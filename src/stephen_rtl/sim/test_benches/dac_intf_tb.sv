`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"
// import mem_layout_pkg::flash_signal;
module dac_intf_tb #(parameter MEM_SIZE, parameter DATA_WIDTH, parameter BATCH_SIZE, parameter DMA_DATA_WIDTH)
					   (input wire ps_clk,dac_clk,
					   	input wire dac_intf_rdy,
					   	input wire[BATCH_SIZE-1:0][DATA_WIDTH-1:0] dac_batch,
					  	input wire valid_dac_batch,
					   	output logic ps_rst, dac_rst, 
						output logic[MEM_SIZE-1:0] fresh_bits,
						output logic[MEM_SIZE-1:0][DATA_WIDTH-1:0] read_resps,
						output logic[$clog2(DATA_WIDTH)-1:0] scale_factor_in,
						output logic halt,
						output logic dac0_rdy, 
						Axis_IF dma);
	localparam BATCH_WIDTH = BATCH_SIZE*DATA_WIDTH;					   
	logic ps_clk2, dac_clk2;
	bit halt_osc = 0;
	bit pause_osc = 0; 	
	assign {ps_clk2, dac_clk2} = {ps_clk, dac_clk};


	task automatic init();
		{dma.valid, dma.last, dma.data} <= 0;
		{read_resps, scale_factor_in, fresh_bits, halt} <= 0;
		dac0_rdy <= 1; 
		fork 
			begin flash_signal(ps_rst,ps_clk2); end 
			begin flash_signal(dac_rst, dac_clk2); end 
		join 
		oscillate_dacrdy(halt_osc, pause_osc); 		
	endtask 

	task automatic oscillate_dacrdy(ref bit halt_osc, pause_osc);
		fork 
			begin
				bit[1:0] delay_timer;
				enum bit {OSC,PAUSE} oscState; 
				oscState = OSC; 
				while (~halt_osc) begin
					case(oscState)
						OSC: begin
							delay_timer = $urandom_range(1,3);
							dac0_rdy <= ~dac0_rdy; 
							for (int i = 0; i < delay_timer; i++) @(posedge dac_clk); 
							if (pause_osc) begin
								oscState = PAUSE;
								dac0_rdy <= 1; 
							end 
						end 
						PAUSE: begin
							if (~pause_osc) oscState = OSC; 
							@(posedge dac_clk); 
						end 
					endcase					
				end
				dac0_rdy <= 1;
				@(posedge dac_clk); 
			end
		join_none
	endtask 

	task automatic notify_dac(logic[$clog2(MEM_SIZE)-1:0] id);
		fresh_bits[id] <= 1; 
		@(posedge ps_clk);
		while (~dac_intf_rdy) @(posedge ps_clk);
		fresh_bits[id] <= 0; 		
	endtask 
	
	task automatic send_rand_samples(output logic[BATCH_WIDTH-1:0] first_batch);
		for (int i = `PS_SEED_BASE_ID; i < `PS_SEED_VALID_ID; i++) read_resps[i] <= 16'hBEEF+(i-`PS_SEED_BASE_ID);
		read_resps[`PS_SEED_VALID_ID] <= 1; 
		for (int i = `PS_SEED_BASE_ID; i <= `PS_SEED_VALID_ID; i++) notify_dac(i); 
		while (~valid_dac_batch) @(posedge dac_clk);
		first_batch = dac_batch;
	endtask 

	task automatic send_trig_wave(inout sim_util_pkg::debug debug, input int samples_to_check);	
		int starting_val = 0;
		bit[BATCH_SIZE-1:0][DATA_WIDTH-1:0] expected = 0;			
		notify_dac(`TRIG_WAVE_ID);
		for (int n = 0; n < samples_to_check; n++) begin
			while (~valid_dac_batch) @(posedge dac_clk);
			for (int i = 0; i < BATCH_SIZE; i++) expected[i] = starting_val+i;
			starting_val+=BATCH_SIZE; 
			debug.disp_test_part(n,dac_batch == expected, $sformatf("Error on triangle wave sample #%0d",n));
			@(posedge dac_clk);
		end
	endtask

	task automatic send_pwl_wave();
		bit[1:0] delay_timer;
		localparam BUFF_LEN = 21; 
		logic[BUFF_LEN-1:0][DMA_DATA_WIDTH-1:0] dma_buff;
		dma_buff = {48'd24, 48'd450971500552, 48'd3405909001569, 48'd3440268738576, 48'd3435973836816, 48'd3435973841057, 48'd3435973836828, 48'd3427383967748, 48'd678604899585, 48'd644245159952, 48'd644245094416, 48'd644245097761, 48'd644245094424, 48'd665719865352, 48'd1902670447169, 48'd1937030184976, 48'd1932735283216, 48'd1932735284257, 48'd1932735283228, 48'd1924145414148, 48'd66433}; 
		notify_dac(`RUN_PWL_ID); 
		for (int i = 0; i < BUFF_LEN; i++) begin
			dma.data <= dma_buff[i];
			delay_timer = $urandom_range(1,3);
			for (int j = 0; j < delay_timer; j++) @(posedge dac_clk);
			dma.valid <= 1; 
			if (i == BUFF_LEN-1) dma.last <= 1;			
			@(posedge dac_clk);
			while (~dma.ready) @(posedge dac_clk); 
			{dma.valid,dma.last} <= 0;
		end		
	endtask  

	task automatic check_pwl_wave(inout sim_util_pkg::debug debug, input int periods_to_check);
		logic[3:0][BATCH_SIZE-1:0][DATA_WIDTH-1:0] expected = {{16'd0, 16'd1, 16'd2, 16'd3, 16'd4, 16'd5, 16'd6, 16'd7, 16'd8, 16'd9, 16'd10, 16'd11, 16'd12, 16'd13, 16'd14, 16'd15}, {16'd16, 16'd17, 16'd18, 16'd19, 16'd20, 16'd21, 16'd22, 16'd23, 16'd24, 16'd25, 16'd26, 16'd27, 16'd28, 16'd29, 16'd30, 16'd31}, {16'd32, 16'd33, 16'd34, 16'd35, 16'd36, 16'd34, 16'd32, 16'd30, 16'd28, 16'd26, 16'd24, 16'd22, 16'd20, 16'd18, 16'd17, 16'd16}, {16'd15, 16'd14, 16'd13, 16'd12, 16'd11, 16'd10, 16'd9, 16'd8, 16'd7, 16'd6, 16'd5, 16'd4, 16'd3, 16'd2, 16'd1, 16'd0}};
		while (~(dac_batch == expected[0] && valid_dac_batch)) @(posedge dac_clk); 
		repeat(periods_to_check) begin
			for (int i = 0; i < 4; i++) begin
				while (~valid_dac_batch) @(posedge dac_clk); 
				debug.disp_test_part(i,dac_batch == expected[i], $sformatf("Error on pwl wave sample #%0d",i));
				@(posedge dac_clk);
			end 
		end
  	endtask 

	task automatic halt_dac();
		flash_signal(halt,ps_clk2);
		while (1) begin
			if (dac0_rdy && ~valid_dac_batch) break;
			@(posedge dac_clk);
		end
	endtask 

endmodule 

`default_nettype wire

