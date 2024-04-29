`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module sample_generator #(parameter CMD_WIDTH, parameter RESP_WIDTH, parameter SAMPLE_WIDTH, parameter BATCH_WIDTH, parameter DMA_DATA_WIDTH,
						  parameter DENSE_BRAM_DEPTH, parameter SPARSE_BRAM_DEPTH)
						 (input wire clk, rst_in,
					  	  input wire[BATCH_WIDTH+CMD_WIDTH-1:0] ps_cmd, 
					  	  input wire valid_cmd,
					  	  input wire dac0_rdy,
					  	  output logic[RESP_WIDTH-1:0] resp, 
					  	  output logic resp_valid,
					  	  output logic[BATCH_WIDTH-1:0] dac_batch,
					  	  output logic valid_dac_batch,
					  	  Axis_IF pwl_dma_if);
	localparam BATCH_SIZE = BATCH_WIDTH/SAMPLE_WIDTH;	
						 	
	logic halt, rst; 
	logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] rand_samples,trig_out,pwl_batch_out,rand_seed;
	logic set_seeds,run_shift_regs,run_trig_wav,run_pwl;
	logic pwl_rdy, valid_pwl_batch;
	logic active_out;
	logic[1:0] pwl_rdy_edge;

	// For the random DAC Sampler
	generate
		for (genvar i = 0; i < BATCH_SIZE; i++) begin: lfsr_machines
			LFSR #(.DATA_WIDTH(SAMPLE_WIDTH)) 
			lfsr(.clk(clk), .rst(rst || set_seeds || halt),
				 .seed(rand_seed[i]),
				 .run(run_shift_regs && dac0_rdy),
				 .sample_out(rand_samples[i]));
		end
	endgenerate
	// For the DAC Triangle Wave Generator 
	trig_wave_gen #(.SAMPLE_WIDTH (SAMPLE_WIDTH), .BATCH_WIDTH (BATCH_WIDTH))
  	twg(.clk(clk), .rst(rst || halt),
      .run(run_trig_wav && dac0_rdy),
      .batch_out_comb(trig_out));
	// For PWL
	pwl_generator #(.DMA_DATA_WIDTH(DMA_DATA_WIDTH), .SAMPLE_WIDTH(SAMPLE_WIDTH), .BATCH_SIZE(BATCH_SIZE), .SPARSE_BRAM_DEPTH(SPARSE_BRAM_DEPTH), .DENSE_BRAM_DEPTH(DENSE_BRAM_DEPTH))
	pwl_gen(.clk(clk), .rst(rst),
	        .halt(halt),
	        .run(run_pwl && dac0_rdy),
	        .rdy_to_run(pwl_rdy),
	        .batch_out(pwl_batch_out),
	        .valid_batch_out(valid_pwl_batch),
	        .dma(pwl_dma_if.stream_in));
	edetect	pwl_rdy_ed(.clk(clk), .rst(rst),
	                   .val(pwl_rdy),
	                   .comb_posedge_out(pwl_rdy_edge)); 

	always_comb begin
		//cmd: [sample_seed(16),rst_cmd(1),halt_cmd(1),run_shift_regs(1),run_trig_wave(1),run_pwl(1)]
		rst = rst_in || (valid_cmd && ps_cmd[4]);
		resp = {0,pwl_rdy};
		resp_valid = pwl_rdy_edge != 0; 
		halt = (valid_cmd && ps_cmd[3]);
		active_out = (run_shift_regs || run_trig_wav || run_pwl);
		if (active_out) begin
			if (run_shift_regs) {dac_batch,valid_dac_batch} = {rand_samples,dac0_rdy};
			else if (run_trig_wav) {dac_batch,valid_dac_batch} = {trig_out,dac0_rdy};
			else if (run_pwl) {dac_batch,valid_dac_batch} = {pwl_batch_out,valid_pwl_batch};
		end else {dac_batch,valid_dac_batch} = 0;
	end 

	always_ff @(posedge clk) begin
		if (rst || halt) begin
			{rand_seed,run_shift_regs,run_trig_wav,run_pwl}  <= 0; 
		end else begin
			if (set_seeds) set_seeds <= 0; 
			if (valid_cmd) begin
				{run_shift_regs,run_trig_wav,run_pwl} <= ps_cmd[0+:CMD_WIDTH]; 
				if (ps_cmd[2]) begin
					rand_seed <= ps_cmd[CMD_WIDTH+:BATCH_WIDTH]; 
					set_seeds <= 1; 	
				end
			end
		end
	end

endmodule 



`default_nettype wire