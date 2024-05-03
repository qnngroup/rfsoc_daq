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

	logic[SAMPLE_WIDTH-1:0] curr_dma_x,curr_dma_slope,curr_dma_dt,x,x_reg,slope,slope_reg, dt,dt_reg, intrp_x,intrp_slope;  
	logic curr_dma_sb, nxt_dma_sb, first_sb, sb;
	logic curr_dma_valid; 
	logic curr_bram, nxt_bram; 
	logic[$clog2(2*SPARSE_BRAM_DEPTH)-1:0] regions_stored;
	logic[$clog2(SPARSE_BRAM_DEPTH)-1:0] sbram_addr,sbram_gen_addr; 
	logic[DMA_DATA_WIDTH:0] sparse_line_in,sparse_batch_out;
	logic sbram_we,sbram_en;
	logic sbram_next;
	logic valid_sparse_batch, sbram_write_rdy;
	logic[$clog2(DENSE_BRAM_DEPTH)-1:0] dbram_addr, dbram_gen_addr; 
	logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] dense_line_in;
	logic dense_nxt_bram_bit;
	logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] intrp_batch,dense_batch_out_TEST;
	logic[2:0][SAMPLE_WIDTH-1:0] sparse_batch_out_TEST;
	logic[BATCH_WIDTH:0] dense_batch_out;
	logic brams_writes_ready, brams_valid;
	logic dbram_we,dbram_en;
	logic dbram_next;
	logic gen_mode, rst_gen_mode;
	logic valid_dense_batch, dbram_write_rdy;
	logic[$clog2(BATCH_WIDTH)-1:0] batch_ptr; 
	logic[INTERPOLATER_DELAY-1:0][SAMPLE_WIDTH:0] intrp_pipe; 
	logic valid_intrp_out,nxt_valid_intrp_out;
	logic[SAMPLE_WIDTH-1:0] intrp_out_dt;
	logic[INTERPOLATER_DELAY-1:0][BATCH_WIDTH-1:0] dbatch_pipe;
	logic[INTERPOLATER_DELAY-1:0][1:0] which_bram_pipe; 
	logic[BATCH_WIDTH-1:0] dbatch_out;
	logic which_bram; 
	logic[1:0][DMA_DATA_WIDTH:0] dma_pipe;
	enum logic[3:0] {IDLE,DENSE_INTRP_WAIT,STORE_DENSE_WAVE,STORE_SPARSE_WAVE,SETUP_GEN_MODE,SEND_DENSE_WAVE,SEND_SPARSE_WAVE,HOLD_SPARSE_CMD,HALT} pwlState;


	bram_interface #(.DATA_WIDTH(DMA_DATA_WIDTH+1), .BRAM_DEPTH(SPARSE_BRAM_DEPTH), .BRAM_DELAY(3))
	sparse_bramint(.clk(clk),.rst(rst),
	               .addr(sbram_addr), .line_in(sparse_line_in),
	               .we(sbram_we), .en(sbram_en),
	               .generator_mode(gen_mode), .rst_gen_mode(rst_gen_mode),
	               .next(sbram_next),
	               .line_out(sparse_batch_out), .valid_line_out(valid_sparse_batch),
	               .generator_addr(sbram_gen_addr),
	               .write_rdy(sbram_write_rdy));


	bram_interface #(.DATA_WIDTH(BATCH_WIDTH+1), .BRAM_DEPTH(DENSE_BRAM_DEPTH), .BRAM_DELAY(3))
	dense_bramint(.clk(clk), .rst(rst),
	               .addr(dbram_addr), .line_in({dense_nxt_bram_bit,dense_line_in}),
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
		sparse_batch_out_TEST = sparse_batch_out[DMA_DATA_WIDTH:1];
		dense_batch_out_TEST = dense_batch_out[BATCH_WIDTH-1:0];

		{curr_dma_valid, curr_dma_x, curr_dma_slope, curr_dma_dt[0+:SAMPLE_WIDTH-1],curr_dma_sb} = dma_pipe[1];
		curr_dma_dt[SAMPLE_WIDTH-1] = 0; 
		nxt_dma_sb = dma_pipe[0][0]; 
		{x,slope,dt} = sparse_batch_out[DMA_DATA_WIDTH:1]; 
		nxt_bram = (curr_bram)? sparse_batch_out[0] : dense_batch_out[BATCH_WIDTH]; 
		
		if (pwlState < SETUP_GEN_MODE) begin
			intrp_x = curr_dma_x;
			intrp_slope = curr_dma_slope;
		end else begin
			intrp_x = (pwlState == HOLD_SPARSE_CMD)? x_reg : x;
			intrp_slope = (pwlState == HOLD_SPARSE_CMD)? slope_reg : slope;
		end

		{valid_intrp_out,intrp_out_dt} = intrp_pipe[INTERPOLATER_DELAY-1];
		nxt_valid_intrp_out = intrp_pipe[INTERPOLATER_DELAY-2][SAMPLE_WIDTH];
		{valid_batch_out,which_bram} = which_bram_pipe[INTERPOLATER_DELAY-1];
		dbatch_out = dbatch_pipe[INTERPOLATER_DELAY-1];
		if (valid_batch_out) batch_out = (which_bram)? intrp_batch : dbatch_out; 
		else batch_out = 0;

		brams_writes_ready = sbram_write_rdy && dbram_write_rdy;
		brams_valid = valid_dense_batch && valid_sparse_batch;
	end

	always_ff @(posedge clk) begin
		if (dma.ready || ~dma.valid) dma_pipe <= {dma_pipe[0],{dma.valid,dma.data}};
		intrp_pipe[INTERPOLATER_DELAY-1:1] <= intrp_pipe[INTERPOLATER_DELAY-2:0];
		which_bram_pipe[INTERPOLATER_DELAY-1:1] <= which_bram_pipe[INTERPOLATER_DELAY-2:0];
		dbatch_pipe[INTERPOLATER_DELAY-1:1] <= dbatch_pipe[INTERPOLATER_DELAY-2:0];

		if (rst) begin
			{sbram_addr, dbram_addr, regions_stored} <= 0; 
			{sparse_line_in, dense_line_in, dense_nxt_bram_bit, batch_ptr} <= 0;
			{dbram_we, dbram_en} <= 0; 
			{sbram_we, sbram_en} <= 0;  
			first_sb <= 0; 
			dma.ready <= 1;
			curr_bram <= 0;
			{which_bram_pipe[0],dbatch_pipe[0],intrp_pipe[0]} <= 0; 
			{gen_mode, rst_gen_mode, rdy_to_run} <= 0;
			pwlState <= IDLE; 
		end else begin
			if (pwlState == IDLE && curr_dma_valid) regions_stored <= 0;
			else if (dbram_we || sbram_we) regions_stored <= regions_stored + 1;

			case(pwlState)
				IDLE: begin
					if (run) begin
						dma.ready <= 0; 
						pwlState <= SETUP_GEN_MODE;
						rdy_to_run <= 0;
					end else begin
						dma.ready <= brams_writes_ready;
						if (dma.valid) gen_mode <= 0;
						if (brams_writes_ready) begin 
							if (curr_dma_valid) begin
								{sbram_addr, dbram_addr} <= 0;
								first_sb <= curr_dma_sb; 
								if (curr_dma_sb) begin
									{sbram_we, sbram_en} <= 3;
									sparse_line_in <= {curr_dma_x,curr_dma_slope,curr_dma_dt,nxt_dma_sb}; 
									intrp_pipe[0] <= 0;
									pwlState <= STORE_SPARSE_WAVE;
								end else begin
									intrp_pipe[0] <= {1'b1,curr_dma_dt}; 
									pwlState <= DENSE_INTRP_WAIT;
								end
								rdy_to_run <= 0;
							end else intrp_pipe[0] <= 0;
						end  
					end 
				end

				DENSE_INTRP_WAIT: begin 
					if (nxt_dma_sb || ~dma.valid) dma.ready <= 0; 
					intrp_pipe[0] <= (~curr_dma_sb && curr_dma_valid)? {1'b1,curr_dma_dt} : 0; 
					if (nxt_valid_intrp_out) begin 
						batch_ptr <= 0;
						pwlState <= STORE_DENSE_WAVE;
					end 
				end 

				STORE_DENSE_WAVE: begin
					if (nxt_dma_sb || ~dma.valid) dma.ready <= 0; 
					intrp_pipe[0] <= (~curr_dma_sb && curr_dma_valid)? {1'b1,curr_dma_dt} : 0; 
					if (dbram_we) dbram_addr <= (dbram_addr == DENSE_BRAM_DEPTH-1)? 0 : dbram_addr + 1; 

					if (valid_intrp_out) begin
						dense_line_in[batch_ptr+:BATCH_SIZE] <= intrp_batch;
						if (batch_ptr + intrp_out_dt == BATCH_SIZE) begin
							{dbram_we, dbram_en} <= 3;
							dense_nxt_bram_bit <= ~nxt_valid_intrp_out;
							batch_ptr <= 0; 
						end else begin
							{dbram_we, dbram_en} <= 0;
							batch_ptr <=  batch_ptr + intrp_out_dt;
						end
					end else begin
						{dbram_we, dbram_en} <= 0;
						dma.ready <= 1;
						if (curr_dma_valid) begin 
							{sbram_we, sbram_en} <= 3;
							sparse_line_in <= {curr_dma_x,curr_dma_slope,curr_dma_dt,nxt_dma_sb};
							intrp_pipe[0] <= 0;
							pwlState <= STORE_SPARSE_WAVE;
						end else begin
							rdy_to_run <= 1;
							pwlState <= IDLE;
						end 
					end
				end

				STORE_SPARSE_WAVE: begin
					if (~dma.valid) dma.ready <= 0;
					if (curr_dma_valid) begin 
						sbram_addr <= (sbram_addr == SPARSE_BRAM_DEPTH-1)? 0 : sbram_addr + 1;
						if (curr_dma_sb) sparse_line_in <= {curr_dma_x,curr_dma_slope,curr_dma_dt,nxt_dma_sb};
						if (~nxt_dma_sb) begin 
							{sbram_we, sbram_en} <= 0; 
							if (~curr_dma_sb) intrp_pipe[0] <= {1'b1,curr_dma_dt}; 
							pwlState <= DENSE_INTRP_WAIT;
						end  
					end else begin
						rdy_to_run <= 1;
						pwlState <= IDLE; 
					end 
				end

				SETUP_GEN_MODE: begin
					curr_bram <= first_sb;  
					{dbram_en,sbram_en,dbram_we,sbram_we} <= 0;
					{dbram_addr, sbram_addr} <= 0; 
					{dbram_next,sbram_next} <= 0;
					gen_mode <= 1; 
					if (brams_valid) begin
						if (first_sb) begin 
							sbram_next <= 1; 
							pwlState <= SEND_SPARSE_WAVE;
						end else begin
							dbram_next <= 1; 
							pwlState <= SEND_DENSE_WAVE; 
						end
					end
				end 

				SEND_DENSE_WAVE: begin
					if (halt) begin
						rst_gen_mode <= 1;
						pwlState <= HALT;
					end else begin
						which_bram_pipe[0] <= {1'b1,1'b0};
						dbatch_pipe[0] <= dense_batch_out[0+:BATCH_WIDTH];
						if (nxt_bram) begin
							curr_bram <= 1; 
							sbram_next <= 1; 
							dbram_next <= 0;
							pwlState <= SEND_SPARSE_WAVE; 
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
							if (~nxt_bram) begin
								sbram_next <= 0;
								dbram_next <= 1;
								curr_bram <= 0;
								pwlState <= SEND_DENSE_WAVE; 
							end
						end else begin
							x_reg <= x + slope*BATCH_SIZE;
							slope_reg <= slope;
							dt_reg <= dt - BATCH_SIZE;
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
							if (nxt_bram) begin 
								sbram_next <= 1; 
								pwlState <= SEND_SPARSE_WAVE;
							end else begin
								pwlState <= SEND_DENSE_WAVE;
								dbram_next <= 1; 
								curr_bram <= 0; 
							end
						end else dt_reg <= dt_reg - BATCH_SIZE;
					end 
				end 

				HALT: begin
					rst_gen_mode <= 0; 
					rdy_to_run <= 1;
					{sbram_next, dbram_next} <= 0;
					{which_bram_pipe[0],dbatch_pipe[0],intrp_pipe[0]} <= 0; 
					pwlState <= IDLE;
				end 
			endcase 
		end
	end
	
endmodule 

`default_nettype wire
