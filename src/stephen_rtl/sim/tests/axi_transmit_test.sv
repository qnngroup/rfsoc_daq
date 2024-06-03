`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"
// Clean up this test and recieve's test so you're not repeating the test.
// have an inital begin in the generate and wait for a start vecotr, and continue to next with a done. 
module axi_transmit_test #(parameter IS_INTEGRATED = 0)();
	localparam TIMEOUT = 1000;
	localparam TEST_NUM = 12*2;; //12 with oscillating rdy, 12 with constant ready
	localparam int CLK_RATE_MHZ = 150;

	sim_util_pkg::debug debug = new(sim_util_pkg::DEBUG,TEST_NUM,"AXI_TRANSMIT",IS_INTEGRATED); 

	logic clk, rst; 
	int total_errors = 0;
	localparam[5:0][7:0] bus_widths = {8'd111, 8'd32, 8'd16, 8'd11, 8'd2, 8'd1};
	localparam[1:0][7:0] data_widths = {8'd32, 8'd16};

	generate
		for (genvar i = 0; i < 6; i++) begin : test_sets1
			for (genvar j = 0; j < 2; j++) begin : test_sets2
				Recieve_Transmit_IF #(bus_widths[i], data_widths[j]) intf(); 

				axi_transmit_tb #(.BUS_WIDTH(bus_widths[i]), .DATA_WIDTH(data_widths[j]))
				tb_i(.clk(clk), .rst(rst),
				   .intf(intf));

				axi_transmit #(.BUS_WIDTH(bus_widths[i]), .DATA_WIDTH(data_widths[j]))
				dut_i(.clk(clk), .rst(rst),
				      .bus(intf.transmit_bus));

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
        if (~IS_INTEGRATED) begin 
	        $dumpfile("axi_transmit_test.vcd");
	        $dumpvars(0,axi_transmit_test); 
	        run_tests(); 
	    end 
    end 

	task automatic run_tests();
		{clk,rst} = 0;
     	repeat (20) @(posedge clk);

        debug.displayc($sformatf("\n\n### TESTING %s ###\n\n",debug.get_test_name()));
     	debug.timeout_watcher(clk,TIMEOUT);
        repeat (5) @(posedge clk);
        flash_signal(rst,clk);        
       	repeat (20) @(posedge clk);
       	//Tests 0-12: Transmit random packets with altering bus/data widths (const ready signal)
       	//Tests 12-24:Transmit random packets with altering bus/data widths (oscillating ready signal)	
		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = high)",debug.test_num,bus_widths[0], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[0].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[0].test_sets2[0].tb_i.send_samples(debug);
		debug.check_test(test_sets1[0].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = high)",debug.test_num,bus_widths[1], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[1].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[1].test_sets2[0].tb_i.send_samples(debug);
		debug.check_test(test_sets1[1].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = high)",debug.test_num,bus_widths[2], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[2].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[2].test_sets2[0].tb_i.send_samples(debug);
		debug.check_test(test_sets1[2].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = high)",debug.test_num,bus_widths[3], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[3].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[3].test_sets2[0].tb_i.send_samples(debug);
		debug.check_test(test_sets1[3].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = high)",debug.test_num,bus_widths[4], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[4].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[4].test_sets2[0].tb_i.send_samples(debug);
		debug.check_test(test_sets1[4].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = high)",debug.test_num,bus_widths[5], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[5].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[5].test_sets2[0].tb_i.send_samples(debug);
		debug.check_test(test_sets1[5].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = high)",debug.test_num,bus_widths[0], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[0].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[0].test_sets2[1].tb_i.send_samples(debug);
		debug.check_test(test_sets1[0].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = high)",debug.test_num,bus_widths[1], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[1].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[1].test_sets2[1].tb_i.send_samples(debug);
		debug.check_test(test_sets1[1].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = high)",debug.test_num,bus_widths[2], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[2].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[2].test_sets2[1].tb_i.send_samples(debug);
		debug.check_test(test_sets1[2].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = high)",debug.test_num,bus_widths[3], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[3].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[3].test_sets2[1].tb_i.send_samples(debug);
		debug.check_test(test_sets1[3].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = high)",debug.test_num,bus_widths[4], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[4].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[4].test_sets2[1].tb_i.send_samples(debug);
		debug.check_test(test_sets1[4].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = high)",debug.test_num,bus_widths[5], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[5].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[5].test_sets2[1].tb_i.send_samples(debug);
		debug.check_test(test_sets1[5].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		//Tests 12-24
		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = oscillating)",debug.test_num,bus_widths[0], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[0].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[0].test_sets2[0].tb_i.send_samples(debug,.do_oscillate_rdy(1));
		debug.check_test(test_sets1[0].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = oscillating)",debug.test_num,bus_widths[1], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[1].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[1].test_sets2[0].tb_i.send_samples(debug,.do_oscillate_rdy(1));
		debug.check_test(test_sets1[1].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = oscillating)",debug.test_num,bus_widths[2], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[2].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[2].test_sets2[0].tb_i.send_samples(debug,.do_oscillate_rdy(1));
		debug.check_test(test_sets1[2].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = oscillating)",debug.test_num,bus_widths[3], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[3].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[3].test_sets2[0].tb_i.send_samples(debug,.do_oscillate_rdy(1));
		debug.check_test(test_sets1[3].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = oscillating)",debug.test_num,bus_widths[4], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[4].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[4].test_sets2[0].tb_i.send_samples(debug,.do_oscillate_rdy(1));
		debug.check_test(test_sets1[4].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = oscillating)",debug.test_num,bus_widths[5], data_widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[5].test_sets2[0].tb_i.prepare_rand_samples(20);
		test_sets1[5].test_sets2[0].tb_i.send_samples(debug,.do_oscillate_rdy(1));
		debug.check_test(test_sets1[5].test_sets2[0].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = oscillating)",debug.test_num,bus_widths[0], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[0].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[0].test_sets2[1].tb_i.send_samples(debug,.do_oscillate_rdy(1));
		debug.check_test(test_sets1[0].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = oscillating)",debug.test_num,bus_widths[1], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[1].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[1].test_sets2[1].tb_i.send_samples(debug,.do_oscillate_rdy(1));
		debug.check_test(test_sets1[1].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = oscillating)",debug.test_num,bus_widths[2], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[2].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[2].test_sets2[1].tb_i.send_samples(debug,.do_oscillate_rdy(1));
		debug.check_test(test_sets1[2].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = oscillating)",debug.test_num,bus_widths[3], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[3].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[3].test_sets2[1].tb_i.send_samples(debug,.do_oscillate_rdy(1));
		debug.check_test(test_sets1[3].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = oscillating)",debug.test_num,bus_widths[4], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[4].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[4].test_sets2[1].tb_i.send_samples(debug,.do_oscillate_rdy(1));
		debug.check_test(test_sets1[4].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));
		reset_errors();

		debug.displayc($sformatf("%0d: Transmit 20 random packets (bus_width = %0d, data_width = %0d, ready = oscillating)",debug.test_num,bus_widths[5], data_widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets1[5].test_sets2[1].tb_i.prepare_rand_samples(20);
		test_sets1[5].test_sets2[1].tb_i.send_samples(debug,.do_oscillate_rdy(1));
		total_errors += debug.get_error_count();
		debug.set_error_count(total_errors);
		debug.check_test(test_sets1[5].test_sets2[1].tb_i.check_samples(debug),.has_parts(1));

        if (~IS_INTEGRATED) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        else if (debug.test_num < TEST_NUM) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        debug.set_test_complete();
	endtask

endmodule 

`default_nettype wire
