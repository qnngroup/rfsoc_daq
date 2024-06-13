`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"

module bram_intf_test #(parameter IS_INTEGRATED = 0)();
	localparam TIMEOUT = 1000;
	localparam TEST_NUM = 0;
	localparam int PS_CLK_RATE_HZ = 100_000_000;
    localparam BRAM_DEPTH = 500; 
    localparam BRAM_DELAY = 3; 
    localparam DATA_WIDTH = `WD_DATA_WIDTH;

    sim_util_pkg::debug debug = new(sim_util_pkg::DEBUG,TEST_NUM,"BRAM_INTERFACE", IS_INTEGRATED); 

    logic clk, rst; 
    int total_errors = 0;
    int curr_err,seed; 
    logic[$clog2(BRAM_DEPTH)-1:0] addr;
    logic[DATA_WIDTH-1:0] line_in;
    logic we, en;
    logic generator_mode, rst_gen_mode;
    logic next;
    logic[DATA_WIDTH-1:0] line_out;
    logic valid_line_out;
    logic[$clog2(BRAM_DEPTH)-1:0] generator_addr;
    logic write_rdy;

    bram_interface #(.DATA_WIDTH(DATA_WIDTH), .BRAM_DEPTH(BRAM_DEPTH), .BRAM_DELAY(BRAM_DELAY))
    dut_i(.clk(clk), .rst(rst),
          .addr(addr), .line_in(line_in),
          .we(we), .en(en), .generator_mode(generator_mode),
          .rst_gen_mode(rst_gen_mode), .next(next),
          .line_out(line_out), .valid_line_out(valid_line_out),
          .generator_addr(generator_addr), .write_rdy(write_rdy));

	always #(0.5s/PS_CLK_RATE_HZ) clk = ~clk;
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
        seed = generate_rand_seed();
        debug.displayc($sformatf("Using Seed Value %0d",seed),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));
        $srandom(seed);
        debug.timeout_watcher(clk,TIMEOUT);
        tb_i.init();
        repeat (20) @(posedge clk);

         // TEST 1
        debug.displayc($sformatf("%0d: Store and read one value",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.store_vals(debug, $urandom_range(-100,100), 2);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();
    endtask 
endmodule 

`default_nettype wire

