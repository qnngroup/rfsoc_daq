`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module axi_recieve_tb #(parameter BUS_WIDTH, parameter DATA_WIDTH)
					   (input wire clk, rst,
					    Recieve_Transmit_IF intf);
	
	logic [DATA_WIDTH-1:0] data_out [$];
	logic [DATA_WIDTH-1:0] data_in [$];
	int samples_to_send = 0;
	int samples_recieved = 0; 

	axi_transmit #(.BUS_WIDTH(BUS_WIDTH), .DATA_WIDTH(DATA_WIDTH))
	transmitter(.clk(clk), .rst(rst),
	            .bus(intf.transmit_bus));

	always @(posedge clk) begin
		if (intf.valid_data) begin
			data_out.push_front(intf.data);
			samples_recieved++;
		end 
	end

	task automatic send_packets(input int n_samples);
		samples_to_send = n_samples;
		for (int i = 0; i < samples_to_send; i++) data_in.push_front($urandom());
		intf.dev_rdy <= 1;
		{intf.data_to_send,intf.send} <= 0; 
		@(posedge clk);
		for (int i = samples_to_send-1; i >= 0; i--) begin
			intf.data_to_send <= data_in[i]; 
			`flash_signal(intf.send,clk)
			while (~intf.trans_rdy) @(posedge clk);
		end
		repeat(5) @(posedge clk);
	endtask

	function bit check_packets(inout sim_util_pkg::debug debug);
		int err_in = debug.error_count;	
		if (~debug.disp_test_part(1,samples_recieved != 0,"No samples recieved")) return 0;
		if (~debug.disp_test_part(2,samples_recieved == samples_to_send,"Sample mismatch")) return 0;
		for (int i = 0; i < samples_to_send; i++) begin
			debug.disp_test_part(3+i,data_in[i] == data_out[i],$sformatf("Sample #%0d incorrect. 0x%0x != 0x%0x", i, data_in[i], data_out[i]));
		end
		clear_queues();
		return debug.error_count == err_in;
	endfunction 

	function void clear_queues();
		while (data_out.size() > 0) data_out.pop_back();
		while (data_in.size() > 0) data_in.pop_back();
		samples_to_send = 0;
		samples_recieved = 0; 
	endfunction

endmodule 

`default_nettype wire

