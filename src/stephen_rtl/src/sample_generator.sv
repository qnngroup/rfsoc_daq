`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module sample_generator #(parameter FULL_CMD_WIDTH, parameter CMD_WIDTH, parameter RESP_WIDTH,  parameter BS_WIDTH, parameter SAMPLE_WIDTH, 
						  parameter BATCH_WIDTH, parameter DMA_DATA_WIDTH, parameter DENSE_BRAM_DEPTH, parameter SPARSE_BRAM_DEPTH)
						 (input wire clk, rst,
					  	  input wire[FULL_CMD_WIDTH-1:0] ps_cmd, 
					  	  input wire valid_ps_cmd,
					  	  input wire dac0_rdy,
					  	  input wire[BS_WIDTH-1:0] dac_bs,
					  	  input wire transfer_rdy, transfer_done,
					  	  output logic[RESP_WIDTH-1:0] dac_cmd, 
					  	  output logic valid_dac_cmd,
					  	  output logic[BATCH_WIDTH-1:0] dac_batch,
					  	  output logic valid_dac_batch,
					  	  Axis_IF pwl_dma_if);
	localparam BATCH_SIZE = BATCH_WIDTH/SAMPLE_WIDTH;
	localparam DAC_STAGES = 5; 	
						 	
	logic halt, ps_halt_cmd; 
	logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] rand_samples,trig_out,pwl_batch_out,rand_seed,dac_batch_in;
	logic valid_dac_batch_in; 
	logic[DAC_STAGES-1:0][BATCH_WIDTH:0] batch_pipe; 
	logic set_seeds,run_shift_regs,run_trig_wav,run_pwl;
	logic pwl_rdy, valid_pwl_batch;
	logic[(2*`WD_DATA_WIDTH)-1:0] pwl_wave_period;
	logic valid_pwl_wave_period; 
	logic active_out;
	logic[RESP_WIDTH-1:0] curr_dac_cmd; 
	logic [BS_WIDTH-1:0] halt_counter; 
	logic unfiltered_valid; 
	enum logic {IDLE, HALT} haltState;



	// For the random DAC Sampler
	generate
		for (genvar i = 0; i < BATCH_SIZE; i++) begin: lfsr_machines
			LFSR #(.DATA_WIDTH(SAMPLE_WIDTH)) 
			lfsr(.clk(clk), .rst(rst || set_seeds || halt),
				 .seed(rand_seed[i]),
				 .run(run_shift_regs && dac0_rdy && ~set_seeds),
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
	        .pwl_rdy(pwl_rdy),
	        .pwl_wave_period(pwl_wave_period),
	        .valid_pwl_wave_period(valid_pwl_wave_period),
	        .batch_out(pwl_batch_out),
	        .valid_batch_out(valid_pwl_batch),
	        .dma(pwl_dma_if.stream_in));

	always_comb begin
		//ps_cmd: [... sample_seed(256),ps_halt_cmd(1),run_shift_regs(1),run_trig_wave(1),run_pwl(1)]
		//dac_cmd: [pwl_wave_period(32), pwl_ready(1)]
		curr_dac_cmd = {pwl_wave_period,pwl_rdy};
		halt = ps_halt_cmd || haltState == HALT;
		active_out = (run_shift_regs || run_trig_wav || run_pwl);
		if (active_out && ~set_seeds) begin
			if (run_shift_regs) {dac_batch_in,valid_dac_batch_in} = {rand_samples,dac0_rdy};
			else if (run_trig_wav) {dac_batch_in,valid_dac_batch_in} = {trig_out,dac0_rdy};
			else if (run_pwl) {dac_batch_in,valid_dac_batch_in} = {pwl_batch_out,valid_pwl_batch};
		end else {dac_batch_in,valid_dac_batch_in} = 0;
		{valid_dac_batch,dac_batch}	= (dac0_rdy && ~halt)? batch_pipe[DAC_STAGES-1] : 0;    
		unfiltered_valid = batch_pipe[DAC_STAGES-1][BATCH_WIDTH];  
	end 

	always_ff @(posedge clk) begin
		if (dac0_rdy) begin 
			batch_pipe[DAC_STAGES-1:1] <= batch_pipe[DAC_STAGES-2:0]; 
			batch_pipe[0] <= {valid_dac_batch_in,dac_batch_in}; 
		end 

		if (rst || halt) begin
			{rand_seed,run_shift_regs,run_trig_wav,run_pwl,set_seeds} <= 0;
			{valid_dac_cmd,dac_cmd,ps_halt_cmd}  <= 0; 
		end else begin
			if (~valid_dac_cmd && transfer_rdy && dac_cmd != curr_dac_cmd) begin
				dac_cmd <= curr_dac_cmd;
				valid_dac_cmd <= 1; 
			end
			if (valid_dac_cmd && transfer_rdy) valid_dac_cmd <= 0; 
			if (set_seeds) set_seeds <= 0; 
			if (valid_ps_cmd) begin
				{ps_halt_cmd,run_shift_regs,run_trig_wav,run_pwl} <= ps_cmd[0+:CMD_WIDTH]; 
				if (ps_cmd[2]) begin
					rand_seed <= ps_cmd[CMD_WIDTH+:BATCH_WIDTH]; 
					set_seeds <= 1; 	
				end
			end
		end
	end

	always_ff @(posedge clk) begin
		if (rst) begin
			halt_counter <= 0; 
			haltState <= IDLE; 
		end else begin
			case(haltState)
				IDLE: begin
					if (ps_halt_cmd) haltState <= HALT;
					else if ((dac_bs != 0) && valid_dac_batch) begin
						if (halt_counter == dac_bs-1) haltState <= HALT;
						halt_counter <= halt_counter + 1;
					end
				end 

				HALT: begin
					if (~unfiltered_valid) begin
						halt_counter <= 0;
						haltState <= IDLE;						
					end
				end 
			endcase 
		end
	end

endmodule 



`default_nettype wire