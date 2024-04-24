`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module ts_tb();
	localparam VERBOSE = 1; 	  
	localparam NUM_OF_TESTS = 7; 
	localparam STARTING_TEST = 0; // 0-indexed test num
	localparam TESTS_TO_RUN = -1; // Set -1 to run all tests

	logic clk, rst;
	logic[NUM_OF_TESTS-1:0] runTest = 0;
	logic[NUM_OF_TESTS-1:0] done, tb_passed; 
	logic signals_defined = 0; 
	logic[$clog2(NUM_OF_TESTS):0] currTestNum, passedTBs, failedTBs, completedTests; 
	logic test_suite_done; 

	axi_recieve_transmit_tb #(.VERBOSE(VERBOSE))
	art_tb(.start(runTest[0]&&signals_defined),
	       .done({tb_passed[0],done[0]}));

	slave_tb #(.VERBOSE(VERBOSE))
	sl_tb(.start(runTest[1]&&signals_defined),
	      .done({tb_passed[1],done[1]}));

	dac_intf_tb #(.VERBOSE(VERBOSE))
	di_tb(.start(runTest[2]&&signals_defined),
	      .done({tb_passed[2],done[2]}));

	adc_intf_tb #(.VERBOSE(VERBOSE))
	ai_tb(.start(runTest[3]&&signals_defined),
	      .done({tb_passed[3],done[3]}));

	pwl_tb #(.VERBOSE(VERBOSE))
	pwl_tb(.start(runTest[4]),
	       .done({tb_passed[4],done[4]}));

	sys_tb #(.VERBOSE(VERBOSE))
	sys_tb(.start(runTest[5]),
	       .done({tb_passed[5],done[5]}));

	top_level_tb #(.VERBOSE(VERBOSE))
	tl_tb(.start(runTest[6]),
	      .done({tb_passed[6],done[6]}));

	assign test_suite_done = currTestNum == NUM_OF_TESTS; 
	always_ff @(posedge clk) begin
		if (rst) begin 
			signals_defined <= 1; 
			runTest <= 1 << STARTING_TEST;
			currTestNum <= STARTING_TEST; 
			{passedTBs, failedTBs, completedTests} <= 0; 
		end else begin
			if (currTestNum < NUM_OF_TESTS) begin 
				if (runTest[currTestNum]) runTest[currTestNum] <= 0; 
				if (done[currTestNum]) begin
					if (TESTS_TO_RUN != -1 && completedTests+1 == TESTS_TO_RUN) currTestNum <= NUM_OF_TESTS;					 
					else begin 
						currTestNum <= currTestNum + 1;
						runTest[currTestNum+1] <= 1;
					end 
					if (|tb_passed) passedTBs <= passedTBs + 1;
					else failedTBs <= failedTBs + 1;
					completedTests <= completedTests + 1; 
				end 
			end 
		end
	end
	always begin
	    #5;  
	    clk = !clk;
	end
    initial begin
        $dumpfile("ts_tb.vcd");
        $dumpvars(0,ts_tb);
        clk = 0;
        rst = 0; 
        #500;
        if (VERBOSE) $display("\nTesting Suite:");
        `flash_sig(rst); 
        while (~test_suite_done) #10; 
        #1000;
        $display("Test Suite Complete\n");
        $write("%c[1;32m",27); 
        $write("%0d Testbenches passed, ", passedTBs); 
        $write("%c[1;31m",27);
        $display("%0d Testbenches failed\n", failedTBs);
        $write("%c[0m",27); 
       $finish;
    end 

endmodule 

`default_nettype wire


