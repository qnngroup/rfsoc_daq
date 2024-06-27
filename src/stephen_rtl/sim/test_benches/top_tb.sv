`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"
// import mem_layout_pkg::flash_signal;
module top_tb #(parameter BATCH_SIZE, parameter A_BUS_WIDTH, parameter WD_BUS_WIDTH, parameter DMA_DATA_WIDTH, parameter WD_WIDTH,
				parameter SDC_DATA_WIDTH, parameter BUFF_CONFIG_WIDTH, parameter CHANNEL_MUX_WIDTH, parameter BUFF_TIMESTAMP_WIDTH)
					   (input wire ps_clk, dac_clk, pl_rstn,
					   	output logic ps_rst, dac_rst, 
		                //DAC
		                output logic dac0_rdy,
		                input  wire[BATCH_SIZE-1:0][WD_WIDTH-1:0] dac_batch, 
		                input  wire valid_dac_batch, 
		                //AXI
		                output logic [A_BUS_WIDTH-1:0] raddr_packet,
		                output logic raddr_valid_packet,
		                output logic [A_BUS_WIDTH-1:0] waddr_packet,
		                output logic waddr_valid_packet,
		                output logic [WD_BUS_WIDTH-1:0] wdata_packet,
		                output logic wdata_valid_packet,
		                output logic ps_wresp_rdy,ps_read_rdy,
		                input  wire[1:0] wresp_out,rresp_out,
		                input  wire wresp_valid_out, rresp_valid_out,
		                input  wire[WD_BUS_WIDTH-1:0] rdata_packet,
		                input  wire rdata_valid_out,
		                //Config Registers
		                output logic sdc_rdy_in,
		                input  wire[SDC_DATA_WIDTH-1:0] sdc_data_out,
		                input  wire sdc_valid_out,
		                output logic buffc_rdy_in,
		                input  wire[BUFF_CONFIG_WIDTH-1:0] buffc_data_out,
		                input  wire buffc_valid_out,
		                output logic cmc_rdy_in,
		                input  wire[CHANNEL_MUX_WIDTH-1:0] cmc_data_out,
		                input  wire cmc_valid_out, 
		                output logic[BUFF_TIMESTAMP_WIDTH-1:0] bufft_data_in,
		                output logic bufft_valid_in,
		                input  wire bufft_rdy_out, 
		                //DMA
		                output logic[DMA_DATA_WIDTH-1:0] pwl_data,
		                output logic[(DMA_DATA_WIDTH/8)-1:0] pwl_keep,
		                output logic pwl_last, pwl_valid,
		                input  wire pwl_ready,
		                input  wire run_pwl, run_trig, run_rand);

	bit halt_osc = 0; 
	logic[WD_WIDTH-1:0] rdata; 
	int samples_seen,samples_expected;

	task automatic init();
		dac0_rdy <= 1;
		{raddr_packet, waddr_packet, wdata_packet} <= 0; 
		{raddr_valid_packet, waddr_valid_packet, wdata_valid_packet} <= 0; 
		{ps_wresp_rdy,ps_read_rdy} <= 0;
		{sdc_rdy_in, buffc_rdy_in, cmc_rdy_in} <= 0;
		{bufft_data_in, bufft_valid_in} <= 0;
		{pwl_data, pwl_keep, pwl_last, pwl_valid} <= 0; 
		osc_sig(); 
		fork 
			begin `flash_signal(ps_rst,ps_clk) end 
			begin `flash_signal(dac_rst, dac_clk) end 
		join 
	endtask 

	task automatic osc_sig();
		fork 
			begin
				while (~halt_osc) begin
					@(posedge ps_clk);
					ps_read_rdy <= ~ps_read_rdy;
					repeat($urandom_range(0,5)) @(posedge ps_clk);  
				end 
				ps_read_rdy <= 1; 
			end 

			begin
				while (~halt_osc) begin
					@(posedge ps_clk);
					ps_wresp_rdy <= ~ps_wresp_rdy;
					repeat($urandom_range(0,5)) @(posedge ps_clk);  
				end 
				ps_wresp_rdy <= 1; 
			end 
		join_none
	endtask 

	task automatic ps_write(inout sim_util_pkg::debug debug, input logic[A_BUS_WIDTH-1:0] waddr, input logic[WD_WIDTH-1:0] wdata);
		@(posedge ps_clk); 
		waddr_packet <= waddr; 
		wdata_packet <= wdata; 
		{waddr_valid_packet, wdata_valid_packet} <= 3; 
		@(posedge ps_clk); 
		{waddr_valid_packet, wdata_valid_packet} <= 0;
		if (wresp_valid_out != 0) debug.fatalc("### WRESP VALID SHOULDN'T BE HIGH ###");
		while (~(wresp_valid_out && ps_wresp_rdy)) @(posedge ps_clk); 
		if (wresp_out != `OKAY) debug.fatalc("### WRITE REQUEST FAILED ###");
	endtask 

	task automatic ps_read(input logic[A_BUS_WIDTH-1:0] raddr);
		@(posedge ps_clk); 
		raddr_packet <= raddr;
		raddr_valid_packet <= 1; 
		@(posedge ps_clk); 
		raddr_valid_packet <= 0; 
		while (~(rdata_valid_out && ps_read_rdy)) @(posedge ps_clk);
		rdata <= rdata_packet;
		@(posedge ps_clk);
	endtask 

	task automatic reset(inout sim_util_pkg::debug debug);
		ps_write(debug,`RST_ADDR, 1);
		while (pl_rstn) @(posedge ps_clk); 
	endtask 

	task automatic reset_test(inout sim_util_pkg::debug debug); 
		logic[WD_WIDTH-1:0] bs = $urandom();  
		logic[WD_WIDTH-1:0] scale = $urandom();  
		logic[WD_WIDTH-1:0] bufft = $urandom(); 

		ps_write(debug,`DAC_BURST_SIZE_ADDR, bs);
		ps_write(debug,`SCALE_DAC_OUT_ADDR, scale);
		ps_write(debug,`BUFF_TIME_BASE_ADDR, bufft);
		if (scale > `MAX_SCALE_FACTOR) scale = `MAX_SCALE_FACTOR; 
		if (bs > `MAX_DAC_BURST_SIZE) bs = `MAX_DAC_BURST_SIZE;

		ps_read(`DAC_BURST_SIZE_ADDR);
		debug.disp_test_part(0, rdata == bs, $sformatf("BS write didn't go through. Expected %0d got %0d.",bs,rdata));
		ps_read(`SCALE_DAC_OUT_ADDR);
		debug.disp_test_part(1, (scale > `MAX_SCALE_FACTOR)? rdata == 15 : rdata == scale, $sformatf("Scale write didn't go through. Expected %0d got %0d.",scale,rdata));
		ps_read(`BUFF_TIME_BASE_ADDR);
		debug.disp_test_part(2, rdata == bufft, $sformatf("Bufft write didn't go through. Expected %0d got %0d.",bufft,rdata));

		reset(debug); 

		ps_read(`DAC_BURST_SIZE_ADDR);
		debug.disp_test_part(3, rdata == 0, "BS reset didn't go through");
		ps_read(`SCALE_DAC_OUT_ADDR);
		debug.disp_test_part(4, rdata == 0, "Scale reset didn't go through");
		ps_read(`BUFF_TIME_BASE_ADDR);
		debug.disp_test_part(5, rdata == {WD_WIDTH{1'b1}}, "Bufft reset didn't go through");
	endtask 

	task automatic halt_dac(inout sim_util_pkg::debug debug);
		ps_write(debug,`DAC_HLT_ADDR, 1);
		while (valid_dac_batch) @(posedge ps_clk); 
	endtask 

	task automatic send_pwl_buff(input logic[DMA_DATA_WIDTH-1:0] dma_buff [$]);
		int delay_timer; 
		@(posedge dac_clk);
		while (~pwl_ready) @(posedge dac_clk); 
		for (int i = 0; i < dma_buff.size(); i++) begin
			pwl_valid <= 1; 
			pwl_data <= dma_buff[i]; 
			if (i == dma_buff.size()-1) pwl_last <= 1; 
			@(posedge dac_clk); 
			while (~pwl_ready) @(posedge dac_clk); 
			delay_timer = $urandom_range(0,4); 
			if (delay_timer == 0) continue; 
			{pwl_last,pwl_valid} <= 0; 
			repeat(delay_timer) @(posedge dac_clk);				
		end
		{pwl_last,pwl_valid} <= 0;  
		@(posedge dac_clk);		
	endtask 


	task automatic dac_test(inout sim_util_pkg::debug debug); 
		logic[A_BUS_WIDTH-1:0] addr = `PS_SEED_BASE_ADDR;
		logic[DMA_DATA_WIDTH-1:0] dma_buff [$]; 
		int expc_batch [$]; 
		bit match = 0; 
		dma_buff = {64'd67216212001, 64'd70368811393875976, 64'd88101667710435352};
		expc_batch = {0, 16, 31, 47, 63, 78, 94, 110, 125, 141, 156, 172, 188, 203, 219, 235};

		while (addr != `PS_SEED_VALID_ADDR) begin
			ps_write(debug,addr, $urandom());
			addr+=4; 
		end
		repeat(20) @(posedge ps_clk); 
		debug.disp_test_part(0, valid_dac_batch == 0, "Dac shouldn't be high");
		ps_write(debug,addr, 1);
		while (~valid_dac_batch) @(posedge ps_clk); 
		debug.disp_test_part(1, (run_rand && ~run_trig && ~run_pwl), "");
		halt_dac(debug);

		ps_write(debug,`TRIG_WAVE_ADDR, 1);
		while (~valid_dac_batch) @(posedge ps_clk); 
		debug.disp_test_part(2, (~run_rand && run_trig && ~run_pwl), "");
		halt_dac(debug);

		send_pwl_buff(dma_buff);
		ps_write(debug,`RUN_PWL_ADDR, 1);
		while (~valid_dac_batch) @(posedge ps_clk); 
		debug.disp_test_part(3, (~run_rand && ~run_trig && run_pwl), "");
		while (~match) begin
			@(posedge ps_clk);
			match = 1;
			for (int i = 0; i < BATCH_SIZE; i++) begin
				if (dac_batch[i] != expc_batch[i]) match = 0;
			end
		end
		debug.disp_test_part(4, 1, "");
		halt_dac(debug);

		debug.disp_test_part(5, (~run_rand && ~run_trig && ~run_pwl), "");

		ps_write(debug,`TRIG_WAVE_ADDR, 1);
		while (~valid_dac_batch) @(posedge ps_clk);
		debug.disp_test_part(6, (~run_rand && run_trig && ~run_pwl), "");
		ps_write(debug,`RUN_PWL_ADDR, 1);
		while (valid_dac_batch) @(posedge ps_clk);
		while (~valid_dac_batch) @(posedge ps_clk);
		debug.disp_test_part(7, (~run_rand && ~run_trig && run_pwl), "");
		while (~match) begin
			@(posedge ps_clk);
			match = 1;
			for (int i = 0; i < BATCH_SIZE; i++) begin
				if (dac_batch[i] != expc_batch[i]) match = 0;
			end
		end
		debug.disp_test_part(8, 1, "");
		halt_dac(debug);
		debug.disp_test_part(9, (~run_rand && ~run_trig && ~run_pwl), "");
	endtask 

	task automatic burst_test(inout sim_util_pkg::debug debug, input int bs);		
		int rounds = 0;
		samples_expected = bs; 
		ps_write(debug,`DAC_BURST_SIZE_ADDR, bs);
		if (bs == 0) samples_expected = `MAX_DAC_BURST_SIZE+100; 
		halt_dac(debug);
		repeat(3) begin
			samples_seen = 0;
			ps_write(debug,`TRIG_WAVE_ADDR, 1);
			while (~valid_dac_batch) @(posedge dac_clk);
			while (valid_dac_batch) begin
				@(posedge dac_clk);
				if (samples_seen == samples_expected) break;
				if (bs == 0 && samples_seen > 5000) break;
				samples_seen++;
			end

			if (bs == 0) begin
				debug.disp_test_part(rounds+0, valid_dac_batch, "Dac shouldn't be in burst mode");
				rounds++;
			end 
			else begin
				debug.disp_test_part(rounds+0, ~valid_dac_batch, "Dac output should have stopped");
				repeat (100) @(posedge dac_clk);
				debug.disp_test_part(rounds+1, ~valid_dac_batch, "Dac output should have stopped2");
				debug.disp_test_part(rounds+2, samples_seen == samples_expected, $sformatf("Expected %0d batches. Saw %0d",samples_expected,samples_seen));
				rounds+=3;
			end 
		end 
	endtask 

	task seq_run(inout sim_util_pkg::debug debug);	
		halt_dac(debug);	
		ps_write(debug,`PS_SEED_VALID_ADDR, 1);
		do @(posedge dac_clk); while (~run_rand);			
		debug.disp_test_part(1, (run_rand && ~run_trig && ~run_pwl), "");

		ps_write(debug,`TRIG_WAVE_ADDR, 1);
		do @(posedge dac_clk); while (run_rand);
		debug.disp_test_part(2, (~run_rand && run_trig && ~run_pwl), "");

		ps_write(debug,`RUN_PWL_ADDR, 1);
		do @(posedge dac_clk); while (run_trig);
		debug.disp_test_part(3, (~run_rand && ~run_trig && run_pwl), "");
	endtask 

	task ps_config_write(inout sim_util_pkg::debug debug);	
		$display("LETS GO!");
	endtask 

endmodule 

`default_nettype wire

