`default_nettype none
`timescale 1ns / 1ps

module bram_intf_test #(parameter IS_INTEGRATED = 0, parameter VERBOSE=sim_util_pkg::DEBUG)();
	localparam TIMEOUT = 5000;
	localparam TEST_NUM = 7;
	localparam int CLK_RATE_MHZ = 150;
    localparam MAN_SEED = 0; 
    localparam BRAM_DEPTH = 100; 
    localparam BRAM_DELAY = 3; 
    localparam DATAW = daq_params_pkg::DMA_DATA_WIDTH;

    sim_util_pkg::debug debug = new(VERBOSE,TEST_NUM,"BRAM_INTERFACE", IS_INTEGRATED); 

    logic clk, rst; 
    int total_errors = 0;
    int curr_err,seed; 
    logic[$clog2(BRAM_DEPTH)-1:0] addr;
    logic[DATAW-1:0] line_in;
    logic we, en;
    logic generator_mode, rst_gen_mode;
    logic next;
    logic[DATAW-1:0] line_out;
    logic valid_line_out;
    logic[$clog2(BRAM_DEPTH)-1:0] generator_addr;
    logic write_rdy;

    bram_interface #(.DATA_WIDTH(DATAW), .BRAM_DEPTH(BRAM_DEPTH), .BRAM_DELAY(BRAM_DELAY))
    dut_i(.clk(clk), .rst(rst),
          .addr(addr), .line_in(line_in),
          .we(we), .en(en), .generator_mode(generator_mode),
          .rst_gen_mode(rst_gen_mode), .next(next),
          .line_out(line_out), .valid_line_out(valid_line_out),
          .generator_addr(generator_addr), .write_rdy(write_rdy));

    bram_intf_tb #(.DATA_WIDTH(DATAW), .BRAM_DEPTH(BRAM_DEPTH))
    tb_i(.clk(clk),
         .line_out(line_out), .valid_line_out(valid_line_out),
         .generator_addr(generator_addr), .write_rdy(write_rdy),
         .rst(rst),
         .addr(addr), .line_in(line_in), .we(we), .en(en),
         .generator_mode(generator_mode), .rst_gen_mode(rst_gen_mode), .next(next));


	always #(0.5s/(CLK_RATE_MHZ*1_000_000)) clk = ~clk;
	initial begin
        if (~IS_INTEGRATED) begin 
            $dumpfile("bram_intf_test.vcd");
            $dumpvars(0,bram_intf_test); 
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
        debug.displayc($sformatf("%0d: Store and read one value (20 cycles)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.write_rands(1);
        tb_i.check_bram_vals(debug,20); 
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 2
        debug.displayc($sformatf("%0d: Store and read half a buffer length (10 cycles)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.write_rands((BRAM_DELAY+1)/2);
        tb_i.check_bram_vals(debug,10); 
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 3
        debug.displayc($sformatf("%0d: Store and read half a full buffer length (10 cycles)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.write_rands(BRAM_DELAY+1);
        tb_i.check_bram_vals(debug,10); 
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 4
        debug.displayc($sformatf("%0d: Store and read half bram length (3 cycles)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.write_rands(BRAM_DEPTH/2);
        tb_i.check_bram_vals(debug,3); 
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 5
        debug.displayc($sformatf("%0d: Store and read full bram length (3 cycles)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.write_rands(BRAM_DEPTH);
        tb_i.check_bram_vals(debug,3); 
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 6
        debug.displayc($sformatf("%0d: Store and read full bram length (3 cycles, osc next)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.write_rands(BRAM_DEPTH);
        tb_i.check_bram_vals(debug,3,.osc_next(1)); 
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 7
        debug.displayc($sformatf("%0d: Reset gen_mode and restart prev test",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        sim_util_pkg::flash_signal(rst_gen_mode,clk);  
        tb_i.check_bram_vals(debug,3,.osc_next(1)); 
        combine_errors();
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));

        if (~IS_INTEGRATED) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        else if (debug.test_num < TEST_NUM) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        debug.set_test_complete();
    endtask 
endmodule 

`default_nettype wire

