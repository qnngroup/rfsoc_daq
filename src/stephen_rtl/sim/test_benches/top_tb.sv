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
	logic[SDC_DATA_WIDTH-1:0] expc_sdc, got_sdc;
	logic[BUFF_CONFIG_WIDTH-1:0] expc_buffc, got_buffc;
	logic[CHANNEL_MUX_WIDTH-1:0] expc_cmc, got_cmc;
	logic[BUFF_TIMESTAMP_WIDTH-1:0] got_bufft;
	logic[WD_WIDTH-1:0] big_reg_buff [$];
	logic[WD_WIDTH-1:0] data_piece;
	int samples_seen,samples_expected;

	`define osc_sig(sig, clk,low,high,def_val) \
    fork \
        begin \
        	while (~halt_osc) begin \
        		@(posedge clk); \
        		sig <= ~sig; \
        		repeat($urandom_range(low,high)) @(posedge clk); \
        	end \
        	sig <= def_val; \
        end \
    join_none 

	task automatic init();
		@(posedge ps_clk);
		dac0_rdy <= 1;
		{raddr_packet, waddr_packet, wdata_packet} <= 0; 
		{raddr_valid_packet, waddr_valid_packet, wdata_valid_packet} <= 0; 
		{ps_wresp_rdy,ps_read_rdy} <= 0;
		{sdc_rdy_in, buffc_rdy_in, cmc_rdy_in} <= 0;
		{bufft_data_in, bufft_valid_in} <= 0;
		{pwl_data, pwl_keep, pwl_last, pwl_valid} <= 0; 
		@(posedge ps_clk);
		`osc_sig(ps_wresp_rdy,ps_clk,0,5,1);
		`osc_sig(ps_read_rdy,ps_clk,0,5,1); 
		`osc_sig(sdc_rdy_in,ps_clk,1,2,0);
		`osc_sig(buffc_rdy_in,ps_clk,1,2,0); 
		`osc_sig(cmc_rdy_in,ps_clk,1,2,0);
		fork 
			begin `flash_signal(ps_rst,ps_clk) end 
			begin `flash_signal(dac_rst, dac_clk) end 
		join 
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

	task automatic seq_run(inout sim_util_pkg::debug debug);	
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

	task automatic write_big_reg(inout sim_util_pkg::debug debug, input logic[A_BUS_WIDTH-1:0] addr);		
		while (big_reg_buff.size() > 0) begin
			data_piece = big_reg_buff.pop_front(); 
			ps_write(debug, addr, data_piece);
			addr+=4;
		end 
		ps_write(debug, addr, 1);
	endtask 

	task automatic ps_config_write(inout sim_util_pkg::debug debug);	
		for (int i = 0; i < SDC_DATA_WIDTH; i+=32) expc_sdc[i+:32] = $urandom();
		for (int i = 0; i < CHANNEL_MUX_WIDTH; i+=32) expc_cmc[i+:32] = $urandom();
		expc_buffc = $urandom();

		for (int i = 0; i < SDC_DATA_WIDTH; i+=WD_WIDTH) big_reg_buff.push_back(expc_sdc[i+:WD_WIDTH]);
		fork 
			begin write_big_reg(debug, `SDC_BASE_ADDR); end 
			begin
				while (~sdc_valid_out) @(posedge ps_clk);
				got_sdc <= sdc_data_out; 
				@(posedge ps_clk);
			end 
		join
		debug.disp_test_part(0, got_sdc == expc_sdc, $sformatf("SDC data incorrect: Expected %h got %h", expc_sdc, got_sdc));

		for (int i = 0; i < CHANNEL_MUX_WIDTH; i+=WD_WIDTH) big_reg_buff.push_back(expc_cmc[i+:WD_WIDTH]);
		fork 
			begin write_big_reg(debug, `CHAN_MUX_BASE_ADDR); end 
			begin
				while (~cmc_valid_out) @(posedge ps_clk);
				got_cmc <= cmc_data_out; 
				@(posedge ps_clk);
			end 
		join
		debug.disp_test_part(1, got_cmc == expc_cmc, $sformatf("SDC data incorrect: Expected %h got %h", expc_cmc, got_cmc));

		fork 
			begin ps_write(debug, `BUFF_CONFIG_ADDR, expc_buffc); end 
			begin
				while (~buffc_valid_out) @(posedge ps_clk);
				got_buffc <= buffc_data_out;
				@(posedge ps_clk); 
			end 
		join
		debug.disp_test_part(2, got_buffc == expc_buffc, $sformatf("SDC data incorrect: Expected %h got %h", expc_buffc, got_buffc));
	endtask 

	task automatic ps_config_write_rdy_hold(inout sim_util_pkg::debug debug);	
		for (int i = 0; i < SDC_DATA_WIDTH; i+=32) expc_sdc[i+:32] = $urandom();
		for (int i = 0; i < CHANNEL_MUX_WIDTH; i+=32) expc_cmc[i+:32] = $urandom();
		expc_buffc = $urandom();
		halt_osc = 1;

		for (int i = 0; i < SDC_DATA_WIDTH; i+=WD_WIDTH) big_reg_buff.push_back(expc_sdc[i+:WD_WIDTH]);
		write_big_reg(debug, `SDC_BASE_ADDR);
		for (int i = 0; i < CHANNEL_MUX_WIDTH; i+=WD_WIDTH) big_reg_buff.push_back(expc_cmc[i+:WD_WIDTH]);
		write_big_reg(debug, `CHAN_MUX_BASE_ADDR);
		ps_write(debug, `BUFF_CONFIG_ADDR, expc_buffc);

		repeat($urandom_range(50,300)) @(posedge  ps_clk);		
		debug.disp_test_part(0, (sdc_valid_out && buffc_valid_out && cmc_valid_out), "All valids should still be high");
		debug.disp_test_part(1, (expc_sdc == sdc_data_out), "SDC data incorret");
		debug.disp_test_part(2, (expc_cmc == cmc_data_out), "CMC data incorret");
		debug.disp_test_part(3, (expc_buffc == buffc_data_out), "BUFFC data incorret");

		sdc_rdy_in <= 1; 
		repeat(2) @(posedge ps_clk); 
		debug.disp_test_part(4, (~sdc_valid_out && buffc_valid_out && cmc_valid_out), "SDC valid should have fallen");
		debug.disp_test_part(5, (sdc_data_out == 0), "SDC data should be zero now");
		cmc_rdy_in <= 1; 
		repeat(2) @(posedge ps_clk); 
		debug.disp_test_part(6, (~sdc_valid_out && buffc_valid_out && ~cmc_valid_out), "CMC and SDC valids should have fallen");
		debug.disp_test_part(7, (cmc_data_out == 0 && sdc_data_out == 0), "CMC and SDC data should be zero now");
		buffc_rdy_in <= 1; 
		repeat(2) @(posedge ps_clk); 
		debug.disp_test_part(8, (~sdc_valid_out && ~buffc_valid_out && ~cmc_valid_out), "All valids should have fallen");
		debug.disp_test_part(9, (buffc_data_out == 0 && cmc_data_out == 0 && sdc_data_out == 0), "All data should be zero now");
	endtask 

	task automatic fill_bufft();
		int i = 0;
		logic[A_BUS_WIDTH-1:0] addr = `BUFF_TIME_BASE_ADDR;

		while (addr < `BUFF_TIME_VALID_ADDR) begin
			ps_read(addr);
			big_reg_buff.push_back(rdata);
			addr+=4; 
		end 
		while (big_reg_buff.size()>0) begin 
			got_bufft[i+:WD_WIDTH] = big_reg_buff.pop_front();
			i+=WD_WIDTH; 
		end 
	endtask
	task automatic rtl_exposed_reg_test(inout sim_util_pkg::debug debug);	
		fill_bufft();
		for (int i =0; i < BUFF_TIMESTAMP_WIDTH; i+= 32) bufft_data_in[i+:32] <= $urandom();
		@(posedge ps_clk);
		debug.disp_test_part(0, got_bufft != bufft_data_in, "Time buffer should not be populated yet");
		bufft_valid_in <= 1;
		do @(posedge ps_clk); while (~bufft_rdy_out); 
		bufft_valid_in <= 0;
		rdata = 0;
		while (rdata != 1) ps_read(`BUFF_TIME_VALID_ADDR);
		fill_bufft();		
		debug.disp_test_part(1, got_bufft == bufft_data_in, $sformatf("Wrong value in time buffer. Expected %h, got %h", bufft_data_in, got_bufft));
	endtask 

	task automatic mem_test(inout sim_util_pkg::debug debug);	
		logic[A_BUS_WIDTH-1:0] addr = `MEM_TEST_BASE_ADDR;
		logic [WD_WIDTH-1:0] data; 
		int i = 0;
		while (addr < `MEM_TEST_END_ADDR) begin
			data = $urandom(); 
			ps_write(debug, addr, data);
			ps_read(addr);
			debug.disp_test_part(i, $signed(rdata) == $signed($signed(data)-10),$sformatf("(1) %h = %h, not %h",addr,data-10,rdata));
			ps_read(addr+4);
			if (addr+4 != `MEM_TEST_END_ADDR) debug.disp_test_part(i+1, rdata == (data+10),$sformatf("(2) %h = %h, not %h",addr+4,data-10,rdata));
			addr+=4;
			i++;
		end
	endtask 

	task automatic mem_read_write_test(inout sim_util_pkg::debug debug);	
		logic[A_BUS_WIDTH-1:0] addr = `PS_SEED_BASE_ADDR;
		logic [WD_WIDTH-1:0] expc_data, wdata; 
		reset(debug);
		while(addr <= `ABS_ADDR_CEILING) begin
			if (addr == `MEM_TEST_BASE_ADDR) begin
				addr = `MEM_TEST_END_ADDR;
				continue;
			end
			if (addr == `RUN_PWL_ADDR || addr == `PWL_PERIOD0_ADDR || addr == `PWL_PERIOD1_ADDR) begin
				addr+=4;
				continue; 
			end 

			case(addr) 
				`PS_SEED_VALID_ADDR,`DAC_BURST_SIZE_ADDR,`SCALE_DAC_OUT_ADDR,`BUFF_TIME_VALID_ADDR,`CHAN_MUX_VALID_ADDR,`SDC_VALID_ADDR: expc_data = 0;
				`MAX_DAC_BURST_SIZE_ADDR: expc_data = `MAX_DAC_BURST_SIZE;
				`VERSION_ADDR: expc_data = `FIRMWARE_VERSION;
				`MEM_SIZE_ADDR: expc_data = `MEM_SIZE;
				`ABS_ADDR_CEILING: expc_data = -2;
				default: expc_data = -1;
			endcase 

			ps_read(addr);			
			debug.disp_test_part((addr-`PS_BASE_ADDR)/4, rdata == expc_data,$sformatf("addr %h: Expected %h got %h",addr,expc_data,rdata));
			wdata = $urandom();
			ps_write(debug,addr,wdata);
			ps_read(addr);

			case(addr)
				`MAX_DAC_BURST_SIZE_ADDR,`VERSION_ADDR,`MEM_SIZE_ADDR,`MAPPED_ADDR_CEILING,`MEM_TEST_END_ADDR,`ABS_ADDR_CEILING: begin
					debug.disp_test_part((addr-`PS_BASE_ADDR)/4, rdata == expc_data,$sformatf("(post-write, READONLY) addr %h: Expected %h got %h",addr,expc_data,rdata));
				end 
				`PS_SEED_VALID_ADDR,`CHAN_MUX_VALID_ADDR,`SDC_VALID_ADDR: begin
					debug.disp_test_part((addr-`PS_BASE_ADDR)/4, rdata == 0,$sformatf("(post-write, valid) addr %h: Expected %h got %h",addr,expc_data,rdata));
				end 
				`DAC_BURST_SIZE_ADDR: begin
					if (wdata > `MAX_DAC_BURST_SIZE) wdata = `MAX_DAC_BURST_SIZE;
					debug.disp_test_part((addr-`PS_BASE_ADDR)/4, rdata == wdata,$sformatf("(post-write) addr %h: Expected %h got %h",addr,wdata,rdata));
				end
				`SCALE_DAC_OUT_ADDR: begin
					if (wdata > `MAX_SCALE_FACTOR) wdata = `MAX_SCALE_FACTOR;
					debug.disp_test_part((addr-`PS_BASE_ADDR)/4, rdata == wdata,$sformatf("(post-write) addr %h: Expected %h got %h",addr,wdata,rdata));
				end  
				default: begin
					if (addr >= `MAPPED_ADDR_CEILING) debug.disp_test_part((addr-`PS_BASE_ADDR)/4, rdata == expc_data,$sformatf("(post-write) addr %h: Expected %h got %h",addr,expc_data,rdata));
					else debug.disp_test_part((addr-`PS_BASE_ADDR)/4, rdata == wdata,$sformatf("(post-write) addr %h: Expected %h got %h",addr,wdata,rdata));
				end 
			endcase 

			addr+=4;
		end
		reset(debug);
	endtask 
endmodule 

`default_nettype wire

