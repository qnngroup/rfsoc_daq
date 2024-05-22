`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module axi_recieve_tb #(parameter BUS_WIDTH, parameter DATA_WIDTH)
					   (input wire clk,
					    input Recieve_Transmit_IF.receive_bus intf);
	
	logic [DATA_WIDTH-1:0] recieved_data [$];

	always @(posedge clk) begin
		if (intf.valid_data) recieved_data.push_front(intf.data)
	end

	task automatic init();
		intf.data <= 0;
		intf.valid_data <= 0;
		@(posedge clk);
	endtask

	task automatic send_packet(input logic[BUS_WIDTH-1:0] packet);
  		
	endtask
endmodule 

`default_nettype wire

/*
Test bench expectations: I'd like a class or set of tasks that do the following:

1. One object gets called in one initial begin loop; it takes in a tb name and a vector of test names, as well as a timeout limit. 
It cycles through each test and waits for any condition to enter. It prints statements based on that and exits. 
2. This is just my usual testing strucuture because it makes sense to me and it very flexible but idk how to standardize it. 
*/
