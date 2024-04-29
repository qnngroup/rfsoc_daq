`timescale 1ns / 1ps
`default_nettype none

module counter #(parameter COUNTER_WIDTH = 32) 
			    (input wire clk,rst,
			     input wire clk_enable,
			     output logic[COUNTER_WIDTH-1:0] count);

	enum logic {IDLE,COUNTING} countState;

	always_ff @(posedge clk) begin
		if (rst) begin
			count <= 0; 
			countState <= IDLE;
		end else begin
			case(countState)
				IDLE: begin 
					if (clk_enable) begin
						count <= count + 1; 
						countState <= COUNTING; 
					end
				end 

				COUNTING: begin
					if (clk_enable) count <= count + 1;
					else countState <= IDLE; 
				end 
			endcase 
		end
	end
	
endmodule 

`default_nettype wire