`timescale 1ns / 1ps
`default_nettype none

import daq_params_pkg::INTERPOLATER_DELAY;
module pwl_generator #(parameter DMA_DATA_WIDTH, SAMPLE_WIDTH, BATCH_SIZE, SPARSE_BRAM_DEPTH, DENSE_BRAM_DEPTH, PWL_PERIOD_WIDTH) 
			 		  (input wire clk,rst,
			 		   input wire halt, 
			 		   input wire run, 
			 		   output logic pwl_rdy,
			 		   output logic[PWL_PERIOD_WIDTH-1:0] pwl_wave_period,
			 		   output logic valid_pwl_wave_period, 
			 		   output logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] batch_out,
			 		   output logic valid_batch_out,
			 		   Axis_IF.stream_in dma);
	localparam BATCH_WIDTH = BATCH_SIZE*SAMPLE_WIDTH;
	localparam BRAM_DELAY = 3; 

	logic[SAMPLE_WIDTH-1:0] curr_dma_x,curr_dma_dt,x,x_reg_whole, dt,dt_reg, curr_dma_slope_whole; 
	logic[(2*SAMPLE_WIDTH)-1:0] curr_dma_slope,slope,slope_reg,intrp_slope,x_reg,scaled_x,intrp_x;  
	logic curr_dma_sb, first_sb;
	logic[1:0] nxt_dma_sb;
	logic curr_dma_valid, nxt_dma_valid; 
	logic curr_bram, nxt_bram, nxt_bram_reg; 
	logic[$clog2(2*DENSE_BRAM_DEPTH)-1:0] regions_stored, regions_sent;
	logic[$clog2(SPARSE_BRAM_DEPTH)-1:0] sbram_addr,sbram_gen_addr; 
	logic[DMA_DATA_WIDTH:0] sparse_line_in,sparse_line_out;
	logic sbram_we,sbram_en;
	logic sbram_next;
	logic valid_sparse_line, sbram_write_rdy;
	logic[$clog2(DENSE_BRAM_DEPTH)-1:0] dbram_addr, dbram_gen_addr; 
	logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] dense_batch_in;
	logic[BATCH_SIZE:0][SAMPLE_WIDTH-1:0] dense_line_in;
	logic dense_nxt_bram_bit;
	logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] intrp_batch;
	logic push_dense_cmd_now, save_sparse_cmd_now;
	logic[BATCH_WIDTH:0] dense_batch_out;
	logic brams_writes_ready, brams_valid;
	logic dbram_we,dbram_en;
	logic dbram_next;
	logic gen_mode, clr_brams;
	logic[PWL_PERIOD_WIDTH-1:0] batch_counter; 
	logic valid_dense_batch, dbram_write_rdy;
	logic[$clog2(BATCH_SIZE)-1:0] batch_ptr; 
	logic[INTERPOLATER_DELAY-1:0][SAMPLE_WIDTH+1:0] intrp_pipe; 
	logic valid_intrp_out,nxt_valid_intrp_out;
	logic[SAMPLE_WIDTH-1:0] intrp_out_dt;
	logic intrp_out_nxt_sb;
	logic[$clog2(INTERPOLATER_DELAY):0] intrp_count; 
	logic[INTERPOLATER_DELAY-1:0][BATCH_WIDTH-1:0] dbatch_pipe;
	logic[INTERPOLATER_DELAY-1:0][2:0] which_bram_pipe;
	logic[BATCH_WIDTH-1:0] dbatch_out;
	logic which_bram, last_batch; 
	logic[1:0][DMA_DATA_WIDTH+1:0] dma_pipe;
	logic curr_is_last, done;	               										             //5              6
	enum logic[3:0] {IDLE,DENSE_INTRP_WAIT,STORE_DENSE_WAVE,STORE_SPARSE_WAVE,SETUP_GEN_MODE,SEND_DENSE_WAVE,SEND_SPARSE_WAVE,HOLD_SPARSE_CMD,HALT} pwlState;

	bram_interface #(.DATA_WIDTH(DMA_DATA_WIDTH+1), .BRAM_DEPTH(SPARSE_BRAM_DEPTH), .BRAM_DELAY(BRAM_DELAY))
	sparse_bramint(.clk(clk),.rst(rst),
	               .addr(sbram_addr), .line_in(sparse_line_in),
	               .we(sbram_we), .en(sbram_en),
	               .generator_mode(gen_mode), .clr_bram(clr_brams),
	               .next(sbram_next),
	               .line_out(sparse_line_out), .valid_line_out(valid_sparse_line),
	               .generator_addr(sbram_gen_addr),
	               .write_rdy(sbram_write_rdy));


	bram_interface #(.DATA_WIDTH(BATCH_WIDTH+1), .BRAM_DEPTH(DENSE_BRAM_DEPTH), .BRAM_DELAY(BRAM_DELAY))
	dense_bramint(.clk(clk), .rst(rst),
	               .addr(dbram_addr), .line_in(dense_line_in),
	               .we(dbram_we), .en(dbram_en),
	               .generator_mode(gen_mode), .clr_bram(clr_brams),
	               .next(dbram_next),
	               .line_out(dense_batch_out), .valid_line_out(valid_dense_batch),
	               .generator_addr(dbram_gen_addr),
	               .write_rdy(dbram_write_rdy));

	interpolater #(.SAMPLE_WIDTH(SAMPLE_WIDTH), .BATCH_SIZE(BATCH_SIZE)) 
				interpolater(.clk(clk),
                   		     .x(intrp_x),.slope(intrp_slope),
                   		     .intrp_batch(intrp_batch));
	always_comb begin
		brams_writes_ready = sbram_write_rdy && dbram_write_rdy;
		brams_valid = (dense_bramint.lines_stored == 0 || valid_dense_batch) && (sparse_bramint.lines_stored == 0 || valid_sparse_line);		

		{curr_is_last, curr_dma_valid, curr_dma_x, curr_dma_slope, curr_dma_dt[0+:SAMPLE_WIDTH-1],curr_dma_sb} = dma_pipe[1];
		curr_dma_slope_whole = curr_dma_slope[SAMPLE_WIDTH+:SAMPLE_WIDTH];
		curr_dma_dt[SAMPLE_WIDTH-1] = 0; 
		nxt_dma_valid = dma_pipe[0][DMA_DATA_WIDTH]; 
		nxt_dma_sb = (nxt_dma_valid)? dma_pipe[0][0] : 3;
		{x,slope,dt} = sparse_line_out[DMA_DATA_WIDTH:1]; 
		if (pwlState == HOLD_SPARSE_CMD) nxt_bram = nxt_bram_reg;
		else nxt_bram = (curr_bram)? sparse_line_out[0] : dense_batch_out[BATCH_WIDTH]; 

		if (pwlState == IDLE) begin
			if (run) dma.ready = 0;
			else dma.ready = brams_writes_ready;
		end else 
		if (pwlState == STORE_SPARSE_WAVE) dma.ready = 1;  
		else if (pwlState == DENSE_INTRP_WAIT || pwlState == STORE_DENSE_WAVE) begin
			if (curr_dma_valid && curr_dma_sb && nxt_dma_valid && intrp_count != 0) dma.ready = 0;
			else dma.ready = 1; 
		end else if (pwlState >= SETUP_GEN_MODE) dma.ready = 0; 

		
		if (pwlState < SETUP_GEN_MODE) begin
			intrp_x = curr_dma_x<<SAMPLE_WIDTH;
			intrp_slope = curr_dma_slope;
		end else begin
			intrp_x = (pwlState == HOLD_SPARSE_CMD)? x_reg : x<<SAMPLE_WIDTH;
			intrp_slope = (pwlState == HOLD_SPARSE_CMD)? slope_reg : slope;
		end

		{valid_intrp_out,intrp_out_dt,intrp_out_nxt_sb} = intrp_pipe[INTERPOLATER_DELAY-1];
		nxt_valid_intrp_out = intrp_pipe[INTERPOLATER_DELAY-2][SAMPLE_WIDTH+1];
		{valid_batch_out,which_bram,last_batch} = which_bram_pipe[INTERPOLATER_DELAY-1];
		dbatch_out = dbatch_pipe[INTERPOLATER_DELAY-1];
		if (valid_batch_out) batch_out = (which_bram)? intrp_batch : dbatch_out; 
		else batch_out = 0;

		push_dense_cmd_now = curr_dma_valid && (nxt_dma_valid || curr_is_last) && ~curr_dma_sb && dma.ready;
		save_sparse_cmd_now = curr_dma_valid && (nxt_dma_valid || curr_is_last) && curr_dma_sb && dma.ready; 
		dense_line_in = {dense_nxt_bram_bit,dense_batch_in};

		x_reg_whole = x_reg[SAMPLE_WIDTH+:SAMPLE_WIDTH];
		scaled_x = x << SAMPLE_WIDTH; 

		clr_brams = (pwlState == IDLE && dma.valid) && (sparse_bramint.lines_stored != 0 || dense_bramint.lines_stored != 0);
	end

	always_ff @(posedge clk) begin
		intrp_pipe[INTERPOLATER_DELAY-1:1] <= intrp_pipe[INTERPOLATER_DELAY-2:0];
		which_bram_pipe[INTERPOLATER_DELAY-1:1] <= which_bram_pipe[INTERPOLATER_DELAY-2:0];
		dbatch_pipe[INTERPOLATER_DELAY-1:1] <= dbatch_pipe[INTERPOLATER_DELAY-2:0];

		if (rst) begin
			{sbram_addr, dbram_addr, regions_stored, regions_sent} <= '0; 
			{sbram_next, dbram_next} <= '0;
			{sparse_line_in, dense_batch_in, dense_nxt_bram_bit, batch_ptr} <= '0;
			{dbram_we, dbram_en} <= '0; 
			{sbram_we, sbram_en} <= '0;  
			{first_sb,curr_bram} <= '0; 
			{which_bram_pipe[0],dbatch_pipe[0],intrp_pipe[0],intrp_count} <= '0; 
			{x_reg,slope_reg,dt_reg,nxt_bram_reg,batch_counter,pwl_wave_period,valid_pwl_wave_period} <= '0;
			{gen_mode, pwl_rdy} <= 1;
			{dma_pipe,done} <= '0; 
			pwlState <= IDLE; 
		end else begin
			if (pwlState == IDLE && curr_dma_valid) regions_stored <= 0;
			else if (dbram_we || sbram_we) regions_stored <= regions_stored + 1;

			if (~valid_pwl_wave_period) begin 
				if (last_batch) begin 
					pwl_wave_period <= batch_counter + 1;
					valid_pwl_wave_period <= 1; 
					batch_counter <= 0;
				end 
				else if (valid_batch_out) batch_counter <= batch_counter + 1;
			end else if (pwlState == IDLE && dma.valid && dma.ready) {pwl_wave_period,valid_pwl_wave_period} <= '0; 

			if (dma.ready) begin
				if (dma.valid) begin
					//Perhaps we can always just march the pipeline on when dma is valid?
					if (~curr_dma_valid) dma_pipe[1] <= {dma.last,dma.valid,dma.data}; 
					if (curr_dma_valid && ~nxt_dma_valid) dma_pipe[0] <= {dma.last,dma.valid,dma.data};
					if (curr_dma_valid && nxt_dma_valid) dma_pipe <= {dma_pipe[0], {dma.last,dma.valid,dma.data}};
				end else begin
					if (curr_dma_valid && ~nxt_dma_valid && curr_is_last) begin
						if (~curr_dma_sb) dma_pipe[1] <= 0;	
						else if (intrp_count == 0) dma_pipe[1] <= 0;
					end 
					if (curr_dma_valid && nxt_dma_valid) dma_pipe <= {dma_pipe[0], {(DMA_DATA_WIDTH+2){1'b0}}};
				end
			end

			if (valid_intrp_out ^ push_dense_cmd_now) begin
				if (valid_intrp_out) intrp_count <= intrp_count - 1; 
				if (push_dense_cmd_now) intrp_count <= intrp_count + 1; 
			end
			intrp_pipe[0] <= (push_dense_cmd_now)? {1'b1,curr_dma_dt,nxt_dma_sb[0]} : 0;

			if (pwlState == HALT) done <= 0; 
			else if (curr_is_last) done <= 1;

			case(pwlState)
				IDLE: begin
					if (run) begin
						pwlState <= SETUP_GEN_MODE;
						pwl_rdy <= 0;
					end else begin
						if (dma.valid) gen_mode <= 0;
						if (brams_writes_ready) begin 
							if (curr_dma_valid) begin
								{sbram_addr, dbram_addr} <= 0;
								first_sb <= curr_dma_sb; 
								pwl_rdy <= 0;
								if (save_sparse_cmd_now) begin 
									{sbram_we, sbram_en} <= 3;
									sparse_line_in <= {curr_dma_x,curr_dma_slope,curr_dma_dt,nxt_dma_sb[0]}; 
									pwlState <= STORE_SPARSE_WAVE;
								end else
								if (push_dense_cmd_now) pwlState <= DENSE_INTRP_WAIT;

							end 
						end  
					end 
				end

				DENSE_INTRP_WAIT: begin 
					if (nxt_valid_intrp_out) begin 
						batch_ptr <= 0;
						pwlState <= STORE_DENSE_WAVE;
					end 
				end 

				STORE_DENSE_WAVE: begin
					if (dbram_we) dbram_addr <= (dbram_addr == DENSE_BRAM_DEPTH-1)? 0 : dbram_addr + 1; 
					if (valid_intrp_out) begin
						for (int i = 0; i < BATCH_SIZE; i++) begin
							if ((batch_ptr+i) < BATCH_SIZE) dense_batch_in[batch_ptr+i] <= intrp_batch[i];
						end
						if (batch_ptr + intrp_out_dt == BATCH_SIZE) begin
							{dbram_we, dbram_en} <= 3;
							dense_nxt_bram_bit <= intrp_out_nxt_sb;
							batch_ptr <= 0; 
						end else begin
							{dbram_we, dbram_en} <= 0;
							batch_ptr <=  batch_ptr + intrp_out_dt;
						end
					end else begin 
						{dbram_we, dbram_en} <= 0;
						if (intrp_count == 0) begin 
							if (done && ~curr_dma_valid) pwlState <= HALT;
							else if (save_sparse_cmd_now) begin 
								{sbram_we, sbram_en} <= 3;
								sparse_line_in <= {curr_dma_x,curr_dma_slope,curr_dma_dt,nxt_dma_sb[0]};
								pwlState <= STORE_SPARSE_WAVE;
							end 
						end 
					end
				end

				STORE_SPARSE_WAVE: begin
					if (sbram_we) sbram_addr <= (sbram_addr == SPARSE_BRAM_DEPTH-1)? 0 : sbram_addr + 1;
					if (done && ~curr_dma_valid) pwlState <= HALT;
					else if (push_dense_cmd_now) pwlState <= DENSE_INTRP_WAIT;
					if (save_sparse_cmd_now) begin						
						sparse_line_in <= {curr_dma_x,curr_dma_slope,curr_dma_dt,nxt_dma_sb[0]};
						{sbram_we, sbram_en} <= 3;
					end else {sbram_we, sbram_en} <= 0; 
				end

				SETUP_GEN_MODE: begin
					curr_bram <= first_sb;  
					{dbram_en,sbram_en,dbram_we,sbram_we} <= 0;
					{dbram_addr, sbram_addr} <= 0; 					
					regions_sent <= 0; 
					gen_mode <= 1; 
					if (brams_valid) begin
						if (first_sb) begin 
							sbram_next <= 1; 
							pwlState <= SEND_SPARSE_WAVE;
						end else begin
							dbram_next <= 1; 
							pwlState <= SEND_DENSE_WAVE; 
						end
					end else {dbram_next, sbram_next} <= 0;
				end 

				SEND_DENSE_WAVE: begin
					if (halt) begin
						gen_mode <= 0;
						pwlState <= HALT;
					end else begin
						which_bram_pipe[0] <= (regions_sent == regions_stored-1)? {1'b1,1'b0,1'b1} : {1'b1,1'b0,1'b0};
						dbatch_pipe[0] <= dense_batch_out[0+:BATCH_WIDTH];
						if (regions_sent == regions_stored-1) begin
							regions_sent <= 0;
							if (first_sb) begin
								curr_bram <= 1; 
								{dbram_next, sbram_next} <= 1; 
								pwlState <= SEND_SPARSE_WAVE;
							end else {sbram_next,dbram_next} <= 1; 
						end else begin
							regions_sent <= regions_sent + 1; 
							if (nxt_bram) begin
								curr_bram <= 1; 
								{dbram_next,sbram_next} <= 1; 
								pwlState <= SEND_SPARSE_WAVE; 
							end 
						end 
					end 
				end 

				SEND_SPARSE_WAVE: begin
					if (halt) begin
						gen_mode <= 0;
						pwlState <= HALT;
					end else begin 
						which_bram_pipe[0] <= (regions_sent == regions_stored-1)? {1'b1,1'b1,1'b1} : {1'b1,1'b1,1'b0}; 
						if (dt == BATCH_SIZE) begin
							if (regions_sent == regions_stored-1) begin
								regions_sent <= 0;
								if (~first_sb) begin
									curr_bram <= 0; 
									{sbram_next,dbram_next} <= 1;  
									pwlState <= SEND_DENSE_WAVE;
								end else {dbram_next, sbram_next} <= 1;
							end else begin
								regions_sent <= regions_sent + 1; 
								if (~nxt_bram) begin
									{sbram_next,dbram_next} <= 1; 
									curr_bram <= 0;
									pwlState <= SEND_DENSE_WAVE; 
								end
							end 
						end else begin
							x_reg <= scaled_x + (slope*BATCH_SIZE);
							slope_reg <= slope;
							dt_reg <= dt - BATCH_SIZE;
							nxt_bram_reg <= nxt_bram; 
							sbram_next <= 0; 
							pwlState <= HOLD_SPARSE_CMD;
						end
					end 
				end 

				HOLD_SPARSE_CMD: begin
					if (halt) begin
						gen_mode <= 0;
						pwlState <= HALT;
					end else begin 
						x_reg <= x_reg + (slope_reg*BATCH_SIZE);
						which_bram_pipe[0] <= (regions_sent == regions_stored-1)? {1'b1,1'b1,1'b1} : {1'b1,1'b1,1'b0}; 
						if (dt_reg == BATCH_SIZE) begin
							if (regions_sent == regions_stored-1) begin
								regions_sent <= 0;
								if (~first_sb) begin
									curr_bram <= 0; 
									{sbram_next,dbram_next} <= 1;  
									pwlState <= SEND_DENSE_WAVE;
								end else begin
									{dbram_next, sbram_next} <= 1;
									pwlState <= SEND_SPARSE_WAVE;
								end
							end else begin
								regions_sent <= regions_sent + 1; 
								if (nxt_bram) begin 
									{dbram_next, sbram_next} <= 1;
									pwlState <= SEND_SPARSE_WAVE;
								end else begin
									{sbram_next,dbram_next} <= 1;
									pwlState <= SEND_DENSE_WAVE;
									curr_bram <= 0; 
								end
							end 
						end else dt_reg <= dt_reg - BATCH_SIZE;
					end 
				end 

				HALT: begin
					pwl_rdy <= 1;				
					{sbram_next, dbram_next} <= '0;
					{sbram_addr, dbram_addr} <= '0;
					{dbram_we, dbram_en, sbram_we, sbram_en} <= '0;
					{which_bram_pipe[0],dbatch_pipe[0]} <= '0; 
					regions_sent <= 0;
					pwlState <= IDLE;
				end 
			endcase 
		end
	end
	// logic[15:0] test0,test1,test2,test3,test4,test5,test6,test7,test8,test9,test10,test11,test12,test13,test14,test15;

	// assign test0 = (gen_mode)? batch_out[0] : intrp_batch[0];
	// assign test1 = (gen_mode)? batch_out[1] : intrp_batch[1];
	// assign test2 = (gen_mode)? batch_out[2] : intrp_batch[2];
	// assign test3 = (gen_mode)? batch_out[3] : intrp_batch[3];
	// assign test4 = (gen_mode)? batch_out[4] : intrp_batch[4];
	// assign test5 = (gen_mode)? batch_out[5] : intrp_batch[5];
	// assign test6 = (gen_mode)? batch_out[6] : intrp_batch[6];
	// assign test7 = (gen_mode)? batch_out[7] : intrp_batch[7];
	// assign test8 = (gen_mode)? batch_out[8] : intrp_batch[8];
	// assign test9 = (gen_mode)? batch_out[9] : intrp_batch[9];
	// assign test10 = (gen_mode)? batch_out[10] : intrp_batch[10];
	// assign test11 = (gen_mode)? batch_out[11] : intrp_batch[11];
	// assign test12 = (gen_mode)? batch_out[12] : intrp_batch[12];
	// assign test13 = (gen_mode)? batch_out[13] : intrp_batch[13];
	// assign test14 = (gen_mode)? batch_out[14] : intrp_batch[14];
	// assign test15 = (gen_mode)? batch_out[15] : intrp_batch[15];
endmodule 

`default_nettype wire
