`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"

module intrp_test #(parameter IS_INTEGRATED = 0)();
	localparam TIMEOUT = 1000;
	localparam TEST_NUM = 4;
	localparam int PS_CLK_RATE_HZ = 100_000_000;
    logic clk, rst; 
    logic[`SAMPLE_WIDTH-1:0] x;
    logic[(2*`SAMPLE_WIDTH)-1:0] slope; 
    logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] intrp_batch;
    int total_errors = 0;
    int curr_err;
    real float;
    
    sim_util_pkg::debug debug = new(sim_util_pkg::DEBUG,TEST_NUM,"INTERPOLATER", IS_INTEGRATED); 

    interpolater #(.SAMPLE_WIDTH(`SAMPLE_WIDTH), .BATCH_SIZE(`BATCH_SAMPLES))
    dut_i(.clk(clk),
          .x(x), .slope(slope),
          .intrp_batch(intrp_batch));

    intrp_tb #(.BATCH_SIZE(`BATCH_SAMPLES), .SAMPLE_WIDTH(`SAMPLE_WIDTH), .M(16), .N(16))
    tb_i(.clk(clk),
        .intrp_batch(intrp_batch),
        .x(x), .slope(slope));

	always #(0.5s/PS_CLK_RATE_HZ) clk = ~clk;    

    initial begin
        if (~IS_INTEGRATED) begin 
            $dumpfile("intrp_test.vcd");
            $dumpvars(0,intrp_test); 
            run_tests(); 
        end  
    end 

	task automatic reset_errors();
        total_errors += debug.get_error_count();
        debug.clear_error_count(); 
    endtask 
    task automatic combine_errors();
        total_errors += debug.get_error_count();
        debug.set_error_count(total_errors);
    endtask 

    task automatic run_tests();
        {clk,rst} = 0;
        debug.displayc($sformatf("\n\n### TESTING %s ###\n\n",debug.get_test_name()));
        repeat (5) @(posedge clk);
        debug.timeout_watcher(clk,TIMEOUT);
        tb_i.init();
        repeat (20) @(posedge clk);

        // TEST 1
        debug.displayc($sformatf("%0d: Positive whole slope",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.check_intrped_batch(debug, 1, 2);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();
        // TEST 2
        debug.displayc($sformatf("%0d: Negative whole slope",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.check_intrped_batch(debug, 2, -2);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();
        // TEST 3
        debug.displayc($sformatf("%0d: Positive fractional slope",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.check_intrped_batch(debug, 3, 0.5);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();
        // TEST 4
        debug.displayc($sformatf("%0d: Negative fractional slope",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.check_intrped_batch(debug, 4, -0.5);
        combine_errors();
        repeat (30) @(posedge clk);
        
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));

    endtask 

endmodule 

`default_nettype wire

