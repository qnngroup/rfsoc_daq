`default_nettype none
`timescale 1ns / 1ps

module axi_transmit_tb #(parameter BUS_WIDTH, parameter DATA_WIDTH)
					   (input wire clk, rst,
					    Recieve_Transmit_IF intf);
	
	logic [DATA_WIDTH-1:0] data_in [$];
	logic [DATA_WIDTH-1:0] data_out [$];
	int samples_to_send = 0;
	int samples_recieved = 0; 
	int test; 
	logic clk2;
	bit halt_osc = 0;
	assign clk2 = clk;

	axi_receive #(.BUS_WIDTH(BUS_WIDTH), .DATA_WIDTH(DATA_WIDTH))
	receiver(.clk(clk), .rst(rst),
	         .is_addr(1'b0),
	         .bus(intf.receive_bus));

	always @(posedge clk) begin
		if (intf.valid_data) begin
			data_out.push_front(intf.data);
			samples_recieved++;
		end 
	end

	task automatic init();
		{intf.dev_rdy, intf.data_to_send, intf.send} <= 0;
		@(posedge clk);
	endtask 

	task automatic oscillate_rdy(ref bit halt_osc);
		fork 
			begin
				bit[3:0] delay_timer;
				while (~halt_osc) begin
					delay_timer = $urandom_range(1,8);
					intf.dev_rdy <= 0; 
					for (int i = 0; i < delay_timer; i++) @(posedge clk); 
					intf.dev_rdy <= 1;
					@(posedge clk); 
				end
			end
		join_none
	endtask 

	task automatic prepare_rand_samples(input int n_samples);
		samples_to_send = n_samples;
		for (int i = 0; i < samples_to_send; i++) data_in.push_front($urandom());
	endtask

	task automatic send_samples(inout sim_util_pkg::debug debug, input bit do_oscillate_rdy = 0);		
		intf.dev_rdy <= 1; 
		@(posedge clk);
		halt_osc = 0;
		if (do_oscillate_rdy) oscillate_rdy(halt_osc);
		for (int i = samples_to_send-1; i >= 0; i--) begin
			intf.data_to_send <= data_in[i]; 
			sim_util_pkg::flash_signal(intf.send,clk2); 
			while (~intf.valid_data) @(posedge clk);
			debug.reset_timeout(clk2);			
		end 
		if (do_oscillate_rdy) halt_osc = 1;
		repeat(5) @(posedge clk);
	endtask

	function bit check_samples(inout sim_util_pkg::debug debug);
		int err_in = debug.get_error_count();	
		if (~debug.disp_test_part(1,samples_recieved != 0,"No samples recieved")) return 0;
		if (~debug.disp_test_part(2,samples_recieved == samples_to_send,"Sample mismatch")) return 0;
		for (int i = 0; i < samples_to_send; i++) begin
			debug.disp_test_part(3+i,data_in[i] == data_out[i],$sformatf("Sample #%0d incorrect. 0x%0x != 0x%0x", i, data_in[i], data_out[i]));
		end
		clear_queues();
		return debug.get_error_count() == err_in;
	endfunction 

	function void clear_queues();
		while (data_out.size() > 0) data_out.pop_back();
		while (data_in.size() > 0) data_in.pop_back();
		samples_to_send = 0;
		samples_recieved = 0; 
	endfunction

endmodule 

`default_nettype wire

