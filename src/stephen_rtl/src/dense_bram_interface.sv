`timescale 1ns / 1ps
`default_nettype none

module dense_bram_interface #(parameter DATA_WIDTH = 257, parameter BRAM_DEPTH = 600)
			 		  		  (input wire clk, rst,
			 		  		   input wire [$clog2(BRAM_DEPTH)-1:0] addr,
			 		  		   input wire[DATA_WIDTH-1:0] line_in,
			 		  		   input wire we, en, 
			 		  		   input wire generator_mode, rst_gen_mode, 
			 		  		   input wire next, 
			 		  		   output logic[DATA_WIDTH-1:0] line_out,
			 		  		   output logic valid_line_out,
			 		  		   output logic write_rdy);
	localparam BRAM_DELAY = 4; // # of clock cycles AFTER changing an address to get respective valid data 
	
	logic en_in, we_in;
	logic[$clog2(BRAM_DEPTH)-1:0] addr_in,buff_addr;
	logic[DATA_WIDTH-1:0] line_out_raw;

	assign en_in = (generator_mode)? 1'b1 : en;
	assign we_in = (generator_mode)? 1'b0 : we; 
	assign addr_in = (generator_mode)? buff_addr : addr;

	bram_interface #(.DATA_WIDTH(DATA_WIDTH), .BRAM_DEPTH(BRAM_DEPTH), .BRAM_DELAY(BRAM_DELAY))
	sbram_interface (.clk(clk),.rst(rst),
					 .line_out_raw(line_out_raw),
					 .we(we), .next(next),
					 .generator_mode(generator_mode), .rst_gen_mode(rst_gen_mode),
					 .buff_addr(buff_addr),
					 .line_out(line_out),
					 .valid_line_out(valid_line_out),
					 .write_rdy(write_rdy));

	DENSE_BRAM DWAVE_BRAM (.clka(clk),       
			   			    .addra(addr_in), .dina(line_in),       
			   			    .wea(we_in), .ena(en_in), 
			   			    .regcea(1'b1),        
			   			    .douta(line_out_raw));
endmodule 

`default_nettype wire
