`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module axi_recieve_test();
	localparam TIMEOUT = 1000;
	localparam TEST_NUM = 1*12+6; // 1 test for all plus 1 additional address tests for the 32 data widths
	localparam int CLK_RATE_MHZ = 150;

	sim_util_pkg::debug debug = new(sim_util_pkg::DEBUG,TEST_NUM,"AXI_RECIEVE"); 

	logic clk, rst; 
	int total_errors = 0;
	bit addr_test = 0;
	localparam[5:0][7:0] bus_widths = {8'd111, 8'd32, 8'd16, 8'd11, 8'd2, 8'd1};
	localparam[1:0][7:0] data_widths = {8'd32, 8'd16};

	generate
		for (genvar i = 0; i < 6; i++) begin : test_sets1
			for (genvar j = 0; j < 2; j++) begin : test_sets2
				Recieve_Transmit_IF #(bus_widths[i], data_widths[j]) intf(); 

				axi_recieve_tb #(.BUS_WIDTH(bus_widths[i]), .DATA_WIDTH(data_widths[j]))
				tb_i(.clk(clk), .rst(rst),
				     .intf(intf));

				axi_receive #(.BUS_WIDTH(bus_widths[i]), .DATA_WIDTH(data_widths[j]))
				dut(.clk(clk), .rst(rst),
				    .is_addr(addr_test),
				    .bus(intf.receive_bus));
				initial begin
					tb_i.init();
				end
			end 
		end
	endgenerate

	task automatic reset_errors();
		total_errors += debug.get_error_count();
		debug.clear_error_count(); 
	endtask 


	always #(0.5s/(CLK_RATE_MHZ*1_000_000)) clk = ~clk;
	initial begin
        $dumpfile("axi_recieve_test.vcd");
        $dumpvars(0,axi_recieve_test); 
        {clk,rst} = 0;
     	repeat (20) @(posedge clk);
        debug.displayc($sformatf("\n\n### TESTING %s ###\n\n",debug.get_test_name()));
     	debug.timeout_watcher(clk,TIMEOUT);
        repeat (5) @(posedge clk);
        flash_signal(rst,clk);        
       	repeat (20) @(posedge clk);

       	//Tests 0-12: Send random packets with altering bus/data widths 
       	//Tests 12-18: Send random packets and address space with alternating bus/data widths
		debug.displayc($sformatf("%0d: Receive 20 random packets (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[0], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[0].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[0].test_sets2[0].tb_i.send_samples();
		debug.check_test(test_sets1[0].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Receive 20 random packets (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[1], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[1].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[1].test_sets2[0].tb_i.send_samples();
		debug.check_test(test_sets1[1].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Receive 20 random packets (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[2], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[2].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[2].test_sets2[0].tb_i.send_samples();
		debug.check_test(test_sets1[2].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Receive 20 random packets (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[3], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[3].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[3].test_sets2[0].tb_i.send_samples();
		debug.check_test(test_sets1[3].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Receive 20 random packets (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[4], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[4].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[4].test_sets2[0].tb_i.send_samples();
		debug.check_test(test_sets1[4].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Receive 20 random packets (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[5], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[5].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[5].test_sets2[0].tb_i.send_samples();
		debug.check_test(test_sets1[5].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Receive 20 random packets (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[0], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		addr_test = 0;
		test_sets1[0].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[0].test_sets2[1].tb_i.send_samples();
		debug.check_test(test_sets1[0].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();
		debug.displayc($sformatf("%0d: Receive address space (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[0], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		addr_test = 1;
		test_sets1[0].test_sets2[1].tb_i.prepare_addr_samples();
		test_sets1[0].test_sets2[1].tb_i.send_samples();
		debug.check_test(test_sets1[0].test_sets2[1].tb_i.check_samples(debug,.is_addr(1)),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Receive 20 random packets (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[1], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		addr_test = 0;
		test_sets1[1].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[1].test_sets2[1].tb_i.send_samples();
		debug.check_test(test_sets1[1].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();
		debug.displayc($sformatf("%0d: Receive address space (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[1], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		addr_test = 1;
		test_sets1[1].test_sets2[1].tb_i.prepare_addr_samples();
		test_sets1[1].test_sets2[1].tb_i.send_samples();
		debug.check_test(test_sets1[1].test_sets2[1].tb_i.check_samples(debug,.is_addr(1)),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Receive 20 random packets (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[2], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		addr_test = 0;
		test_sets1[2].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[2].test_sets2[1].tb_i.send_samples();
		debug.check_test(test_sets1[2].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();
		debug.displayc($sformatf("%0d: Receive address space (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[2], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		addr_test = 1;
		test_sets1[2].test_sets2[1].tb_i.prepare_addr_samples();
		test_sets1[2].test_sets2[1].tb_i.send_samples();
		debug.check_test(test_sets1[2].test_sets2[1].tb_i.check_samples(debug,.is_addr(1)),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Receive 20 random packets (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[3], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		addr_test = 0;
		test_sets1[3].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[3].test_sets2[1].tb_i.send_samples();
		debug.check_test(test_sets1[3].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();
		debug.displayc($sformatf("%0d: Receive address space (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[3], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		addr_test = 1;
		test_sets1[3].test_sets2[1].tb_i.prepare_addr_samples();
		test_sets1[3].test_sets2[1].tb_i.send_samples();
		debug.check_test(test_sets1[3].test_sets2[1].tb_i.check_samples(debug,.is_addr(1)),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Receive 20 random packets (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[4], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		addr_test = 0;
		test_sets1[4].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[4].test_sets2[1].tb_i.send_samples();
		debug.check_test(test_sets1[4].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();
		debug.displayc($sformatf("%0d: Receive address space (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[4], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		addr_test = 1;
		test_sets1[4].test_sets2[1].tb_i.prepare_addr_samples();
		test_sets1[4].test_sets2[1].tb_i.send_samples();
		debug.check_test(test_sets1[4].test_sets2[1].tb_i.check_samples(debug,.is_addr(1)),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Receive 20 random packets (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[5], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		addr_test = 0;
		test_sets1[5].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[5].test_sets2[1].tb_i.send_samples();
		debug.check_test(test_sets1[5].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();
		debug.displayc($sformatf("%0d: Receive address space (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[5], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		addr_test = 1;
		test_sets1[5].test_sets2[1].tb_i.prepare_addr_samples();
		test_sets1[5].test_sets2[1].tb_i.send_samples();
		total_errors += debug.get_error_count();
		debug.set_error_count(total_errors); 
		debug.check_test(test_sets1[5].test_sets2[1].tb_i.check_samples(debug,.is_addr(1)),.has_parts(1));

        debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
    end 
endmodule 

`default_nettype wire
