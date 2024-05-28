`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module axi_transmit #(parameter BUS_WIDTH = 32, parameter DATA_WIDTH = 32)
					 (input wire clk, rst, Recieve_Transmit_IF.transmit_bus bus);
	localparam LAST_EVEN_CUT = (BUS_WIDTH < DATA_WIDTH && DATA_WIDTH%BUS_WIDTH != 0)? (DATA_WIDTH-(DATA_WIDTH%BUS_WIDTH)) : 0;
	enum logic {IDLE, TRANSMITTING} axiT_state;
	logic[DATA_WIDTH-1:0] data_to_send_buff; 
	logic send_buff, transmit;
	logic [$clog2((BUS_WIDTH > DATA_WIDTH)? BUS_WIDTH : DATA_WIDTH):0] trans_ptr;

	always_comb begin
		transmit = (bus.send || send_buff) && bus.dev_rdy;
		bus.trans_rdy = axiT_state == IDLE;
		case(axiT_state)
			IDLE: begin
				bus.valid_pack = transmit; 
				if (transmit) begin 
					if (bus.send) bus.packet = (BUS_WIDTH >= DATA_WIDTH)? bus.data_to_send[DATA_WIDTH-1:0] : bus.data_to_send[0+:BUS_WIDTH]; 
					else bus.packet = (BUS_WIDTH >= DATA_WIDTH)? data_to_send_buff[DATA_WIDTH-1:0] : data_to_send_buff[0+:BUS_WIDTH];
				end else bus.packet = 0;
			end 
			TRANSMITTING: begin
				bus.valid_pack = bus.dev_rdy; 
				bus.packet = (trans_ptr + BUS_WIDTH > DATA_WIDTH)? data_to_send_buff[DATA_WIDTH-1:LAST_EVEN_CUT] : data_to_send_buff[trans_ptr+:BUS_WIDTH]; 
			end
		endcase	
	end
	always_ff @(posedge clk) begin
		if (rst) begin
			{data_to_send_buff,trans_ptr,send_buff} <= 0;
			axiT_state <= IDLE;
		end else begin
			if (bus.send && ~bus.dev_rdy) send_buff <= 1;
			else if (send_buff && bus.dev_rdy) send_buff <= 0;  
			if (bus.send) data_to_send_buff <= bus.data_to_send; 
			case (axiT_state)
				IDLE: begin
					if (transmit) begin
						trans_ptr <= BUS_WIDTH;
						if (BUS_WIDTH >= DATA_WIDTH) bus.packet <= (bus.send)? bus.data_to_send[DATA_WIDTH-1:0] : data_to_send_buff[DATA_WIDTH-1:0];
						else begin
							bus.packet <= (bus.send)? bus.data_to_send[0+:BUS_WIDTH] : data_to_send_buff[0+:BUS_WIDTH];
							axiT_state <= TRANSMITTING;
						end 
					end 
				end 

				TRANSMITTING: begin
					if (bus.dev_rdy) begin 
						if (trans_ptr+BUS_WIDTH >= DATA_WIDTH) begin
							trans_ptr <= 0;
							axiT_state <= IDLE;
						end else trans_ptr <= trans_ptr + BUS_WIDTH;
					end
				end 
			endcase
		end 
	end

endmodule 

`default_nettype wire