`timescale 1ns / 1ps
`default_nettype none

module pwl_generator #(parameter DMA_DATA_WIDTH = 32, parameter SAMPLE_WIDTH = 16, parameter BATCH_WIDTH = 1024) 
			 		  (input wire clk,rst,
			 		   input wire halt, 
			 		   input wire run, 
			 		   input wire dac0_rdy,
			 		   output logic[BATCH_WIDTH-1:0] batch_out,
			 		   output logic valid_batch_out,
			 		   Axis_IF.stream_in dma);
	localparam LINE_STAGES = 5; //Describes the maximum clock cycles it will take to populate a full line with (`BATCH_SAMPLES) number of samples. 			 		  
	logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] wave_line_in; 
	logic[$clog2(`PWL_BRAM_DEPTH)-1:0] wave_bram_addr_reg, wave_bram_addr; 
	logic[$clog2(`PWL_BRAM_DEPTH)-1:0] wave_lines_stored = 0; 
	logic wave_bram_en, wave_bram_we; 

	logic [1:0][`SAMPLE_WIDTH-1:0] curr_sample_pair, curr_time_pair; 
	logic[1:0] valid_pipe; 
	logic signed[`SAMPLE_WIDTH-1:0] slope_in; 
	logic [1:0][`SAMPLE_WIDTH-1:0] curr_slope_pair;
	logic [`SAMPLE_WIDTH-1:0] sample_in, time_in;
	logic[`SAMPLE_WIDTH-1:0] tot_samples_to_store, samples_stored, samples_left_to_store; 
	logic[$clog2(`BATCH_SAMPLES):0] sample_in_base_ptr;
	logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] intrp_points;
	logic hold_curr_sample, done; 
	logic done_all_building, data_to_process; 
	logic[BATCH_WIDTH-1:0] batch;
	logic valid_batch;
	logic[LINE_STAGES-1:0][$clog2(`BATCH_SAMPLES):0] wave_linein_limits;
	logic[$clog2(LINE_STAGES):0] curr_limit_index; 
	logic[$clog2(`BATCH_SAMPLES):0] curr_limit;
	enum logic[2:0] {IDLE, BUILD_WAVE, SAVE_LAST, BRAM_READ_WAIT, SEND_WAVE} pwlState;
 	
 	always_comb begin
 		valid_batch_out = (dac0_rdy)? valid_batch : 0; 
 		batch_out = (valid_batch_out)? batch : 0;
 		if (pwlState < BRAM_READ_WAIT) wave_bram_addr = wave_bram_addr_reg; 
 		else begin
 			if (~valid_batch_out && pwlState == SEND_WAVE) wave_bram_addr = (wave_bram_addr_reg == 0)? wave_lines_stored-1 : wave_bram_addr_reg-1;
 			else wave_bram_addr = wave_bram_addr_reg;  
 		end 	
 	end 

	PWL_WAVE_BRAM WAVE_BRAM (.clka(clk),       
			   				 .addra(wave_bram_addr),     
			   				 .dina(wave_line_in),       
			   				 .wea(wave_bram_we),        
			   				 .ena(wave_bram_en),         
			   				 .douta(batch));
    data_splicer #(.DATA_WIDTH(`DMA_DATA_WIDTH), .SPLICE_WIDTH(`SAMPLE_WIDTH))
    slope_splice(.data(dma.data),
                 .i(0),
                 .spliced_data(slope_in));
    data_splicer #(.DATA_WIDTH(`DMA_DATA_WIDTH), .SPLICE_WIDTH(`SAMPLE_WIDTH))
    sample_splice(.data(dma.data),
                  .i(1),
                  .spliced_data(sample_in));
 	data_splicer #(.DATA_WIDTH(`DMA_DATA_WIDTH), .SPLICE_WIDTH(`SAMPLE_WIDTH))
    time_splice(.data(dma.data),
                .i(2),
                .spliced_data(time_in));
    logic[`SAMPLE_WIDTH-1:0] curr_sample, curr_slope, curr_time; 
    assign curr_sample = curr_sample_pair[1];
    assign curr_slope = curr_slope_pair[1];
    assign curr_time = curr_time_pair[1];

    logic[`SAMPLE_WIDTH-1:0] nxt_sample, nxt_slope, nxt_time; 
    assign nxt_sample = curr_sample_pair[0];
    assign nxt_slope = curr_slope_pair[0];
    assign nxt_time = curr_time_pair[0];

	always_comb begin
		for (int i = 1; i <= LINE_STAGES; i++) wave_linein_limits[i-1] = (i < LINE_STAGES)? (`BATCH_SAMPLES/LINE_STAGES)*i : `BATCH_SAMPLES; 
		curr_limit = wave_linein_limits[curr_limit_index]; 
		tot_samples_to_store = (nxt_time-curr_time) + 1; 
		samples_left_to_store = tot_samples_to_store - samples_stored - 1; // Subtracting one here because we don't store the very last value (it'll be stored on the next sample or filled in at the end with the current sample) 
		hold_curr_sample = (sample_in_base_ptr+samples_left_to_store) > curr_limit; 
		done_all_building = done && ~hold_curr_sample; 
		data_to_process = valid_pipe[1] || hold_curr_sample; 
		if (pwlState == IDLE || pwlState == BUILD_WAVE) dma.ready =  ~hold_curr_sample; 
		else dma.ready = 0; 
		for (int i = 0; i < `BATCH_SAMPLES; i++) begin
			if ((i+samples_stored) < tot_samples_to_store) begin
				int is_above = ($signed(curr_sample) + $signed(curr_slope)*$signed(i+samples_stored)) > $signed(nxt_sample); 
				int is_below = ($signed(curr_sample) + $signed(curr_slope)*$signed(i+samples_stored)) < $signed(nxt_sample);
				if ($signed(curr_slope) >= 0) intrp_points[i] = (is_above)? nxt_sample : curr_sample + curr_slope*(i+samples_stored); 
				else intrp_points[i] = (is_below)? nxt_sample : curr_sample + curr_slope*(i+samples_stored); 
			end else intrp_points[i] = -1;
		end
	end

	always_ff @(posedge clk) begin
		if (rst || halt) begin
			if (rst) wave_lines_stored <= 0;  
			{curr_sample_pair, curr_time_pair, curr_slope_pair, valid_pipe, sample_in_base_ptr, samples_stored, done} <= 0; 
			{wave_line_in, wave_bram_addr_reg, wave_bram_we, wave_bram_en} <= 0;
			{valid_batch,curr_limit_index} <= 0; 
			pwlState <= IDLE; 
		end else begin
			valid_pipe <= {valid_pipe[0], dma.valid}; 
			if (dma.valid) begin
				if (~hold_curr_sample) begin
					curr_sample_pair <= {nxt_sample, sample_in}; 
					curr_time_pair <= {nxt_time, time_in}; 
					curr_slope_pair <= {nxt_slope, slope_in}; ; 
				end 
			end else begin 
				if (~data_to_process) {curr_sample_pair, curr_time_pair, curr_slope_pair, sample_in_base_ptr, samples_stored} <= 0; 
			end 

			if (wave_bram_we && wave_bram_en) wave_lines_stored <= wave_lines_stored + 1; 
			case(pwlState)
				IDLE: begin
					if (dma.valid) pwlState <= BUILD_WAVE; 
					else if (run) begin 
						wave_bram_en <= 1; 
						pwlState <= BRAM_READ_WAIT;  
					end 
				end 

				BUILD_WAVE: begin
					if (dma.done) done <= 1; 
					if (data_to_process || done_all_building) begin
						for (int i = 0; i < `BATCH_SAMPLES; i++) begin 
							if (done_all_building) begin
								if ((i+sample_in_base_ptr) < `BATCH_SAMPLES) begin
									if (i < samples_left_to_store) wave_line_in[i+sample_in_base_ptr] <= intrp_points[i];
									else wave_line_in[i+sample_in_base_ptr] <= nxt_sample; 
								end 
							end else begin 
								if ((i+sample_in_base_ptr) < curr_limit) begin
									if (i < samples_left_to_store) wave_line_in[i+sample_in_base_ptr] <= intrp_points[i];
								end 
							end 
						end 

						if (sample_in_base_ptr+samples_left_to_store < curr_limit) begin
							sample_in_base_ptr <= sample_in_base_ptr+samples_left_to_store;
							samples_stored <= 0; // As in, on the next clock cycle, 0 samples of the next interpolation was stored 
							if (wave_bram_we) wave_bram_addr_reg <= (wave_bram_addr_reg < `PWL_BRAM_DEPTH-1)? wave_bram_addr_reg + 1 : 0;
							{wave_bram_en, wave_bram_we} <= (done_all_building)? 3 : 0;
						end else begin 
							if (curr_limit == `BATCH_SAMPLES) begin
								curr_limit_index <= 0;
								sample_in_base_ptr <= 0; 
								if (wave_bram_we) wave_bram_addr_reg <= (wave_bram_addr_reg < `PWL_BRAM_DEPTH-1)? wave_bram_addr_reg + 1 : 0;
								else {wave_bram_en, wave_bram_we} <= 3;
							end else begin
								if (wave_bram_we) begin
									wave_bram_addr_reg <= (wave_bram_addr_reg < `PWL_BRAM_DEPTH-1)? wave_bram_addr_reg + 1 : 0; 
									{wave_bram_en, wave_bram_we} <= 0;
								end 
								curr_limit_index <= curr_limit_index + 1; 
								sample_in_base_ptr <= curr_limit;
							end							
							samples_stored <= ((sample_in_base_ptr+samples_left_to_store) == curr_limit)? 0 : samples_stored + (curr_limit - sample_in_base_ptr);
						end

						if (done_all_building) begin
							pwlState <= SAVE_LAST; 
							done <= 0; 
						end 
					end 
				end 

				SAVE_LAST: begin
					{wave_bram_we, wave_bram_en} <= 0;
					wave_line_in <= 0; 
					wave_bram_addr_reg <= 0;
					pwlState <= IDLE;
				end 

				BRAM_READ_WAIT: begin 
					if (dac0_rdy) begin
						valid_batch <= 1; 
						wave_bram_addr_reg <= 1; 
						pwlState <= SEND_WAVE; 
					end 
				end 

				SEND_WAVE: begin
					if (dac0_rdy) begin 
						if (~run) begin
							wave_bram_en <= 0;
							valid_batch <= 0; 
							pwlState <= IDLE;
						end else wave_bram_addr_reg <= (wave_bram_addr_reg == (wave_lines_stored-1))? 0 : wave_bram_addr_reg + 1; 
					end 
				end 
			endcase 
		end
	end
endmodule 

`default_nettype wire

/*
Known problem:

1. When producing the wave, if the last batch isn't filled with interpolation points on the current period, instead of filling in the remainder of that batch with samples 
   starting immediately from the next period, the current implementation simply buffers the rest of that batch with the last value in the interpolation. It's much 
   easier to do this and the logic is that even if an entire batch is filled with the same value at the end of a period, that won't translate to much time passing 
   (because a full batch is present for one cyle of the sys clock which is 150Mhz => there would be junk output for 6.6 nano seconds, which is 0.03% of the maximum
   allowed wavelet period of 20 microseconds).

2. The time field needs to be 18 bits, not 16. It needs to be able to represent the maximum possible number for a wave that has a period of 20 microseconds. If the period 
   is this long, => the largest value the time can be is 3000*64 which requires 18 bits to represent. As of now, the longest period this system can support is about 3.5 us. 

3. The way you did it is if you have 13 samples to between two points (time 0 to time 12, say), you won't store the 13th sample. This is because on the next round, you will be 
interpolating THAT 13th sample with i=0 which means we have SAMPLE + (i=0)*slope = SAMPLE, so you end up storing that sample in the correct location. You would store 0 to 11 
(12 samples), then on the next round save that last one. However, this doesn't work if it's the very last sample. Make a new testcase that has a perfect filling of 3 or 4 batches and 
ensure you don't spill over or under. 
*/