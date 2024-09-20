`default_nettype none
`timescale 1ns / 1ps

module pwl_test #(parameter IS_INTEGRATED = 0, parameter VERBOSE=sim_util_pkg::DEBUG)();
	localparam TIMEOUT = 10000;
	localparam TEST_NUM = 42;
	localparam int CLK_RATE_HZ = 100_000_000;
    localparam MAN_SEED = 0;
    
    logic clk, rst; 
    logic halt, run_pwl, pwl_generator_rdy;
    logic[(2*axi_params_pkg::DATAW)-1:0] pwl_wave_period;
    logic valid_pwl_wave_period;
    logic[(daq_params_pkg::BATCH_SIZE)-1:0][(daq_params_pkg::SAMPLE_WIDTH)-1:0] batch_out;
    logic valid_batch_out;
    int curr_err, test_num, seed; 
    int total_errors = 0;
    string test_str;
    bit is_fract,is_neg,long_wave,osc_valid;
    int osc_delay_range [2]; 

    Axis_IF #(daq_params_pkg::DMA_DATA_WIDTH) pwl_dma(); 

    sim_util_pkg::debug debug = new(VERBOSE,TEST_NUM,"PWL", IS_INTEGRATED); 

    pwl_generator #(.DMA_DATA_WIDTH(daq_params_pkg::DMA_DATA_WIDTH), .SAMPLE_WIDTH(daq_params_pkg::SAMPLE_WIDTH), .BATCH_SIZE(daq_params_pkg::BATCH_SIZE), .SPARSE_BRAM_DEPTH(daq_params_pkg::SPARSE_BRAM_DEPTH), .DENSE_BRAM_DEPTH(daq_params_pkg::DENSE_BRAM_DEPTH), .PWL_PERIOD_WIDTH(daq_params_pkg::PWL_PERIOD_WIDTH))
    dut_i(.clk(clk), .rst(rst),
          .halt(halt), .run(run_pwl), .pwl_generator_rdy(pwl_generator_rdy),
          .pwl_wave_period(pwl_wave_period), .valid_pwl_wave_period(valid_pwl_wave_period),
          .batch_out(batch_out), .valid_batch_out(valid_batch_out),
          .dma(pwl_dma));

    pwl_tb #(.SAMPLE_WIDTH(daq_params_pkg::SAMPLE_WIDTH), .DMA_DATA_WIDTH(daq_params_pkg::DMA_DATA_WIDTH), .BATCH_SIZE(daq_params_pkg::BATCH_SIZE))
    tb_i(.clk(clk), .rst(rst),
         .pwl_generator_rdy(pwl_generator_rdy),
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

        // TESTS 1-12
        for (int i = 0; i < 4; i++) begin
            {is_fract,is_neg} = {2{i}}; 
            case(i)
                0: test_str = "positive whole slope";
                1: test_str = "negative whole slope";
                2: test_str = "positive fractional slope";
                3: test_str = "negative fractional slope";
            endcase 

            // TEST i+0
            debug.displayc($sformatf("%0d: Run a single batch wave (sparse, 5 periods, %s)",debug.test_num,test_str), .msg_verbosity(sim_util_pkg::VERBOSE));
            curr_err = debug.get_error_count();
            tb_i.send_single_batch(.is_sparse(1), .is_fract(is_fract), .is_neg(is_neg)); 
            repeat($urandom_range(10,30)) @(posedge clk);
            debug.disp_test_part(1,valid_batch_out == 0 && valid_pwl_wave_period == 0,"There shouldn't yet be valid batches or periods");
            tb_i.check_pwl_wave(debug,5);
            debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
            reset_errors();

            // TEST i+1
            debug.displayc($sformatf("%0d: Check wave period (sparse, %s)",debug.test_num,test_str), .msg_verbosity(sim_util_pkg::VERBOSE)); 
            debug.check_test(valid_pwl_wave_period == 1 && pwl_wave_period == 1, .has_parts(0), .fail_msg("Wave period should be valid and 1"));
            reset_errors();

            // TEST i+2
            debug.displayc($sformatf("%0d: Halt, confirm a full period, halt again (sparse, %s)",debug.test_num,test_str), .msg_verbosity(sim_util_pkg::VERBOSE));  
            tb_i.halt_pwl();
            while (valid_batch_out) @(posedge clk); 
            tb_i.check_pwl_wave(debug,1); 
            tb_i.halt_pwl();
            while (valid_batch_out) @(posedge clk); 
            debug.check_test(1'b1, .has_parts(1));
            reset_errors(); 
        end 

        // TESTS 13-24
        for (int i = 0; i < 4; i++) begin
            {is_fract,is_neg} = {2{i}}; 
            
            //TEST 13+i+0
            debug.displayc($sformatf("%0d: Run a single batch wave (dense, 5 periods, dense ex #%0d)",debug.test_num,i), .msg_verbosity(sim_util_pkg::VERBOSE));
            curr_err = debug.get_error_count();
            tb_i.send_single_batch(.is_sparse(0), .is_fract(is_fract), .is_neg(is_neg)); 
            repeat($urandom_range(10,30)) @(posedge clk);
            debug.disp_test_part(1,valid_batch_out == 0 && valid_pwl_wave_period == 0,"There shouldn't yet be valid batches or periods");
            tb_i.check_pwl_wave(debug,5);
            debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
            reset_errors();
        
            // TEST 13+i+1
            debug.displayc($sformatf("%0d: Check wave period dense ex #%0d)",debug.test_num,i), .msg_verbosity(sim_util_pkg::VERBOSE)); 
            debug.check_test(valid_pwl_wave_period == 1 && pwl_wave_period == 1, .has_parts(0));
            reset_errors();

            // TEST 13+i+2
            debug.displayc($sformatf("%0d: Halt, confirm a full period, halt again dense ex #%0d)",debug.test_num,i), .msg_verbosity(sim_util_pkg::VERBOSE));  
            tb_i.halt_pwl();
            while (valid_batch_out) @(posedge clk); 
            tb_i.check_pwl_wave(debug,1); 
            tb_i.halt_pwl();
            while (valid_batch_out) @(posedge clk); 
            debug.check_test(1'b1, .has_parts(0));
            reset_errors();
        end 

        // TESTS 25-42
        for (int i = 0; i < 6; i++) begin            
            case(i)
                0: begin
                    {long_wave, osc_valid} = {1'b0, 1'b0};
                    osc_delay_range = {0,0};
                end
                1: begin
                    {long_wave, osc_valid} = {1'b0, 1'b1};
                    osc_delay_range = {0,2};
                end
                2: begin
                    {long_wave, osc_valid} = {1'b0, 1'b1};
                    osc_delay_range = {20,50};
                end
                3: begin
                    {long_wave, osc_valid} = {1'b1, 1'b0};
                    osc_delay_range = {0,0};
                end
                4: begin
                    {long_wave, osc_valid} = {1'b1, 1'b1};
                    osc_delay_range = {0,2};
                end
                5: begin
                    {long_wave, osc_valid} = {1'b1, 1'b1};
                    osc_delay_range = {20,50};
                end
            endcase


            case(i)
                0: test_str = "medium wave, const dma valid";
                1: test_str = "medium wave, oscillating dma valid (short delay)";
                2: test_str = "medium wave, oscillating dma valid (long delay)";
                3: test_str = "long wave, const dma valid";
                4: test_str = "long wave, oscillating dma valid (short delay)";
                5: test_str = "long wave, oscillating dma valid (long delay)";
            endcase 

            // TEST 25+i+0
            debug.displayc($sformatf("%0d: Run a full wave, check 3 periods (%s)",debug.test_num,test_str), .msg_verbosity(sim_util_pkg::VERBOSE));  
            curr_err = debug.get_error_count();
            tb_i.send_pwl_wave(.long_wave(long_wave),.osc_valid(osc_valid),.osc_delay_range(osc_delay_range));
            debug.disp_test_part(1,valid_batch_out == 0 && valid_pwl_wave_period == 0,"There shouldn't yet be valid batches or periods");
            tb_i.check_pwl_wave(debug,3); 
            debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
            reset_errors();

            // TEST 25+i+1
            debug.displayc($sformatf("%0d: Check wave period (%s))",debug.test_num,test_str), .msg_verbosity(sim_util_pkg::VERBOSE)); 
            debug.check_test(valid_pwl_wave_period == 1 && pwl_wave_period == tb_i.period_len, .has_parts(0));
            reset_errors();

            // TEST 25+i+2
            debug.displayc($sformatf("%0d: Halt, confirm a full period, halt again dense ex #%0d)",debug.test_num,i), .msg_verbosity(sim_util_pkg::VERBOSE));  
            tb_i.halt_pwl();
            while (valid_batch_out) @(posedge clk); 
            tb_i.check_pwl_wave(debug,1); 
            tb_i.halt_pwl();
            while (valid_batch_out) @(posedge clk); 

            if (i == 5) begin
                combine_errors();
                debug.check_test(1'b1, .has_parts(0));
            end else begin 
                debug.check_test(1'b1, .has_parts(0));
                reset_errors();
            end 
        end 

        if (~IS_INTEGRATED) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        else if (debug.test_num < TEST_NUM) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        debug.set_test_complete();
    endtask
endmodule 

`default_nettype wire

