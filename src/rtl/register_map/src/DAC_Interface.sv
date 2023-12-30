`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module DAC_Interface (input wire clk,rst,
					  input wire[`MEM_SIZE-1:0] fresh_bits,
					  input wire[`MEM_SIZE-1:0][`WD_DATA_WIDTH-1:0] read_resps,
					  input wire halt,
					  input wire dac0_rdy, 
					  output logic[`BATCH_WIDTH-1:0] dac_batch,
					  output logic valid_dac_batch,
					  output logic[1:0] valid_dac_edge,
					  Axis_IF pwl_dma_if);

	enum logic[1:0] {IDLE,READ_DELAY,BUILD_SEED} dacState;
	logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] trig_out,seed_set, samples_out, pwl_batch_out;  
	logic produce_rand_samples, produce_trig_wave, produce_pwl; 
	logic[`MEM_SIZE-1:0] read_reqs;
	logic set_seeds;
	logic run_shift_regs, run_trig_wav, run_pwl; 
	logic shutdown_twg, shutdown_lfsr, shutdown_pwl; 
	logic pwl_data_incoming, dma_stream_delay; 
	logic valid_pwl_batch; 

	edetect valid_dac_edetect (.clk(clk), .rst(rst),
                               .val(valid_dac_batch),
                               .comb_posedge_out(valid_dac_edge));

	// For the random DAC Sampler
	generate
		for (genvar i = 0; i < `BATCH_SAMPLES; i++) begin: lfsr_machines
			 LFSR #(.DATA_WIDTH(`SAMPLE_WIDTH)) 
		     lfsr(.clk(clk), .rst(rst || set_seeds || shutdown_lfsr),
		          .seed(seed_set[i]),
		          .run(run_shift_regs),
		          .sample_out(samples_out[i]));
		end
	endgenerate

	// For the DAC Triangle Wave Generator 
	trig_wave_gen #(.SAMPLE_WIDTH (`SAMPLE_WIDTH), .BATCH_WIDTH (`BATCH_WIDTH))
  	twg(.clk(clk), .rst(rst || halt || shutdown_twg),
      .run(run_trig_wav),
      .batch_out_comb(trig_out));
	
	// For PWL
	pwl_generator #(.DMA_DATA_WIDTH(`DMA_DATA_WIDTH), .SAMPLE_WIDTH(`SAMPLE_WIDTH), .BATCH_WIDTH(`BATCH_WIDTH))
	pwl_gen(.clk(clk), .rst(rst || pwl_data_incoming), 
			.halt(halt || shutdown_pwl), 
			.run(run_pwl),
			.dac0_rdy(dac0_rdy),
			.batch_out(pwl_batch_out), .valid_batch_out(valid_pwl_batch),
			.dma(pwl_dma_if.stream_in));

	always_comb begin
		if (rst) {dac_batch, valid_dac_batch, run_shift_regs, run_trig_wav, run_pwl} = 0;
		else begin
			case (dacState)
				IDLE: begin
					if (produce_rand_samples) begin 
						valid_dac_batch = (halt)? 0 : dac0_rdy;
						dac_batch = (valid_dac_batch)? samples_out : 0;
						run_shift_regs = (halt)? 0 : valid_dac_batch;
						{run_trig_wav, run_pwl} = 0; 
					end else 
					if (produce_trig_wave) begin
						valid_dac_batch = (halt)? 0 : dac0_rdy;
						dac_batch = (valid_dac_batch)? trig_out : 0; 
						run_trig_wav = (halt)? 0 : valid_dac_batch;
						{run_shift_regs, run_pwl} = 0; 
					end else
					if (produce_pwl) begin
						valid_dac_batch = (halt)? 0 : valid_pwl_batch;
						dac_batch = (valid_dac_batch)? pwl_batch_out : 0; 
						run_pwl = (halt)? 0 : 1;
						{run_shift_regs, run_trig_wav} = 0; 
					end
					else {dac_batch, valid_dac_batch, run_shift_regs, run_trig_wav, run_pwl} = 0; 
				end  
				default: {dac_batch, valid_dac_batch, run_shift_regs, run_trig_wav, run_pwl} = 0; 
			endcase 
		end
	end

	always_ff @(posedge clk) begin
		if (rst || halt) begin 
			{seed_set,produce_rand_samples,produce_trig_wave,produce_pwl,read_reqs,set_seeds} <= 0;
			{shutdown_twg, shutdown_lfsr, shutdown_pwl, pwl_data_incoming, dma_stream_delay} <= 0;
			dacState <= IDLE;
		end else begin
			if (shutdown_twg) shutdown_twg <= 0; 
			if (shutdown_lfsr) shutdown_lfsr <= 0; 
			if (shutdown_pwl) shutdown_pwl <= 0; 
			if (pwl_data_incoming) pwl_data_incoming <= 0; 
			case (dacState) 
				IDLE: begin
					if (fresh_bits[`PS_SEED_VALID_ID]) begin
						read_reqs[`PS_SEED_VALID_ID] <= 1;
						for (int i = 0; i < `BATCH_SAMPLES; i++) read_reqs[`PS_SEED_BASE_ID+i] <= 1;
						{shutdown_twg, shutdown_pwl} <= 3; 
						{produce_trig_wave, produce_pwl, produce_rand_samples} <= 1;
						dacState <= READ_DELAY; 
					end else 
					if (fresh_bits[`TRIG_WAVE_ID]) begin
						read_reqs[`TRIG_WAVE_ID] <= 1; 
						{shutdown_lfsr, shutdown_pwl} <= 3; 
						{produce_rand_samples, produce_pwl, produce_trig_wave} <= 1;
						dacState <= READ_DELAY;
					end else 
					if (fresh_bits[`PWL_PREP_ID]) begin
						read_reqs[`PWL_PREP_ID] <= 1; 
						pwl_data_incoming <= 1; 
						dma_stream_delay <= 1;
						{shutdown_lfsr, shutdown_twg} <= 3; 
						{produce_rand_samples, produce_trig_wave, produce_pwl} <= 0;
						dacState <= READ_DELAY;
					end
					if (fresh_bits[`RUN_PWL_ID]) begin
						read_reqs[`RUN_PWL_ID] <= 1; 
						{shutdown_lfsr, shutdown_twg} <= 3; 
						{produce_rand_samples, produce_trig_wave, produce_pwl} <= 1;
						dacState <= READ_DELAY;
					end
				end 

				READ_DELAY: begin 
					if (produce_rand_samples) begin 
						read_reqs[`PS_SEED_VALID_ID] <= 0;
						for (int i = 0; i < `BATCH_SAMPLES; i++) read_reqs[`PS_SEED_BASE_ID+i] <= 0;
						dacState <= BUILD_SEED;
					end else 
					if (produce_trig_wave) begin
						read_reqs[`TRIG_WAVE_ID] <= 0; 
						dacState <= IDLE;
					end 
					if (dma_stream_delay) begin
						read_reqs[`PWL_PREP_ID] <= 0; 
						if (pwl_dma_if.valid) begin 
							dma_stream_delay <= 0; 
							produce_pwl <= 1; 
							dacState <= IDLE;
						end 
					end
					if (produce_pwl) begin
						read_reqs[`RUN_PWL_ID] <= 0; 
						dacState <= IDLE;
					end
				end 

				BUILD_SEED: begin
					if (~set_seeds) begin
						for (int i = 0; i < `BATCH_SAMPLES; i++) seed_set[i] <= read_resps[`PS_SEED_BASE_ID+i];
						set_seeds <= 1; 
					end else begin
						dacState <= IDLE;
						set_seeds <= 0; 
					end
				end 
			endcase 
		end
	end	
endmodule 



`default_nettype wire