`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"

module dac_intf_test #(parameter IS_INTEGRATED = 0)();
	localparam TIMEOUT = 1500;
	localparam TEST_NUM = 10;
	localparam int PS_CLK_RATE_MHZ = 150;
	localparam int DAC_CLK_RATE_MHZ = 384;
	localparam MAN_SEED = 0;
	localparam DATA_WIDTH = `WD_DATA_WIDTH;
	localparam BATCH_SIZE = `BATCH_WIDTH/DATA_WIDTH; 

	sim_util_pkg::debug debug = new(sim_util_pkg::DEBUG,TEST_NUM,"DAC_INTERFACE",IS_INTEGRATED); 

	logic ps_clk, ps_rst, dac_clk, dac_rst; 
	logic halt, dac0_rdy,valid_dac_batch; 
	logic[$clog2(DATA_WIDTH)-1:0] scale_factor_in;
	logic[$clog2(`MAX_DAC_BURST_SIZE):0] dac_bs_in;
	logic[`BATCH_WIDTH-1:0] dac_batch; 
	
	logic[`MEM_SIZE-1:0] fresh_bits; 
	logic[`MEM_SIZE-1:0][DATA_WIDTH-1:0] read_resps; 
	int total_errors = 0;
	int curr_err,test_num, seed, halts_seen;
	int intLi [$];
	bit done_sending;
	Axis_IF #(`DMA_DATA_WIDTH) pwl_dma_if();

	dac_intf_tb #(.MEM_SIZE(`MEM_SIZE), .DATA_WIDTH(DATA_WIDTH), .BATCH_SIZE(BATCH_SIZE), .DMA_DATA_WIDTH(`DMA_DATA_WIDTH), .MAX_DAC_BURST_SIZE(`MAX_DAC_BURST_SIZE))
	tb_i(.ps_clk(ps_clk), .ps_rst(ps_rst),
	     .dac_clk(dac_clk), .dac_rst(dac_rst),
	     .dac_batch(dac_batch), .valid_dac_batch(valid_dac_batch),
	     .dac_intf_rdy(dut_i.state_rdy), .pwl_rdy(dut_i.pwl_rdy), .fresh_bits(fresh_bits),
	     .read_resps(read_resps),
	     .scale_factor_in(scale_factor_in), .dac_bs_in(dac_bs_in), .halt_counter(dut_i.sample_gen.halt_counter),
	     .scale_factor_out(dut_i.scale_factor_out), .dac_bs_out(dut_i.dac_bs_out),
	     .halt(halt),
	     .dma(pwl_dma_if));

	DAC_Interface
	dut_i(.ps_clk(ps_clk), .ps_rst(ps_rst),
	      .dac_clk(dac_clk), .dac_rst(dac_rst),
	      .fresh_bits(fresh_bits), .read_resps(read_resps),
	      .scale_factor_in(scale_factor_in), .dac_bs_in(dac_bs_in),
	      .halt(halt), .dac0_rdy(dac0_rdy),
	      .dac_batch(dac_batch), .valid_dac_batch(valid_dac_batch),
	      .pwl_dma_if(pwl_dma_if));
			
	assign dac0_rdy = 1;	
	always_ff @(posedge ps_clk) test_num <= debug.test_num;
	always #(0.5s/(PS_CLK_RATE_MHZ*1_000_000)) ps_clk = ~ps_clk;
	always #(0.5s/(DAC_CLK_RATE_MHZ*1_000_000)) dac_clk = ~dac_clk;
	initial begin
		if (~IS_INTEGRATED) begin 
	        $dumpfile("dac_intf_test.vcd");
	        $dumpvars(0,dac_intf_test); 
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
        {dac_clk, dac_rst} = 0; 
     	repeat (5) @(posedge ps_clk);
        debug.displayc($sformatf("\n\n### TESTING %s ###\n\n",debug.get_test_name()));
        if (MAN_SEED > 0) begin
            seed = MAN_SEED;
            debug.displayc($sformatf("Using manually selected seed value %0d",seed),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));
        end else begin
            seed = generate_rand_seed();
            debug.displayc($sformatf("Using random seed value %0d",seed),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));            
        end
        $srandom(seed);
     	debug.timeout_watcher(ps_clk,TIMEOUT);
        tb_i.init();
        repeat (20) @(posedge ps_clk);

        // TEST 1
        debug.displayc($sformatf("%0d: Run random samples",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
       	tb_i.send_rand_samples(debug); 
       	debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));

        // TEST 2
        debug.displayc($sformatf("%0d: Halt, check for valid drop. Then count 30 halt signal transfers",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        debug.disp_test_part(1, valid_dac_batch == 1, "Valid should be high");
        tb_i.halt_dac();
        repeat (20) @(posedge ps_clk);
        debug.disp_test_part(2, valid_dac_batch == 0, "Valid should have fallen");
        {halts_seen,done_sending} = 0;
        fork 
        	begin 
		        for (int i = 0; i < 30; i++) begin 
		        	halt <= 1; @(posedge ps_clk);  halt <= 0; @(posedge ps_clk); 
		        	while (~dut_i.ps_cmd_transfer_done) @(posedge ps_clk); 
		        end 
		        done_sending = 1;
		    end 
		    begin
		    	while (~done_sending) begin
		    		@(posedge dac_clk);
		    		if (dut_i.sample_gen.ps_halt_cmd) begin 
		    			debug.disp_test_part(halts_seen, 1, "");	
		    			halts_seen++; 
		    		end     		 
		    	end
		    end
		join 		
        debug.check_test(halts_seen == 30, .has_parts(1), .fail_msg($sformatf("Expected 30 halts, dac saw %0d",halts_seen)));

        // TEST 3
        debug.displayc($sformatf("%0d: Run triangle wave, and check outputs (halt in middle)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.send_trig_wave(debug,5);
        tb_i.halt_dac();
        tb_i.send_trig_wave(debug,15);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 4
        debug.displayc($sformatf("%0d: Run pwl wave and check first 2 periods",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.send_pwl_wave();
		tb_i.check_pwl_wave(debug,2);  
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 5
        debug.displayc($sformatf("%0d: Send dac config settings from ps_domain to dac_domain (no delay)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        tb_i.send_dac_configs({0,0});
        debug.check_test(1, .has_parts(0));
        reset_errors();

         // TEST 6
        debug.displayc($sformatf("%0d: Send dac config settings from ps_domain to dac_domain (small delay)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        tb_i.send_dac_configs({1,3});
        debug.check_test(1, .has_parts(0));
        reset_errors();

         // TEST 7
        debug.displayc($sformatf("%0d: Send dac config settings from ps_domain to dac_domain (large delay)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        tb_i.send_dac_configs({20,40});
        debug.check_test(1, .has_parts(0));
        reset_errors();

        // TEST 8
        debug.displayc($sformatf("%0d: Send a step pwl function. Check 2 periods",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.send_step_pwl_wave();
        tb_i.check_pwl_wave(debug,2);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 9
        debug.displayc($sformatf("%0d: Scale down the step function (1, 2, 5, 15)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        intLi = {1, 2, 5, 15};
        foreach(intLi[i]) begin 
        	debug.displayc($sformatf("\nScale %0d:",intLi[i]),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));            
        	tb_i.scale_check(debug, intLi[i]);
        end 
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

		// TEST 10
        debug.displayc($sformatf("%0d: Check various burst sizes (1, 5, 150, 2321)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        intLi = {1, 5, 150, 2321};
        foreach(intLi[i]) begin 
        	debug.displayc($sformatf("\nBurst Size %0d:",intLi[i]),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));            
        	tb_i.burst_size_check(debug, intLi[i],i);
        end 
        combine_errors();
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));


       	if (~IS_INTEGRATED) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        else if (debug.test_num < TEST_NUM) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        debug.set_test_complete();
    endtask 
endmodule 

`default_nettype wire

