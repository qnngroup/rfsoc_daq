`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"

module adc_intf_test #(parameter IS_INTEGRATED = 0)();
	localparam TIMEOUT = 1000;
	localparam TEST_NUM = 0;
	localparam int CLK_RATE_MHZ = 150;
    localparam MAN_SEED = 0;

    sim_util_pkg::debug debug = new(sim_util_pkg::DEBUG,TEST_NUM,"ADC_INTERFACE", IS_INTEGRATED); 

    logic clk, rst; 
    logic[`MEM_SIZE-1:0] fresh_bits; 
    logic[`MEM_SIZE-1:0][`WD_DATA_WIDTH-1:0] mem_map, read_resps; 
    logic[`CHAN_SAMPLES-1:0][`WD_DATA_WIDTH-1:0] exp_cmc_data; 
    logic[`SDC_SAMPLES-1:0][`WD_DATA_WIDTH-1:0] exp_sdc_data; 
    int total_errors = 0;
    int curr_err, seed; 
    Axis_IF #(`BUFF_TIMESTAMP_WIDTH) bufft_if(); 
    Axis_IF #(`BUFF_CONFIG_WIDTH) buffc_if();
    Axis_IF #(`CHANNEL_MUX_WIDTH) cmc_if();
    Axis_IF #(`SDC_DATA_WIDTH) sdc_if(); 

    ADC_Interface DUT(.clk(clk), .rst(rst),
                      .fresh_bits(fresh_bits),
                      .read_resps(read_resps),
                      .bufft(bufft_if.stream_in),
                      .buffc(buffc_if.stream_out),
                      .cmc(cmc_if.stream_out),
                      .sdc(sdc_if.stream_out));

	always #(0.5s/(CLK_RATE_MHZ*1_000_000)) clk = ~clk;
    initial begin
        if (~IS_INTEGRATED) begin 
            $dumpfile("adc_intf_test.vcd");
            $dumpvars(0,adc_intf_test); 
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
        {ps_clk,ps_rst} = 0;
        {dac_clk,dac_rst} = 0;
        repeat (5) @(posedge ps_clk);        
        debug.displayc($sformatf("\n\n### TESTING %s ###\n\n",debug.get_test_name()));
        seed = (MAN_SEED > 0)?  MAN_SEED : generate_rand_seed();
        debug.displayc($sformatf("Using Seed Value %0d",seed),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));
        $srandom(seed);
        debug.timeout_watcher(ps_clk,TIMEOUT);
        tb_i.init();

        // TEST 1
        debug.displayc($sformatf("%0d: Send 10 random commands to dac back to back",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.send_ps_cmds(debug, 10);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        if (~IS_INTEGRATED) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        else if (debug.test_num < TEST_NUM) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        debug.set_test_complete();
    endtask 
endmodule 

`default_nettype wire

