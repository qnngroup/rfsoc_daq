`timescale 1ns / 1ps
`default_nettype none

module LFSR #(parameter DATA_WIDTH = 16) 
			 (input wire clk,rst,
			  input wire [DATA_WIDTH-1:0] seed,
			  input wire run,
			  output logic[DATA_WIDTH-1:0] sample_out);	
	always_ff @(posedge clk) begin
	    if (rst) sample_out <= seed;
	    else begin
	    	if (run) begin
		    	sample_out[0] <= sample_out[DATA_WIDTH-1];
		        for (int i = DATA_WIDTH-1; i > 0; i--) begin
		        	if (i%3 == 0) sample_out[i] <= sample_out[i-1] ^ sample_out[DATA_WIDTH-1];
		        	else sample_out[i] <= sample_out[i-1];
		        end
		    end 
		end 
    end
endmodule 

`default_nettype wire