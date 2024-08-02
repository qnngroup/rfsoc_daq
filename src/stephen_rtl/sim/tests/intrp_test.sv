`default_nettype none
`timescale 1ns / 1ps

module intrp_test #(parameter IS_INTEGRATED = 0, parameter VERBOSE=sim_util_pkg::DEBUG)();
	localparam TIMEOUT = 1000;
	localparam TEST_NUM = 6;
	localparam int CLK_RATE_MHZ = 150;
    localparam MAN_SEED = 0;
    
    logic clk; 
    logic[(2*(daq_params_pkg::SAMPLE_WIDTH))-1:0] x,slope; 
    logic[(daq_params_pkg::BATCH_SIZE)-1:0][(daq_params_pkg::SAMPLE_WIDTH)-1:0] intrp_batch;
    int total_errors = 0;
    int curr_err,seed;
    real float;
    
    sim_util_pkg::debug debug = new(VERBOSE,TEST_NUM,"INTERPOLATER", IS_INTEGRATED); 

    interpolater #(.SAMPLE_WIDTH(daq_params_pkg::SAMPLE_WIDTH), .BATCH_SIZE(daq_params_pkg::BATCH_SIZE))
    dut_i(.clk(clk),
          .x(x), .slope(slope),
          .intrp_batch(intrp_batch));

    intrp_tb #(.BATCH_SIZE(daq_params_pkg::BATCH_SIZE), .SAMPLE_WIDTH(daq_params_pkg::SAMPLE_WIDTH), .INTERPOLATER_DELAY(daq_params_pkg::INTERPOLATER_DELAY), .M(daq_params_pkg::SAMPLE_WIDTH), .N(daq_params_pkg::SAMPLE_WIDTH))
    tb_i(.clk(clk),
        .slopet(dut_i.slopet),
        .xpslopet(dut_i.xpslopet),
        .intrp_batch(intrp_batch),
        .x(x), .slope(slope));

	always #(0.5s/(CLK_RATE_MHZ*1_000_000)) clk = ~clk;
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
        clk = 0;
        repeat (5) @(posedge clk);        
        debug.displayc($sformatf("\n\n### TESTING %s ###\n\n",debug.get_test_name()));
        if (MAN_SEED > 0) begin
            seed = MAN_SEED;
            debug.displayc($sformatf("Using manually selected seed value %0d",seed),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));
        end else begin
            seed = sim_util_pkg::generate_rand_seed();
            debug.displayc($sformatf("Using random seed value %0d",seed),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));            
        end
        $srandom(seed);
        debug.timeout_watcher(clk,TIMEOUT);
        tb_i.init();
        repeat (20) @(posedge clk);


        // TEST 1
        debug.displayc($sformatf("%0d: Positive whole slope",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.check_intrped_batch(debug, $urandom_range(-16'h7500,16'h7500), 2);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 2
        debug.displayc($sformatf("%0d: Negative whole slope",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.check_intrped_batch(debug, $urandom_range(-16'h7500,16'h7500), -2);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 3
        debug.displayc($sformatf("%0d: Positive fractional slope",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.check_intrped_batch(debug, $urandom_range(-16'h7500,16'h7500), 0.5);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 4
        debug.displayc($sformatf("%0d: Negative fractional slope",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.check_intrped_batch(debug, $urandom_range(-16'h7500,16'h7500), -0.5);        
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        

        //TEST 5
        debug.displayc($sformatf("%0d: 30 random slopes",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        repeat(30) tb_i.check_intrped_batch(debug, $urandom_range(-16'h7500,16'h7500), tb_i.gen_rand_real({-100,100}));
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        //TEST 6
        debug.displayc($sformatf("%0d: Test 30 slope bursts",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.check_slope_bursts(debug,30);
        combine_errors();        
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));

        if (~IS_INTEGRATED) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        else if (debug.test_num < TEST_NUM) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        debug.set_test_complete();
    endtask 

endmodule 

`default_nettype wire

