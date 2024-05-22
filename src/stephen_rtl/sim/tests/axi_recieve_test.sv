`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module axi_recieve_test();
	localparam DATA_WIDTH = 16; 
	localparam TIMEOUT = 500;
	localparam TEST_NUM = 1*6; 
	localparam int PS_CLK_RATE_HZ = 100_000_000;
	sim_util_pkg::debug debug = new(sim_util_pkg::DEBUG,TEST_NUM); 

	logic clk, rst; 
	localparam[5:0][7:0] widths = {8'd111, 8'd32, 8'd16, 8'd11, 8'd2, 8'd1};

	generate
		for (genvar i = 0; i < 6; i++) begin: test_sets
			Recieve_Transmit_IF #(widths[i], DATA_WIDTH) intf(); 

			axi_recieve_tb #(.BUS_WIDTH(widths[i]), .DATA_WIDTH(DATA_WIDTH))
			tb(.clk(clk), .rst(rst),
			     .intf(intf));

			axi_receive #(.BUS_WIDTH(widths[i]), .DATA_WIDTH(DATA_WIDTH))
			dut(.clk(clk),
			      .rst(rst),
			      .is_addr(1'b0),
			      .bus(intf.receive_bus));
		end
	endgenerate
	always #(0.5s/PS_CLK_RATE_HZ) clk = ~clk;
	initial begin
        $dumpfile("axi_recieve_test.vcd");
        $dumpvars(0,axi_recieve_test); 
        {clk,rst} = 0;
     	repeat (20) @(posedge clk);
        debug.displayc("\n\n### TESTING AXI_RECIEVE ###\n\n");
     	debug.timeout_watcher(clk,TIMEOUT);
        repeat (5) @(posedge clk);
        `flash_signal(rst,clk);        
       	repeat (20) @(posedge clk);

       	//Tests 0-5: Send random packets with altering bus widths 
       	debug.displayc($sformatf("%0d: Send 50 random packets (bus_width = %0d)",0,widths[0]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets[0].tb.send_packets(20);
		debug.check_test(test_sets[0].tb.check_packets(debug),.has_parts(1));
		debug.clear_error_count(); 

		debug.displayc($sformatf("%0d: Send 50 random packets (bus_width = %0d)",1,widths[1]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets[1].tb.send_packets(20);
		debug.check_test(test_sets[1].tb.check_packets(debug),.has_parts(1));
		debug.clear_error_count(); 

		debug.displayc($sformatf("%0d: Send 50 random packets (bus_width = %0d)",2,widths[2]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets[2].tb.send_packets(20);
		debug.check_test(test_sets[2].tb.check_packets(debug),.has_parts(1));
		debug.clear_error_count(); 

		debug.displayc($sformatf("%0d: Send 50 random packets (bus_width = %0d)",3,widths[3]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets[3].tb.send_packets(20);
		debug.check_test(test_sets[3].tb.check_packets(debug),.has_parts(1));
		debug.clear_error_count(); 

		debug.displayc($sformatf("%0d: Send 50 random packets (bus_width = %0d)",4,widths[4]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets[4].tb.send_packets(20);
		debug.check_test(test_sets[4].tb.check_packets(debug),.has_parts(1));
		debug.clear_error_count(); 

		debug.displayc($sformatf("%0d: Send 50 random packets (bus_width = %0d)",5,widths[5]), .msg_verbosity(sim_util_pkg::VERBOSE));
		test_sets[5].tb.send_packets(20);
		debug.check_test(test_sets[5].tb.check_packets(debug),.has_parts(1));
		debug.clear_error_count(); 

        debug.finishc();
    end 
endmodule 

`default_nettype wire

