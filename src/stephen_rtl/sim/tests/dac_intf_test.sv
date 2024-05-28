`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"

module dac_intf_test();
	localparam TIMEOUT = 1000;
	localparam TEST_NUM = 4;
	localparam int PS_CLK_RATE_MHZ = 150;
	localparam int DAC_CLK_RATE_MHZ = 384;
	localparam DATA_WIDTH = `WD_DATA_WIDTH;
	localparam BATCH_SIZE = `BATCH_WIDTH/DATA_WIDTH; 

	sim_util_pkg::debug debug = new(sim_util_pkg::DEBUG,TEST_NUM,"DAC_INTERFACE"); 

	logic ps_clk, ps_rst, dac_clk, dac_rst; 
	logic halt, dac0_rdy,valid_dac_batch; 
	logic[$clog2(DATA_WIDTH)-1:0] scale_factor_in;
	logic[`BATCH_WIDTH-1:0] dac_batch, sample; 
	logic[BATCH_SIZE-1:0][DATA_WIDTH-1:0] rand_sample_batch;
	logic[`MEM_SIZE-1:0] fresh_bits; 
	logic[`MEM_SIZE-1:0][DATA_WIDTH-1:0] read_resps; 
	int total_errors = 0;
	int curr_err;
	Axis_IF #(`DMA_DATA_WIDTH) pwl_dma_if();

	dac_intf_tb #(.MEM_SIZE(`MEM_SIZE), .DATA_WIDTH(DATA_WIDTH), .BATCH_SIZE(BATCH_SIZE), .DMA_DATA_WIDTH(`DMA_DATA_WIDTH))
	tb_i(.ps_clk(ps_clk), .ps_rst(ps_rst),
	     .dac_clk(dac_clk), .dac_rst(dac_rst),
	     .dac_batch(dac_batch), .valid_dac_batch(valid_dac_batch),
	     .dac_intf_rdy(dut_i.state_rdy), .fresh_bits(fresh_bits),
	     .read_resps(read_resps),
	     .scale_factor_in(scale_factor_in), .halt(halt),
	     .dac0_rdy(dac0_rdy), .dma(pwl_dma_if));

	DAC_Interface
	dut_i(.ps_clk(ps_clk), .ps_rst(ps_rst),
	      .dac_clk(dac_clk), .dac_rst(dac_rst),
	      .fresh_bits(fresh_bits), .read_resps(read_resps),
	      .scale_factor_in(scale_factor_in),
	      .halt(halt), .dac0_rdy(dac0_rdy),
	      .dac_batch(dac_batch), .valid_dac_batch(valid_dac_batch),
	      .pwl_dma_if(pwl_dma_if));

	 task automatic reset_errors();
        total_errors += debug.get_error_count();
        debug.clear_error_count(); 
    endtask 
	
	always #(0.5s/(PS_CLK_RATE_MHZ*1_000_000)) ps_clk = ~ps_clk;
	always #(0.5s/(DAC_CLK_RATE_MHZ*1_000_000)) dac_clk = ~dac_clk;
	always_comb begin 
		for (int i = 0; i < BATCH_SIZE; i++) rand_sample_batch[i] = 16'hBEEF+i;
	end 

	initial begin
        $dumpfile("dac_intf_test.vcd");
        $dumpvars(0,dac_intf_test); 
        {ps_clk,ps_rst} = 0;
        {dac_clk, dac_rst} = 0; 
     	repeat (20) @(posedge ps_clk);
        debug.displayc($sformatf("\n\n### TESTING %s ###\n\n",debug.get_test_name()));
     	debug.timeout_watcher(ps_clk,TIMEOUT);
        tb_i.init();
        repeat (5) @(posedge ps_clk);

        // TEST 1
        debug.displayc($sformatf("%0d: Run random samples",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
       	tb_i.send_rand_samples(sample); 
       	debug.check_test(sample == rand_sample_batch, .has_parts(0));
        reset_errors();

        // TEST 2
        debug.displayc($sformatf("%0d: Halt, check for valid drop",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        tb_i.halt_dac();
        debug.check_test(1'b1, .has_parts(0));
        reset_errors();

        // TEST 3
        debug.displayc($sformatf("%0d: Run triangle wave, and check outputs (halt in middle)",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.send_trig_wave(debug,5);
        tb_i.halt_dac();
        tb_i.send_trig_wave(debug,30);
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 4
        debug.displayc($sformatf("%0d: Run pwl wave",debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        tb_i.send_pwl_wave();
        total_errors += debug.get_error_count();
		debug.set_error_count(total_errors);
		tb_i.pause_osc = 1;
		tb_i.check_pwl_wave();
		#10000;       
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));

       	debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
    end 
endmodule 

`default_nettype wire

