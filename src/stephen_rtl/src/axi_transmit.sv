`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module axi_transmit #(parameter BUS_WIDTH = 32, parameter DATA_WIDTH = 32)
					 (input wire clk, rst, Recieve_Transmit_IF.transmit_bus bus);

	localparam PACKETS_TO_SEND = DATA_WIDTH/BUS_WIDTH;
	enum logic[1:0] {IDLE, RDY_WAIT, TRANSMITTING} axiT_state;
	logic[DATA_WIDTH-1:0] send_mask;
	logic[$clog2(PACKETS_TO_SEND)+1:0] packets_sent;
	logic[DATA_WIDTH-1:0] data_to_send_buff; 

	assign send_mask = {BUS_WIDTH{$signed(1'b1)}} << BUS_WIDTH*(PACKETS_TO_SEND - packets_sent);
	assign bus.valid_pack = axiT_state != IDLE;
	if (BUS_WIDTH >= DATA_WIDTH) begin
		assign bus.packet = (bus.valid_pack)? data_to_send_buff : 0;
	end else begin
		assign bus.packet = (bus.valid_pack)? (data_to_send_buff & send_mask) >> BUS_WIDTH*(PACKETS_TO_SEND - packets_sent) : 0;
	end
	assign bus.trans_rdy = axiT_state == IDLE;
	always_ff @(posedge clk) begin
		if (rst) begin
			{packets_sent,data_to_send_buff} <= 0;
			axiT_state <= IDLE;
		end else begin
			case (axiT_state) 
				IDLE: begin
					if (bus.send) begin
						data_to_send_buff <= bus.data_to_send; 
						packets_sent <= 1;
						axiT_state <= (bus.dev_rdy)? TRANSMITTING : RDY_WAIT;
					end
				end 

				RDY_WAIT: begin 
					if (bus.dev_rdy) begin
						axiT_state <= (BUS_WIDTH >= DATA_WIDTH)? IDLE : TRANSMITTING;
						packets_sent <= 2;
					end 
				end 

				TRANSMITTING: begin
					if (bus.dev_rdy) begin
						if (packets_sent == PACKETS_TO_SEND || BUS_WIDTH >= DATA_WIDTH) axiT_state <= IDLE;
						else packets_sent <= packets_sent + 1;
					end 
				end 
			endcase 
		end
	end

endmodule 

`default_nettype wire