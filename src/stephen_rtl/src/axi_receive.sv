`timescale 1ns / 1ps
`default_nettype none

import mem_layout_pkg::ABS_ADDR_CEILING;
import mem_layout_pkg::ABS_ID_CEILING;
import mem_layout_pkg::ADDR2ID;
module axi_receive #(parameter BUS_WIDTH, DATA_WIDTH)
					(input wire clk, rst,
					 input wire is_addr,
					 Recieve_Transmit_IF.receive_bus bus);
	logic[DATA_WIDTH-1:0] buff, mem_id;
	logic[$clog2((BUS_WIDTH > DATA_WIDTH)? BUS_WIDTH : DATA_WIDTH):0] buff_ptr;

	always_comb begin 
		if (BUS_WIDTH > DATA_WIDTH) mem_id = (buff <= ABS_ADDR_CEILING)? ADDR2ID(buff) : ABS_ID_CEILING; 
		else mem_id = (buff <= ABS_ADDR_CEILING)? ADDR2ID(buff) : ABS_ID_CEILING; 

		bus.valid_data = buff_ptr >= DATA_WIDTH; 
		if (bus.valid_data) bus.data = (is_addr)? mem_id : buff;
		else bus.data = 0; 
	end
	
	always_ff @(posedge clk) begin
		if (rst) {buff,buff_ptr} <= 0;
		else begin
			if (bus.valid_pack) begin
				if (BUS_WIDTH > DATA_WIDTH) buff <= bus.packet[DATA_WIDTH-1:0];
				else buff[buff_ptr+:BUS_WIDTH] <= bus.packet;
				buff_ptr <= (bus.valid_data)? BUS_WIDTH : buff_ptr + BUS_WIDTH; 
			end else begin
				if (buff_ptr >= DATA_WIDTH) buff_ptr <= 0; 
			end
		end
	end

endmodule 


`default_nettype wire
