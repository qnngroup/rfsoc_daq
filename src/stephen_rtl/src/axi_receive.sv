`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module axi_receive #(parameter BUS_WIDTH = 32, parameter DATA_WIDTH = 16)
					(input wire clk, rst,
					 input wire is_addr,
					 Recieve_Transmit_IF.receive_bus bus);

	enum logic{IDLE, RECEIVING} axiR_state;
	logic[DATA_WIDTH-1:0] buff;
	logic[`A_DATA_WIDTH-1:0] ps_addr_req; 
	logic[$clog2(`MEM_SIZE)-1:0] mem_id; 

	assign mem_id = (ps_addr_req <= `ABS_ADDR_CEILING)? (ps_addr_req - `PS_BASE_ADDR) >> 2 : `ABS_ID_CEILING; 
	assign ps_addr_req = buff; 
	assign bus.valid_data = (axiR_state == RECEIVING && ~bus.valid_pack);
	assign bus.data = (bus.valid_data)? ( (is_addr)? mem_id : buff ) : 0;
	
	always_ff @(posedge clk) begin
		if (rst) begin
			buff <= 0;
			axiR_state <= IDLE;
		end else begin
			case (axiR_state) 
				IDLE: begin
					if (bus.valid_pack) begin
						if (BUS_WIDTH >= DATA_WIDTH) buff <= bus.packet;
						else buff <= {buff[DATA_WIDTH-1-BUS_WIDTH:0],bus.packet}; 
						axiR_state <= RECEIVING;
					end
				end 

				RECEIVING: begin
					if (bus.valid_pack) begin
						if (BUS_WIDTH >= DATA_WIDTH) buff <= bus.packet;
						else buff <= {buff[DATA_WIDTH-1-BUS_WIDTH:0],bus.packet}; 
					end 
					else axiR_state <= IDLE;
				end 
			endcase 
		end
	end

endmodule 


`default_nettype wire
