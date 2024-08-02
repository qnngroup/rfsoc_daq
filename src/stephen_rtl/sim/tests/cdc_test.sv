`default_nettype none
`timescale 1ns / 1ps



module cdc_test #(parameter IS_INTEGRATED = 0, parameter VERBOSE=sim_util_pkg::DEBUG)();
	localparam TIMEOUT = 1000;
	localparam TEST_NUM = 4; 
	localparam int PS_CLK_RATE_MHZ = 150;
    localparam int DAC_CLK_RATE_MHZ = 384;
    localparam MAN_SEED = 0;
    localparam PS_CMD_WIDTH = 271;
    localparam DAC_RSP_WIDTH = 65;

    sim_util_pkg::debug debug = new(VERBOSE,TEST_NUM,"CDC_DATA_HANDSHAKE", IS_INTEGRATED); 
    
    logic ps_clk, ps_rst; 
    logic dac_clk, dac_rst;
    logic[PS_CMD_WIDTH-1:0] ps_cmd_in, ps_cmd_out; 
    logic ps_cmd_valid_in, ps_cmd_valid_out, ps_cmd_transfer_rdy, ps_cmd_transfer_done;
    logic[DAC_RSP_WIDTH-1:0] dac_resp_in, dac_resp_out; 
    logic dac_resp_valid_in, dac_resp_valid_out, dac_resp_transfer_rdy, dac_resp_transfer_done;
    int total_errors = 0;
    int curr_err, seed; 
    int test_num; 

    data_handshake #(.DATA_WIDTH(PS_CMD_WIDTH))
    ps_to_dac(.clk_src(ps_clk), .rst_src(ps_rst),
              .clk_dst(dac_clk), .rst_dst(dac_rst),
              .data_in(ps_cmd_in), .valid_in(ps_cmd_valid_in),
              .data_out(ps_cmd_out), .valid_out(ps_cmd_valid_out),
              .rdy(ps_cmd_transfer_rdy), .done(ps_cmd_transfer_done));

    data_handshake #(.DATA_WIDTH(DAC_RSP_WIDTH))
    dac_to_ps(.clk_src(dac_clk), .rst_src(dac_rst),
              .clk_dst(ps_clk), .rst_dst(ps_rst),
              .data_in(dac_resp_in), .valid_in(dac_resp_valid_in),
              .data_out(dac_resp_out), .valid_out(dac_resp_valid_out),
              .rdy(dac_resp_transfer_rdy), .done(dac_resp_transfer_done));

    cdc_tb #(.PS_CMD_WIDTH(PS_CMD_WIDTH), .DAC_RSP_WIDTH(DAC_RSP_WIDTH))
    tb_i(.ps_clk(ps_clk), .ps_rst(ps_rst),
         .dac_clk(dac_clk), .dac_rst(dac_rst),
         .ps_cmd_out(ps_cmd_out), .ps_cmd_valid_out(ps_cmd_valid_out), .ps_cmd_transfer_rdy(ps_cmd_transfer_rdy), .ps_cmd_transfer_done(ps_cmd_transfer_done),
         .dac_resp_out(dac_resp_out), .dac_resp_valid_out(dac_resp_valid_out), .dac_resp_transfer_rdy(dac_resp_transfer_rdy), .dac_resp_transfer_done(dac_resp_transfer_done),
         .ps_cmd_in(ps_cmd_in), .ps_cmd_valid_in(ps_cmd_valid_in), 
         .dac_resp_in(dac_resp_in), .dac_resp_valid_in(dac_resp_valid_in));

	always #(0.5s/(PS_CLK_RATE_MHZ*1_000_000)) ps_clk = ~ps_clk;
    always #(0.5s/(DAC_CLK_RATE_MHZ*1_000_000)) dac_clk = ~dac_clk;
    always_ff @(posedge ps_clk) test_num <= debug.test_num;

    initial begin
        if (~IS_INTEGRATED) begin 
            $dumpfile("cdc_test.vcd");
            $dumpvars(0,cdc_test); 
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
        if (MAN_SEED > 0) begin
            seed = MAN_SEED;
            debug.displayc($sformatf("Using manually selected seed value %0d",seed),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));
        end else begin
            seed = sim_util_pkg::generate_rand_seed();
            debug.displayc($sformatf("Using random seed value %0d",seed),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));            
        end
        $srandom(seed);
        debug.timeout_watcher(ps_clk,TIMEOUT);
        tb_i.init();
        repeat (20) @(posedge ps_clk);

        // TEST 1
        debug.displayc($sformatf("%0d: Send 10 random commands to dac back to back",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.send_ps_cmds(debug, 10);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 2
        debug.displayc($sformatf("%0d: Send 10 random commands to dac (random delays)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.send_ps_cmds(debug, 10, .rand_wait(1));
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 3
        debug.displayc($sformatf("%0d: Send 10 random replies to ps back to back",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.send_dac_resp(debug, 10);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 4
        debug.displayc($sformatf("%0d: Send 10 random replies to ps (with delays)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.send_dac_resp(debug, 10, .rand_wait(1));
        combine_errors();
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        

        if (~IS_INTEGRATED) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        else if (debug.test_num < TEST_NUM) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        debug.set_test_complete();
    endtask 
endmodule 

`default_nettype wire

