`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"

module pwl_test #(parameter IS_INTEGRATED = 0)();
	localparam TIMEOUT = 10000;
	localparam TEST_NUM = 6;
	localparam int CLK_RATE_HZ = 100_000_000;
    logic clk, rst; 
    logic halt, run_pwl, rdy_to_run;
    logic[(2*`WD_DATA_WIDTH)-1:0] pwl_wave_period;
    logic valid_pwl_wave_period;
    logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] batch_out;
    logic valid_batch_out;
    int curr_err, test_num; 
    int total_errors = 0;

    Axis_IF #(`DMA_DATA_WIDTH) pwl_dma(); 

    sim_util_pkg::debug debug = new(sim_util_pkg::DEBUG,TEST_NUM,"PWL", IS_INTEGRATED); 

    pwl_generator #(.DMA_DATA_WIDTH(`DMA_DATA_WIDTH), .SAMPLE_WIDTH(`SAMPLE_WIDTH), .BATCH_SIZE(`BATCH_SAMPLES), .SPARSE_BRAM_DEPTH(`SPARSE_BRAM_DEPTH), .DENSE_BRAM_DEPTH(`DENSE_BRAM_DEPTH))
    dut_i(.clk(clk), .rst(rst),
          .halt(halt), .run(run_pwl), .rdy_to_run(rdy_to_run),
          .pwl_wave_period(pwl_wave_period), .valid_pwl_wave_period(valid_pwl_wave_period),
          .batch_out(batch_out), .valid_batch_out(valid_batch_out),
          .dma(pwl_dma));

    pwl_tb #(.SAMPLE_WIDTH(`SAMPLE_WIDTH), .DMA_DATA_WIDTH(`DMA_DATA_WIDTH), .BATCH_SIZE(`BATCH_SAMPLES))
    tb_i(.clk(clk), .rst(rst),
         .valid_batch(valid_batch_out), .batch(batch_out),
         .halt(halt), .run_pwl(run_pwl),
         .dma(pwl_dma));

    always_ff @(posedge clk) test_num <= debug.test_num;
	always #(0.5s/CLK_RATE_HZ) clk = ~clk;
	initial begin
        if (~IS_INTEGRATED) begin 
            $dumpfile("pwl_test.vcd");
            $dumpvars(0,pwl_test); 
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
        debug.displayc($sformatf("%0d: Run a single batch wave (sparse, 5 periods)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.send_single_batch(.is_sparse(1)); 
        debug.disp_test_part(1,valid_batch_out == 0,"There shouldn't yet be valid batches");
        tb_i.check_pwl_wave(debug,5);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 2
        debug.displayc($sformatf("%0d: Check wave period",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE)); 
        debug.check_test(valid_pwl_wave_period == 1 && pwl_wave_period == 1, .has_parts(0));

        // TEST 3
        debug.displayc($sformatf("%0d: Halt output and confirm a full period",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));  
        tb_i.halt_pwl();
        while (valid_batch_out) @(posedge clk); 
        tb_i.check_pwl_wave(debug,1); 
        tb_i.halt_pwl();
        debug.check_test(1'b1, .has_parts(0));
        
        // TEST 4
        debug.displayc($sformatf("%0d: Run a single batch wave (dense, 5 periods)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.send_single_batch(.is_sparse(0)); 
        debug.disp_test_part(1,valid_batch_out == 0 && valid_pwl_wave_period == 0,"There shouldn't yet be valid batches nor a valid period");
        tb_i.check_pwl_wave(debug,5);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 5
        debug.displayc($sformatf("%0d: Check wave period", debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE)); 
        debug.check_test(valid_pwl_wave_period == 1 && pwl_wave_period == 1, .has_parts(0));

        // TEST 6
        debug.displayc($sformatf("%0d: Halt output and confirm a full period",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));  
        tb_i.halt_pwl();
        while (valid_batch_out) @(posedge clk); 
        tb_i.check_pwl_wave(debug,1); 
        tb_i.halt_pwl();
        debug.check_test(1'b1, .has_parts(0));

        // TEST 7
        debug.displayc($sformatf("%0d: Run a full wave (stable valid, 3 periods)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));  
        curr_err = debug.get_error_count();
        tb_i.send_pwl_wave();
        tb_i.check_pwl_wave(debug,3); 
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));

        if (~IS_INTEGRATED) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        else if (debug.test_num < TEST_NUM) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        debug.set_test_complete();
    endtask
endmodule 

`default_nettype wire

