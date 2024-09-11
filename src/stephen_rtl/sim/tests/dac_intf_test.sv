`default_nettype none
`timescale 1ns / 1ps

import daq_params_pkg::DAC_NUM;
module dac_intf_test #(parameter IS_INTEGRATED = 0, parameter VERBOSE=sim_util_pkg::DEBUG)();
	localparam TIMEOUT = 1500;
	localparam TEST_NUM = 18;
	localparam int PS_CLK_RATE_MHZ = 150;
	localparam int DAC_CLK_RATE_MHZ = 384;
	localparam MAN_SEED = 53;

	sim_util_pkg::debug debug = new(VERBOSE,TEST_NUM,"DAC_INTERFACE",IS_INTEGRATED); 

	logic ps_clk, ps_rst, dac_clk, dac_rst; 
	logic[DAC_NUM-1:0] halts, dac_rdys, valid_dac_batches, save_pwl_wave_periods; 
	logic[DAC_NUM-1:0][(daq_params_pkg::PWL_PERIOD_SIZE)-1:0][(axi_params_pkg::DATAW)-1:0] pwl_wave_periods; 
	logic[DAC_NUM-1:0][$clog2(daq_params_pkg::SAMPLE_WIDTH)-1:0] scale_factor_ins;
	logic[DAC_NUM-1:0][(daq_params_pkg::BS_WIDTH)-1:0] dac_bs_ins;
	logic[DAC_NUM-1:0][(daq_params_pkg::BATCH_WIDTH)-1:0] dac_batches; 	
	logic[(mem_layout_pkg::MEM_SIZE)-1:0] fresh_bits; 
	logic[(mem_layout_pkg::MEM_SIZE)-1:0][(axi_params_pkg::DATAW)-1:0] read_resps; 
	int total_errors = 0;
	int curr_err,test_num, seed, halts_seen;
	int intLi [$];
	bit done_sending;
	int dac_id;
	Axis_IF #(daq_params_pkg::DMA_DATA_WIDTH, DAC_NUM) pwl_dmas_if();

	dac_intf_tb #(.MEM_SIZE(mem_layout_pkg::MEM_SIZE), .DATA_WIDTH(axi_params_pkg::DATAW), .BATCH_SIZE(daq_params_pkg::BATCH_SIZE), .DMA_DATA_WIDTH(daq_params_pkg::DMA_DATA_WIDTH), .MAX_DAC_BURST_SIZE(daq_params_pkg::MAX_DAC_BURST_SIZE), .BS_WIDTH(daq_params_pkg::BS_WIDTH))
	tb_i(.ps_clk(ps_clk), .ps_rst(ps_rst),
	     .dac_clk(dac_clk), .dac_rst(dac_rst),
	     .dac_batches(dac_batches), .valid_dac_batches(valid_dac_batches),
	     .dac_intf_rdys(dut_i.state_rdys), .pwl_rdys(dut_i.pwl_rdys), .fresh_bits(fresh_bits),
	     .read_resps(read_resps),
	     .scale_factor_ins(scale_factor_ins), .dac_bs_ins(dac_bs_ins), .halt_counters(dut_i.halt_counters),
	     .scale_factor_outs(dut_i.scale_factor_outs), .dac_bs_outs(dut_i.dac_bs_outs),
	     .halts(halts),
	     .dac_rdys(dac_rdys),
	     .dmas(pwl_dmas_if));

	DAC_Interface #(.DATAW(axi_params_pkg::DATAW), .SAMPLEW(daq_params_pkg::SAMPLE_WIDTH), .BS_WIDTH(daq_params_pkg::BS_WIDTH), .BATCH_WIDTH(daq_params_pkg::BATCH_WIDTH), .BATCH_SIZE(daq_params_pkg::BATCH_SIZE), .PWL_PERIOD_WIDTH(daq_params_pkg::PWL_PERIOD_WIDTH), .PWL_PERIOD_SIZE(daq_params_pkg::PWL_PERIOD_SIZE))
	dut_i(.ps_clk(ps_clk), .ps_rst(ps_rst),
	      .dac_clk(dac_clk), .dac_rst(dac_rst),
	      .fresh_bits(fresh_bits), .read_resps(read_resps),
	      .scale_factor_ins(scale_factor_ins), .dac_bs_ins(dac_bs_ins),
	      .halts(halts), .dac_rdys(dac_rdys),
	      .dac_batches(dac_batches), .valid_dac_batches(valid_dac_batches),
	      .save_pwl_wave_periods(save_pwl_wave_periods), .pwl_wave_periods(pwl_wave_periods),
	      .pwl_dmas_if(pwl_dmas_if));
	
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
            seed = sim_util_pkg::generate_rand_seed();
            debug.displayc($sformatf("Using random seed value %0d",seed),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));            
        end
        $srandom(seed);
        dac_id = seed%DAC_NUM;
        debug.displayc($sformatf("Inital dac targeted is %0d",dac_id),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));
     	debug.timeout_watcher(ps_clk,TIMEOUT);
        tb_i.init();
        repeat (20) @(posedge ps_clk);

        // TEST 1
        debug.displayc($sformatf("%0d: Run random samples",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
       	tb_i.send_rand_samples(debug,dac_id); 
       	debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
       	reset_errors();

        // TEST 2
        debug.displayc($sformatf("%0d: Halt, check for valid drop. Then count 30 halt signal transfers",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        debug.disp_test_part(1, valid_dac_batches[dac_id] == 1, "Valid should be high");
        tb_i.halt_dac(dac_id);
        repeat (20) @(posedge ps_clk);
        debug.disp_test_part(2, valid_dac_batches[dac_id] == 0, "Valid should have fallen");
        {halts_seen,done_sending} = 0;
        fork 
        	begin 
		        for (int i = 0; i < 30; i++) begin 
		        	halts[dac_id] <= 1; @(posedge ps_clk);  halts[dac_id] <= 0; @(posedge ps_clk); 
		        	while (~dut_i.ps_cmd_transfer_done[dac_id]) @(posedge ps_clk); 
		        end 
		        done_sending = 1;
		    end 
		    begin
		    	while (~done_sending) begin
		    		@(posedge dac_clk);
		    		if (dut_i.ps_halt_cmds[dac_id]) begin 
		    			debug.disp_test_part(halts_seen, 1, "");	
		    			halts_seen++; 
		    		end     		 
		    	end
		    end
		join 		
        debug.check_test(halts_seen == 30, .has_parts(1), .fail_msg($sformatf("Expected 30 halts, dac saw %0d",halts_seen)));
        reset_errors();

        // TEST 3
        debug.displayc($sformatf("%0d: Run triangle wave and check outputs (halt in middle)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.send_trig_wave(debug,5,dac_id);
        tb_i.halt_dac(dac_id);
        tb_i.send_trig_wave(debug,15,dac_id);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();
        // TEST 4
        debug.displayc($sformatf("%0d: Run pwl wave and check first 2 periods",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.send_pwl_wave(dac_id);
		tb_i.check_pwl_wave(debug,2, dac_id);
		repeat(100) @(posedge ps_clk);  
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 5
        debug.displayc($sformatf("%0d: Send dac config settings from ps_domain to dac_domain (no delay)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        tb_i.send_dac_configs({0,0},dac_id);
        debug.check_test(1, .has_parts(0));
        reset_errors();

         // TEST 6
        debug.displayc($sformatf("%0d: Send dac config settings from ps_domain to dac_domain (small delay)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        tb_i.send_dac_configs({1,3}, dac_id);
        debug.check_test(1, .has_parts(0));
        reset_errors();

         // TEST 7
        debug.displayc($sformatf("%0d: Send dac config settings from ps_domain to dac_domain (large delay)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        tb_i.send_dac_configs({20,40}, dac_id);
        debug.check_test(1, .has_parts(0));
        reset_errors();

        // TEST 8-15
        dac_id = 0; 
        repeat(DAC_NUM) begin 
	        debug.displayc($sformatf("%0d: Send a step pwl function (dac #%0d). Check 2 periods",debug.test_num, dac_id), .msg_verbosity(sim_util_pkg::VERBOSE));
	        curr_err = debug.get_error_count();
	        tb_i.send_step_pwl_wave(dac_id);
	        tb_i.check_pwl_wave(debug, 2, dac_id);
	        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
	        tb_i.halt_dac(dac_id);
	        dac_id++;
	        reset_errors();
	    end
	    
        // TEST 16
	    dac_id = 0;
        debug.displayc($sformatf("%0d: Scale down the step function (1, 2, 5, 15)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        intLi = {1, 2, 5, 15};
        foreach(intLi[i]) begin 
        	debug.displayc($sformatf("\nScale %0d:",intLi[i]),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));            
        	tb_i.scale_check(debug, intLi[i], dac_id);
        end 
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

		// TEST 17
        debug.displayc($sformatf("%0d: Check various burst sizes (1, 5, 150, 2321)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        intLi = {1, 5, 150, 2321};
        foreach(intLi[i]) begin 
        	debug.displayc($sformatf("\nBurst Size %0d:",intLi[i]),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));            
        	tb_i.burst_size_check(debug, intLi[i],i, dac_id);
        end 
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 18
        debug.displayc($sformatf("%0d: Check that the correct periods are saved across dacs",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        for (int i = 0; i < 8; i++) begin
        	tb_i.send_pwl_wave(i,i); 
        	tb_i.notify_dac(mem_layout_pkg::RUN_PWL_IDS[i], i);
        	while (1) begin
        		if (save_pwl_wave_periods[i] && pwl_wave_periods[i] != 0) break;
        		@(posedge ps_clk); 
        	end 
        	debug.disp_test_part(i, pwl_wave_periods[i] == tb_i.period_len,$sformatf("Period length for dac %0d should be %0d. Got %0d", i, tb_i.period_len, pwl_wave_periods[i]));
        	debug.reset_timeout(ps_clk);
        end        
        combine_errors();
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));

       	if (~IS_INTEGRATED) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        else if (debug.test_num < TEST_NUM) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        debug.set_test_complete();
    endtask 
endmodule 

	// logic[(daq_params_pkg::BATCH_WIDTH)-1:0] dac_batches0,dac_batches1,dac_batches2,dac_batches3,dac_batches4,dac_batches5,dac_batches6,dac_batches7;
	// assign dac_batches0 = dac_batches[0];
	// assign dac_batches1 = dac_batches[1];
	// assign dac_batches2 = dac_batches[2];
	// assign dac_batches3 = dac_batches[3];
	// assign dac_batches4 = dac_batches[4];
	// assign dac_batches5 = dac_batches[5];
	// assign dac_batches6 = dac_batches[6];
	// assign dac_batches7 = dac_batches[7];
	// logic valid_dac_batches0,valid_dac_batches1,valid_dac_batches2,valid_dac_batches3,valid_dac_batches4,valid_dac_batches5,valid_dac_batches6,valid_dac_batches7;
	// assign valid_dac_batches0 = valid_dac_batches[0];
	// assign valid_dac_batches1 = valid_dac_batches[1];
	// assign valid_dac_batches2 = valid_dac_batches[2];
	// assign valid_dac_batches3 = valid_dac_batches[3];
	// assign valid_dac_batches4 = valid_dac_batches[4];
	// assign valid_dac_batches5 = valid_dac_batches[5];
	// assign valid_dac_batches6 = valid_dac_batches[6];
	// assign valid_dac_batches7 = valid_dac_batches[7];

`default_nettype wire
