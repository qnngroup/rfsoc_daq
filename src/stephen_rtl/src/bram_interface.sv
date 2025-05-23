`timescale 1ns / 1ps
`default_nettype none

module bram_interface #(parameter DATA_WIDTH = 48, parameter BRAM_DEPTH = 600, parameter BRAM_DELAY = 4)
			 		  		  (input wire clk, rst,
			 		  		   input wire[DATA_WIDTH-1:0] line_out_raw,
			 		  		   input wire we,
			 		  		   input wire generator_mode, rst_gen_mode, 
			 		  		   input wire next, 
			 		  		   output logic[$clog2(BRAM_DEPTH)-1:0] buff_addr,
			 		  		   output logic[DATA_WIDTH-1:0] line_out,
			 		  		   output logic valid_line_out,
			 		  		   output logic write_rdy);
	localparam BUFF_LEN = BRAM_DELAY+1;

	logic[BRAM_DELAY-1:0] valid_line_pipe; 
	logic valid_line;
	logic[BUFF_LEN-1:0][DATA_WIDTH-1:0] line_out_buffer; 
	logic[$clog2(BRAM_DEPTH)-1:0] lines_stored;
	logic[$clog2(BUFF_LEN)-1:0] buff_place_ptr, buff_access_ptr, els_in_buff;
	enum logic[2:0] {WRITE_MODE, PREP_GEN_MODE, FILL_BUFF, GENERATOR_MODE, SIMPLE_MODE} bramState;

	always_comb begin
		valid_line = valid_line_pipe[BRAM_DELAY-1];
		line_out = 	line_out_buffer[buff_access_ptr];
		write_rdy = bramState == WRITE_MODE;
	end

	always_ff @(posedge clk) begin
		valid_line_pipe[BRAM_DELAY-1:1] <= valid_line_pipe[BRAM_DELAY-2:0]; 

		if (rst) begin
			valid_line_pipe[0] <= 0; 
			{buff_addr,buff_place_ptr,buff_access_ptr,els_in_buff} <= 0;
			{lines_stored,valid_line_out} <= 0;
			bramState <= WRITE_MODE;
		end
		else begin
			case(bramState)
				WRITE_MODE: begin
					if (generator_mode) bramState <= PREP_GEN_MODE;
					if (we) lines_stored <= lines_stored + 1;
				end 

				PREP_GEN_MODE: begin
					if (~rst_gen_mode) begin 
						{buff_addr,buff_place_ptr,buff_access_ptr,els_in_buff} <= 0; 
						valid_line_pipe[0] <= 1;
						bramState <= FILL_BUFF;
					end 
				end 

				FILL_BUFF: begin
					if (buff_addr < BUFF_LEN) buff_addr <= buff_addr + 1; 
					if (buff_addr == BUFF_LEN-1) valid_line_pipe[0] <= 0;
					if (els_in_buff < BUFF_LEN) begin
						if (valid_line) begin 
							els_in_buff <= els_in_buff + 1;
							buff_place_ptr <= (buff_place_ptr == BUFF_LEN-1)? 0 : buff_place_ptr + 1;
							line_out_buffer[buff_place_ptr] <= line_out_raw;
						end 
					end else begin
						valid_line_out <= 1;
						bramState <= (lines_stored > BUFF_LEN)? GENERATOR_MODE : SIMPLE_MODE;
					end
				end 

				GENERATOR_MODE: begin
					if (rst_gen_mode) begin
						valid_line_out <= 0; 
						bramState <= PREP_GEN_MODE;
					end else if (~generator_mode) begin
						bramState <= WRITE_MODE;
						valid_line_pipe[0] <= 0; 
						{buff_addr,buff_place_ptr,buff_access_ptr,els_in_buff} <= 0;
						{lines_stored,valid_line_out} <= 0;
					end else begin 
						if (next) begin
							buff_access_ptr <= (buff_access_ptr == BUFF_LEN-1)? 0 : buff_access_ptr + 1;
							buff_addr <= (buff_addr == lines_stored-1)? 0 : buff_addr + 1; 
							valid_line_pipe[0] <= 1;
						end else valid_line_pipe[0] <= 0;

						if (valid_line && ~next) els_in_buff <= els_in_buff + 1; 
						if (next && ~valid_line) els_in_buff <= els_in_buff - 1;

						if (valid_line) begin
							buff_place_ptr <= (buff_place_ptr == BUFF_LEN-1)? 0 : buff_place_ptr + 1;
							line_out_buffer[buff_place_ptr] <= line_out_raw;
						end 
					end 
				end 

				SIMPLE_MODE: begin
					if (rst_gen_mode) begin
						valid_line_out <= 0; 
						bramState <= PREP_GEN_MODE;
					end else if (~generator_mode) begin
						bramState <= WRITE_MODE;
						valid_line_pipe[0] <= 0; 
						{buff_addr,buff_place_ptr,buff_access_ptr,els_in_buff} <= 0;
						{lines_stored,valid_line_out} <= 0;
					end else 
					if (next) buff_access_ptr <= (buff_access_ptr == lines_stored-1)? 0 : buff_access_ptr + 1;
				end 
			endcase 
		end
	end
	
endmodule 

`default_nettype wire
