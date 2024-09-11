`default_nettype none
`timescale 1ns / 1ps

module top_test #(parameter IS_INTEGRATED = 0, parameter VERBOSE=sim_util_pkg::DEBUG)();
	localparam TIMEOUT = 8000;
	localparam TEST_NUM = 10;
	localparam int PS_CLK_RATE_MHZ = 150;
    localparam int DAC_CLK_RATE_MHZ = 384;
    localparam MAN_SEED = 0;
    localparam SKIP_LONG_TEST = 1;

    sim_util_pkg::debug debug = new(VERBOSE,TEST_NUM,"TOP", IS_INTEGRATED); 

    logic ps_clk, ps_rst;
    logic dac_clk, dac_rst; 
    logic[(axi_params_pkg::A_BUS_WIDTH)-1:0] raddr_packet, waddr_packet;
    logic[(axi_params_pkg::WD_BUS_WIDTH)-1:0] rdata_packet, wdata_packet;
    logic[(axi_params_pkg::RESP_DATA_WIDTH)-1:0] wresp_out, rresp_out; 
    logic raddr_valid_packet, waddr_valid_packet, wdata_valid_packet, rdata_valid_out, wresp_valid_out, rresp_valid_out, ps_wresp_rdy, ps_read_rdy; 
    logic[(daq_params_pkg::DMA_DATA_WIDTH)-1:0] pwl_tdata;
    logic[((daq_params_pkg::DMA_DATA_WIDTH)/8)-1:0] pwl_tkeep;
    logic pwl_tlast, pwl_tready, pwl_tvalid; 
    logic[(daq_params_pkg::DAC_NUM)-1:0][(daq_params_pkg::BATCH_WIDTH)-1:0] dac_batches;
    logic[(daq_params_pkg::DAC_NUM)-1:0] valid_dac_batches, dac_rdys;
    logic pl_rstn;
    logic[(daq_params_pkg::SDC_DATA_WIDTH)-1:0] sdc_data_out;
    logic[(daq_params_pkg::CHANNEL_MUX_WIDTH)-1:0] cmc_data_out;
    logic[(daq_params_pkg::BUFF_CONFIG_WIDTH)-1:0] buffc_data_out;
    logic sdc_valid_out, cmc_valid_out, buffc_valid_out;
    logic sdc_rdy_in, cmc_rdy_in, buffc_rdy_in;
    logic[(daq_params_pkg::BUFF_TIMESTAMP_WIDTH)-1:0] bufft_data_in;
    logic bufft_valid_in;
    logic bufft_rdy_out;
    int total_errors = 0;
    int dac_id; 
    int curr_err,seed,test_num;


    top_level
    dut_i(.ps_clk(ps_clk), .ps_rst(ps_rst), .pl_rstn(pl_rstn),
          .dac_clk(dac_clk), .dac_rst(dac_rst),
          .dac_rdys(dac_rdys), .dac_batches(dac_batches), .valid_dac_batches(valid_dac_batches),
          .raddr_packet(raddr_packet), .raddr_valid_packet(raddr_valid_packet),
          .waddr_packet(waddr_packet), .waddr_valid_packet(waddr_valid_packet),
          .wdata_packet(wdata_packet), .wdata_valid_packet(wdata_valid_packet),
          .rdata_packet(rdata_packet), .rdata_valid_out(rdata_valid_out),
          .ps_wresp_rdy(ps_wresp_rdy), .wresp_out(wresp_out), .wresp_valid_out(wresp_valid_out),
          .ps_read_rdy(ps_read_rdy), .rresp_out(rresp_out), .rresp_valid_out(rresp_valid_out),
          .sdc_rdy_in(sdc_rdy_in),
          .sdc_data_out(sdc_data_out), .sdc_valid_out(sdc_valid_out),
          .buffc_rdy_in(buffc_rdy_in),
          .buffc_data_out(buffc_data_out), .buffc_valid_out(buffc_valid_out),
          .cmc_rdy_in(cmc_rdy_in),
          .cmc_data_out(cmc_data_out), .cmc_valid_out(cmc_valid_out),
          .bufft_data_in(bufft_data_in), .bufft_valid_in(bufft_valid_in),
          .bufft_rdy_out(bufft_rdy_out),
          .pwl_tdata(pwl_tdata), .pwl_tkeep(pwl_tkeep), .pwl_tlast(pwl_tlast), .pwl_tvalid(pwl_tvalid), .pwl_tready(pwl_tready));

    top_tb 
    tb_i(.ps_clk(ps_clk), .ps_rst(ps_rst), .pl_rstn(pl_rstn),
         .dac_clk(dac_clk), .dac_rst(dac_rst),
         .dac_rdys(dac_rdys), .dac_batches(dac_batches), .valid_dac_batches(valid_dac_batches),
         .raddr_packet(raddr_packet), .raddr_valid_packet(raddr_valid_packet),
         .waddr_packet(waddr_packet), .waddr_valid_packet(waddr_valid_packet),
         .wdata_packet(wdata_packet), .wdata_valid_packet(wdata_valid_packet),
         .rdata_packet(rdata_packet), .rdata_valid_out(rdata_valid_out),
         .ps_wresp_rdy(ps_wresp_rdy), .wresp_out(wresp_out), .wresp_valid_out(wresp_valid_out),
         .ps_read_rdy(ps_read_rdy), .rresp_out(rresp_out), .rresp_valid_out(rresp_valid_out),
         .sdc_rdy_in(sdc_rdy_in),
         .sdc_data_out(sdc_data_out), .sdc_valid_out(sdc_valid_out),
         .buffc_rdy_in(buffc_rdy_in),
         .buffc_data_out(buffc_data_out), .buffc_valid_out(buffc_valid_out),
         .cmc_rdy_in(cmc_rdy_in),
         .cmc_data_out(cmc_data_out), .cmc_valid_out(cmc_valid_out),
         .bufft_data_in(bufft_data_in), .bufft_valid_in(bufft_valid_in),
         .bufft_rdy_out(bufft_rdy_out),
         .pwl_data(pwl_tdata), .pwl_keep(pwl_tkeep), .pwl_last(pwl_tlast), .pwl_valid(pwl_tvalid), .pwl_ready(pwl_tready),
         .run_pwl(dut_i.sys.dac_intf.sample_gen.run_pwl),.run_trig(dut_i.sys.dac_intf.sample_gen.run_trig_wav),.run_rand(dut_i.sys.dac_intf.sample_gen.run_shift_regs));

	always #(0.5s/(PS_CLK_RATE_MHZ*1_000_000)) ps_clk = ~ps_clk;
    always #(0.5s/(DAC_CLK_RATE_MHZ*1_000_000)) dac_clk = ~dac_clk;
    always_ff @(posedge ps_clk) test_num <= debug.test_num;
    initial begin
        if (~IS_INTEGRATED) begin 
            $dumpfile("top_test.vcd");
            $dumpvars(0,top_test); 
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
        tb_i.halt_osc = 1;
    endtask 

    task automatic run_tests();
        {ps_clk,ps_rst} = 0;
        {dac_clk,dac_rst} = 0;
        repeat (5) @(posedge ps_clk);        
        debug.displayc($sformatf("\n\n### TESTING %s ###\n\n",debug.get_test_name()));
        if (MAN_SEED > 0) begin
            seed = MAN_SEED;
            debug.displayc($sformatf("Using manually selected seed value %0d",seed),.msg_color(sim_util_pkg::RED),.msg_verbosity(sim_util_pkg::VERBOSE));
        end else begin
            seed = sim_util_pkg::generate_rand_seed();
            debug.displayc($sformatf("Using random seed value %0d",seed),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));            
        end
        $srandom(seed);
        debug.timeout_watcher(ps_clk,TIMEOUT);
        tb_i.init();
        repeat (20) @(posedge ps_clk);

        //TEST 1
        debug.displayc($sformatf("%0d: Write to reset",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.reset_test(debug);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        //TEST 2
        debug.displayc($sformatf("%0d: Ensure dac's valid goes high for random, triangle, and pwl waves",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.dac_test(debug);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        //TEST 3
        debug.displayc($sformatf("%0d: Ensure a 0 burst size results in continous running",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        if (SKIP_LONG_TEST == 0) tb_i.burst_test(debug,0);
        else debug.displayc("Skipping this test because it's long",.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        //TEST 4
        debug.displayc($sformatf("%0d: Ensure a constant burst size produces the correct burst",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.burst_test(debug, $urandom_range(20,700));
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        //TEST 5
        debug.displayc($sformatf("%0d: Run different modes sequentially",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.seq_run(debug);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        //TEST 6
        debug.displayc($sformatf("%0d: Have ps write to config registers, ensure correct value gets output from top",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.ps_config_write(debug);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        //TEST 7
        debug.displayc($sformatf("%0d: Have ps write to config registers, hold ready signal low for random time",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.ps_config_write_rdy_hold(debug);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        //TEST 8
        debug.displayc($sformatf("%0d: Write to exposed registers",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.rtl_exposed_reg_test(debug);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        //TEST 9
        debug.displayc($sformatf("%0d: Perform memory test",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.mem_test(debug);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 10
        debug.displayc($sformatf("%0d: Read from every address and ensure appropriate values are present on reset, as well as are written upon a ps write",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.mem_read_write_test(debug);
        combine_errors();
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));

        if (~IS_INTEGRATED) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        else if (debug.test_num < TEST_NUM) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        debug.set_test_complete();
    endtask 
endmodule 

`default_nettype wire

/*
    Trying to explain to myself why I made these changes, and what they are
    1. Talking about the skeleton for a general test
    2. Talking about the general probes I'm making in my system at a high level
    3. Explaining why what I was doing before wasnt working 
    4. Readability modularity and refactorability.

    1. GPIB for Linux driver, use pynq board to connect to a SRS 
    2. System wide changes
*/

