`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"

//Cannot perform bufft test here, write signals are propogated to system level. 
module adc_intf_test #(parameter IS_INTEGRATED = 0)();
	localparam TIMEOUT = 1500;
	localparam TEST_NUM = 8;
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
    Axis_IF #(`BUFF_TIMESTAMP_WIDTH) bufft(); 
    Axis_IF #(`BUFF_CONFIG_WIDTH) buffc();
    Axis_IF #(`CHANNEL_MUX_WIDTH) cmc();
    Axis_IF #(`SDC_DATA_WIDTH) sdc(); 

    ADC_Interface dut_i(.clk(clk), .rst(rst),
                        .fresh_bits(fresh_bits),
                        .read_resps(read_resps),
                        .bufft(bufft.stream_in),
                        .buffc(buffc.stream_out),
                        .cmc(cmc.stream_out),
                        .sdc(sdc.stream_out));
    
    adc_intf_tb #(.MEM_SIZE(`MEM_SIZE), .DATA_WIDTH(`WD_DATA_WIDTH))
    tb_i(.clk(clk), .adc_rdy(dut_i.state_rdy),
         .rst(rst),
         .fresh_bits(fresh_bits), .read_resps(read_resps),
         .bufft(bufft), .buffc(buffc), .cmc(cmc), .sdc(sdc));

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

    task automatic cmc_test(inout sim_util_pkg::debug debug, input bit write_all = 1, input bit signal_rdy = 1);
        tb_i.populate_wd_list(`CHAN_SAMPLES+1); 
        tb_i.write_addr(`CHAN_MUX_BASE_ID, .write_all(write_all));
        delay(clk, $urandom_range(2,100));
        debug.disp_test_part(1, cmc.valid == 1, "Valid should be high"); 
        debug.disp_test_part(2,cmc.data == read_resps[`CHAN_MUX_BASE_ID+:`CHAN_SAMPLES],$sformatf("Expected %h, got %h",cmc.data, read_resps[`CHAN_MUX_BASE_ID+:`CHAN_SAMPLES])); 
        if (signal_rdy) begin 
            `flash_signal(cmc.ready,clk); 
            debug.disp_test_part(3, cmc.valid == 0, "Valid should have fallen");
        end 
    endtask 
    task automatic buffc_test(inout sim_util_pkg::debug debug, input bit write_all = 1, input bit signal_rdy = 1);
        tb_i.populate_wd_list(1); 
        tb_i.write_addr(`BUFF_CONFIG_ID, .write_all(write_all));
        delay(clk, $urandom_range(2,100));
        debug.disp_test_part(1, buffc.valid == 1, "Valid should be high"); 
        debug.disp_test_part(2,buffc.data == read_resps[`BUFF_CONFIG_ID][0+:`BUFF_CONFIG_WIDTH],$sformatf("Expected %h, got %h",buffc.data,read_resps[`BUFF_CONFIG_ID][0+:`BUFF_CONFIG_WIDTH])); 
        if (signal_rdy) begin 
            `flash_signal(buffc.ready,clk); 
            debug.disp_test_part(3, buffc.valid == 0, "Valid should have fallen");
        end 
    endtask 
    task automatic sdc_test(inout sim_util_pkg::debug debug, input bit write_all = 1, input bit signal_rdy = 1);
        tb_i.populate_wd_list(`SDC_SAMPLES+1); 
        tb_i.write_addr(`SDC_BASE_ID, .write_all(write_all));
        delay(clk, $urandom_range(2,100));
        debug.disp_test_part(1, sdc.valid == 1, "Valid should be high"); 
        debug.disp_test_part(2,sdc.data == read_resps[`SDC_BASE_ID+:`SDC_SAMPLES],$sformatf("Expected %h, got %h",sdc.data, read_resps[`SDC_BASE_ID+:`SDC_SAMPLES])); 
        if (signal_rdy) begin 
            `flash_signal(sdc.ready,clk); 
            debug.disp_test_part(3, sdc.valid == 0, "Valid should have fallen");
        end 
    endtask 

    task automatic run_tests();
        {clk,rst} = 0;
        repeat (5) @(posedge clk);        
        debug.displayc($sformatf("\n\n### TESTING %s ###\n\n",debug.get_test_name()));
        seed = (MAN_SEED > 0)?  MAN_SEED : generate_rand_seed();
        debug.displayc($sformatf("Using Seed Value %0d",seed),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));
        $srandom(seed);
        debug.timeout_watcher(clk,TIMEOUT);
        tb_i.init();

        // TEST 1
        debug.displayc($sformatf("%0d: Retrieve channel mux register (hold for random time, ps_sends immediately)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        cmc_test(debug,.write_all(1));
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 2
        debug.displayc($sformatf("%0d: Retrieve channel mux register (hold for random time, ps_sends one at a time)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        cmc_test(debug,.write_all(0));
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 3
        debug.displayc($sformatf("%0d: Retrieve buff_config register (hold for random time, ps_sends immediately)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        buffc_test(debug,.write_all(1));
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 4
        debug.displayc($sformatf("%0d: Retrieve buff_config register (hold for random time, ps_sends one at a time)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        buffc_test(debug,.write_all(0));
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 5
        debug.displayc($sformatf("%0d: Retrieve sdc register (hold for random time, ps_sends immediately)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        sdc_test(debug,.write_all(1)); 
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 6
        debug.displayc($sformatf("%0d: Retrieve sdc register (hold for random time, ps_sends one at a time)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        sdc_test(debug,.write_all(0)); 
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 7
        debug.displayc($sformatf("%0d: Write to all special registers and ensure values are correct and valid remains high until ps is ready",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        sdc_test(debug,.write_all(0),.signal_rdy(0)); 
        buffc_test(debug,.write_all(0),.signal_rdy(0));
        cmc_test(debug,.write_all(0),.signal_rdy(0));
        delay(clk, $urandom_range(100,500)); 
        debug.disp_test_part(3, cmc.valid && sdc.valid && buffc.valid, "All valids should still be high");
        fork 
            begin `flash_signal(cmc.ready,clk) end 
            begin `flash_signal(sdc.ready,clk) end 
            begin `flash_signal(buffc.ready,clk) end 
        join
        debug.disp_test_part(4, ~cmc.valid && ~sdc.valid && ~buffc.valid, "All valids should have fallen");
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 8
        debug.displayc($sformatf("%0d: Write to all special registers and ensure values are correct and valid remains high until ps is ready (sequential ready pulses)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        sdc_test(debug,.write_all(0),.signal_rdy(0)); 
        buffc_test(debug,.write_all(0),.signal_rdy(0));
        cmc_test(debug,.write_all(0),.signal_rdy(0));
        delay(clk, $urandom_range(100,500)); 
        debug.disp_test_part(3, cmc.valid && sdc.valid && buffc.valid, "All valids should still be high");
        `flash_signal(cmc.ready,clk)
        debug.disp_test_part(4, ~cmc.valid && sdc.valid && buffc.valid, "Only cmc valid should have fallen");
        delay(clk, $urandom_range(10,30)); 
        `flash_signal(sdc.ready,clk)
        debug.disp_test_part(5, ~cmc.valid && ~sdc.valid && buffc.valid, "sdc and cmc valids should have fallen");
        delay(clk, $urandom_range(10,30));
        `flash_signal(buffc.ready,clk)
        debug.disp_test_part(6, ~cmc.valid && ~sdc.valid && ~buffc.valid, "All valids should have fallen");
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        if (~IS_INTEGRATED) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        else if (debug.test_num < TEST_NUM) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        debug.set_test_complete();
    endtask   
endmodule 

`default_nettype wire

//Oh did u guys have that convo already? With timmy