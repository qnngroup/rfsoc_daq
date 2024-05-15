`timescale 1ns / 1ps
`default_nettype none

module pwl_generator #(parameter DMA_DATA_WIDTH, parameter SAMPLE_WIDTH, parameter BATCH_SIZE, parameter SPARSE_BRAM_DEPTH, parameter DENSE_BRAM_DEPTH) 
			 		  (input wire clk,rst,
			 		   input wire halt, 
			 		   input wire run, 
			 		   input wire dac0_rdy,
			 		   output logic rdy_to_run,
			 		   output logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] batch_out,
			 		   output logic valid_batch_out,
			 		   Axis_IF.stream_in dma);
	localparam BATCH_WIDTH = BATCH_SIZE*SAMPLE_WIDTH;
	localparam INTERPOLATER_DELAY = 3;
	localparam BRAM_DELAY = 3; 

	logic[SAMPLE_WIDTH-1:0] curr_dma_x,curr_dma_slope,curr_dma_dt,x,x_reg,slope,slope_reg, dt,dt_reg, intrp_x,intrp_slope;  
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
	logic gen_mode, rst_gen_mode;
	logic valid_dense_batch, dbram_write_rdy;
	logic[$clog2(BATCH_WIDTH)-1:0] batch_ptr; 
	logic[INTERPOLATER_DELAY-1:0][SAMPLE_WIDTH+1:0] intrp_pipe; 
	logic valid_intrp_out,nxt_valid_intrp_out;
	logic[SAMPLE_WIDTH-1:0] intrp_out_dt;
	logic intrp_out_nxt_sb;
	logic[$clog2(INTERPOLATER_DELAY):0] intrp_count; 
	logic[INTERPOLATER_DELAY-1:0][BATCH_WIDTH-1:0] dbatch_pipe;
	logic[INTERPOLATER_DELAY-1:0][1:0] which_bram_pipe; 
	logic[BATCH_WIDTH-1:0] dbatch_out;
	logic which_bram; 
	logic[1:0][DMA_DATA_WIDTH+1:0] dma_pipe;
	logic curr_is_last, done;	               												 //    5                  6
	enum logic[3:0] {IDLE,DENSE_INTRP_WAIT,STORE_DENSE_WAVE,STORE_SPARSE_WAVE,SETUP_GEN_MODE,SEND_DENSE_WAVE,SEND_SPARSE_WAVE,HOLD_SPARSE_CMD,HALT} pwlState;

	bram_interface #(.DATA_WIDTH(DMA_DATA_WIDTH+1), .BRAM_DEPTH(SPARSE_BRAM_DEPTH), .BRAM_DELAY(BRAM_DELAY))
	sparse_bramint(.clk(clk),.rst(rst),
	               .addr(sbram_addr), .line_in(sparse_line_in),
	               .we(sbram_we), .en(sbram_en),
	               .generator_mode(gen_mode), .rst_gen_mode(rst_gen_mode),
	               .next(sbram_next),
	               .line_out(sparse_line_out), .valid_line_out(valid_sparse_line),
	               .generator_addr(sbram_gen_addr),
	               .write_rdy(sbram_write_rdy));


	bram_interface #(.DATA_WIDTH(BATCH_WIDTH+1), .BRAM_DEPTH(DENSE_BRAM_DEPTH), .BRAM_DELAY(BRAM_DELAY))
	dense_bramint(.clk(clk), .rst(rst),
	               .addr(dbram_addr), .line_in(dense_line_in),
	               .we(dbram_we), .en(dbram_en),
	               .generator_mode(gen_mode), .rst_gen_mode(rst_gen_mode),
	               .next(dbram_next),
	               .line_out(dense_batch_out), .valid_line_out(valid_dense_batch),
	               .generator_addr(dbram_gen_addr),
	               .write_rdy(dbram_write_rdy));

	interpolater #(.SAMPLE_WIDTH(SAMPLE_WIDTH), .BATCH_SIZE(BATCH_SIZE)) 
				interpolater(.clk(clk),
                   		     .x(intrp_x),.slope(intrp_slope),
                   		     .intrp_batch(intrp_batch));

	always_comb begin
		{curr_is_last, curr_dma_valid, curr_dma_x, curr_dma_slope, curr_dma_dt[0+:SAMPLE_WIDTH-1],curr_dma_sb} = dma_pipe[1];
		curr_dma_dt[SAMPLE_WIDTH-1] = 0; 
		nxt_dma_valid = dma_pipe[0][DMA_DATA_WIDTH]; 
		nxt_dma_sb = (nxt_dma_valid)? dma_pipe[0][0] : 3;
		{x,slope,dt} = sparse_line_out[DMA_DATA_WIDTH:1]; 
		if (pwlState == HOLD_SPARSE_CMD) nxt_bram = nxt_bram_reg;
		else nxt_bram = (curr_bram)? sparse_line_out[0] : dense_batch_out[BATCH_WIDTH]; 
		push_dense_cmd_now = curr_dma_valid && (nxt_dma_valid || curr_is_last) && ~curr_dma_sb;
		save_sparse_cmd_now = curr_dma_valid && (nxt_dma_valid || curr_is_last) && curr_dma_sb && intrp_count == 0 && dma.ready; 
		dense_line_in = {dense_nxt_bram_bit,dense_batch_in};
		
		if (pwlState < SETUP_GEN_MODE) begin
			intrp_x = curr_dma_x;
			intrp_slope = curr_dma_slope;
		end else begin
			intrp_x = (pwlState == HOLD_SPARSE_CMD)? x_reg : x;
			intrp_slope = (pwlState == HOLD_SPARSE_CMD)? slope_reg : slope;
		end

		{valid_intrp_out,intrp_out_dt,intrp_out_nxt_sb} = intrp_pipe[INTERPOLATER_DELAY-1];
		nxt_valid_intrp_out = intrp_pipe[INTERPOLATER_DELAY-2][SAMPLE_WIDTH+1];
		{valid_batch_out,which_bram} = which_bram_pipe[INTERPOLATER_DELAY-1];
		dbatch_out = dbatch_pipe[INTERPOLATER_DELAY-1];
		if (valid_batch_out) batch_out = (which_bram)? intrp_batch : dbatch_out; 
		else batch_out = 0;

		brams_writes_ready = sbram_write_rdy && dbram_write_rdy;
		brams_valid = valid_dense_batch && valid_sparse_line;
	end

	always_ff @(posedge clk) begin
		intrp_pipe[INTERPOLATER_DELAY-1:1] <= intrp_pipe[INTERPOLATER_DELAY-2:0];
		which_bram_pipe[INTERPOLATER_DELAY-1:1] <= which_bram_pipe[INTERPOLATER_DELAY-2:0];
		dbatch_pipe[INTERPOLATER_DELAY-1:1] <= dbatch_pipe[INTERPOLATER_DELAY-2:0];

		if (rst) begin
			{sbram_addr, dbram_addr, regions_stored, regions_sent} <= 0; 
			{sbram_next, dbram_next} <= 0;
			{sparse_line_in, dense_batch_in, dense_nxt_bram_bit, batch_ptr} <= 0;
			{dbram_we, dbram_en} <= 0; 
			{sbram_we, sbram_en} <= 0;  
			{first_sb,curr_bram} <= 0; 
			{which_bram_pipe[0],dbatch_pipe[0],intrp_pipe[0],intrp_count} <= 0; 
			{x_reg,slope_reg,dt_reg,nxt_bram_reg} <= 0;
			{gen_mode, rst_gen_mode, rdy_to_run} <= 0;
			dma.ready <= 1;
			{dma_pipe,done} <= 0; 
			pwlState <= IDLE; 
		end else begin
			if (pwlState == IDLE && curr_dma_valid) regions_stored <= 0;
			else if (dbram_we || sbram_we) regions_stored <= regions_stored + 1;

			if (dma.ready) begin
				if (dma.valid) begin
					//Perhaps we can always just march the pipeline on when dma is valid?
					if (~curr_dma_valid) dma_pipe[1] <= {dma.last,dma.valid,dma.data}; 
					if (curr_dma_valid && ~nxt_dma_valid) dma_pipe[0] <= {dma.last,dma.valid,dma.data};
					if (curr_dma_valid && nxt_dma_valid) dma_pipe <= {dma_pipe[0], {dma.last,dma.valid,dma.data}};
				end else begin
					if (curr_dma_valid && ~nxt_dma_valid && curr_is_last && intrp_count == 0) dma_pipe[1] <= 0;
					if (curr_dma_valid && nxt_dma_valid) dma_pipe <= {dma_pipe[0], {(DMA_DATA_WIDTH+2){1'b0}}};
				end
			end

			if (valid_intrp_out ^ push_dense_cmd_now) begin
				if (valid_intrp_out) intrp_count <= intrp_count - 1; 
				if (push_dense_cmd_now) intrp_count <= intrp_count + 1; 
			end
			intrp_pipe[0] <= (push_dense_cmd_now)? {1'b1,curr_dma_dt,nxt_dma_sb[0]} : 0;

			if (pwlState == IDLE) begin
				if (run) dma.ready <= 0;
				else dma.ready <= brams_writes_ready;
			end else  
			if (pwlState == DENSE_INTRP_WAIT || pwlState == STORE_DENSE_WAVE) begin
				if (~dma.ready) begin
					if (intrp_count == 0) dma.ready <= 1; 						
				end else
				if ((curr_dma_valid && dma.valid && curr_dma_sb)) dma.ready <= 0; 
			end

			if (pwlState == HALT) done <= 0; 
			else if (curr_is_last) done <= 1;

			case(pwlState)
				IDLE: begin
					if (run) begin
						pwlState <= SETUP_GEN_MODE;
						rdy_to_run <= 0;
					end else begin
						if (dma.valid) gen_mode <= 0;
						if (brams_writes_ready) begin 
							if (curr_dma_valid) begin
								{sbram_addr, dbram_addr} <= 0;
								first_sb <= curr_dma_sb; 
								rdy_to_run <= 0;
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
						dense_batch_in[batch_ptr+:BATCH_SIZE] <= intrp_batch;
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
							else if (dma.ready && save_sparse_cmd_now) begin 
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
						rst_gen_mode <= 1;
						pwlState <= HALT;
					end else begin
						which_bram_pipe[0] <= {1'b1,1'b0};
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
						rst_gen_mode <= 1;
						pwlState <= HALT;
					end else begin 
						which_bram_pipe[0] <= {1'b1,1'b1};
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
							x_reg <= x + slope*BATCH_SIZE;
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
						rst_gen_mode <= 1;
						pwlState <= HALT;
					end else begin 
						x_reg <= x_reg + slope_reg*BATCH_SIZE;
						which_bram_pipe[0] <= {1'b1,1'b1};
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
					rst_gen_mode <= 0; 
					rdy_to_run <= 1;
					{sbram_next, dbram_next} <= 0;
					{sbram_addr, dbram_addr} <= 0;
					{dbram_we, dbram_en, sbram_we, sbram_en} <= 0;
					{which_bram_pipe[0],dbatch_pipe[0]} <= 0; 
					pwlState <= IDLE;
				end 
			endcase 
		end
	end

	logic[15:0] test0,test1,test2,test3,test4,test5,test6,test7,test8,test9,test10,test11,test12,test13,test14,test15;

	assign test0 = (gen_mode)? batch_out[0] : dense_line_in[0];
	assign test1 = (gen_mode)? batch_out[1] : dense_line_in[1];
	assign test2 = (gen_mode)? batch_out[2] : dense_line_in[2];
	assign test3 = (gen_mode)? batch_out[3] : dense_line_in[3];
	assign test4 = (gen_mode)? batch_out[4] : dense_line_in[4];
	assign test5 = (gen_mode)? batch_out[5] : dense_line_in[5];
	assign test6 = (gen_mode)? batch_out[6] : dense_line_in[6];
	assign test7 = (gen_mode)? batch_out[7] : dense_line_in[7];
	assign test8 = (gen_mode)? batch_out[8] : dense_line_in[8];
	assign test9 = (gen_mode)? batch_out[9] : dense_line_in[9];
	assign test10 = (gen_mode)? batch_out[10] : dense_line_in[10];
	assign test11 = (gen_mode)? batch_out[11] : dense_line_in[11];
	assign test12 = (gen_mode)? batch_out[12] : dense_line_in[12];
	assign test13 = (gen_mode)? batch_out[13] : dense_line_in[13];
	assign test14 = (gen_mode)? batch_out[14] : dense_line_in[14];
	assign test15 = (gen_mode)? batch_out[15] : dense_line_in[15];
endmodule 

`default_nettype wire
