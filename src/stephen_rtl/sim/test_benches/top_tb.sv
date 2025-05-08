`default_nettype none
`timescale 1ns / 1ps

import mem_layout_pkg::*;
import axi_params_pkg::*;
import daq_params_pkg::*;
module top_tb (input wire ps_clk, dac_clk, pl_rstn, ps_rst, dac_rst,
			   output logic sys_rst, 
			   //DAC
			   output logic[DAC_NUM-1:0] dac_rdys,
			   input  wire[DAC_NUM-1:0][(BATCH_SIZE)-1:0][(SAMPLE_WIDTH)-1:0] dac_batches, 
			   input  wire[DAC_NUM-1:0] valid_dac_batches, 
			   input  wire[DAC_NUM-1:0] dac_intf_rdys,
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
			   output logic[DAC_NUM-1:0][DMA_DATA_WIDTH-1:0] pwl_datas,
			   output logic[DAC_NUM-1:0][(DMA_DATA_WIDTH/8)-1:0] pwl_keeps,
			   output logic[DAC_NUM-1:0] pwl_lasts, pwl_valids,
			   input  wire[DAC_NUM-1:0] pwl_rdys,
			   input  wire[DAC_NUM-1:0] pwl_gen_rdys,
			   input  wire[DAC_NUM-1:0] run_pwls, run_trigs, run_rands);

	bit halt_osc = 0; 
	logic[DATAW-1:0] rdata; 
	logic[SDC_DATA_WIDTH-1:0] expc_sdc, got_sdc;
	logic[BUFF_CONFIG_WIDTH-1:0] expc_buffc, got_buffc;
	logic[CHANNEL_MUX_WIDTH-1:0] expc_cmc, got_cmc;
	logic[BUFF_TIMESTAMP_WIDTH-1:0] got_bufft;
	logic[DATAW-1:0] big_reg_buff [$];
	logic[DATAW-1:0] data_piece;
	int samples_seen,samples_expected;
	int test_part = 0;
	logic ref_ps_clk;
	assign ref_ps_clk = ps_clk;	

	logic[DAC_NUM-1:0][DATAW-1:0] bss;
	logic[DAC_NUM-1:0][DATAW-1:0] scales;
	logic[BUFF_SIZE-1:0][DATAW-1:0] bufft;

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

    `define iinside(i, ids) (i inside {[ids[0] : ids[DAC_NUM-1]]})

	task automatic init();
		@(posedge ps_clk);
		dac_rdys <= {DAC_NUM{1'b1}};
		{raddr_packet, waddr_packet, wdata_packet} <= '0; 
		{raddr_valid_packet, waddr_valid_packet, wdata_valid_packet} <= '0; 
		{ps_wresp_rdy,ps_read_rdy} <= '0;
		{sdc_rdy_in, buffc_rdy_in, cmc_rdy_in} <= '0;
		{bufft_data_in, bufft_valid_in} <= '0;
		{pwl_datas, pwl_keeps, pwl_lasts, pwl_valids} <= '0; 
		@(posedge ps_clk);
		`osc_sig(ps_wresp_rdy,ps_clk,0,5,1);
		`osc_sig(ps_read_rdy,ps_clk,0,5,1); 
		`osc_sig(sdc_rdy_in,ps_clk,1,2,0);
		`osc_sig(buffc_rdy_in,ps_clk,1,2,0); 
		`osc_sig(cmc_rdy_in,ps_clk,1,2,0);
		sim_util_pkg::flash_signal(sys_rst,  ref_ps_clk);
	endtask 

	task automatic ps_write(inout sim_util_pkg::debug debug, input logic[A_BUS_WIDTH-1:0] waddr, input logic[DATAW-1:0] wdata);
		@(posedge ps_clk); 
		waddr_packet <= waddr; 
		wdata_packet <= wdata; 
		{waddr_valid_packet, wdata_valid_packet} <= 3; 
		@(posedge ps_clk); 
		{waddr_valid_packet, wdata_valid_packet} <= 0;
		if (wresp_valid_out != 0) debug.fatalc("### WRESP VALID SHOULDN'T BE HIGH ###");
		while (~(wresp_valid_out && ps_wresp_rdy)) @(posedge ps_clk); 
		if (wresp_out != axi_params_pkg::OKAY) debug.fatalc("### WRITE REQUEST FAILED ###");
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

	task automatic send_reset(inout sim_util_pkg::debug debug);
		ps_write(debug,RST_ADDR, 1);
		while (pl_rstn) @(posedge ps_clk);
		while (~pl_rstn) @(posedge ps_clk); 
	endtask 

	task automatic async_reset_test(inout sim_util_pkg::debug debug);
		sys_rst = 1;
        repeat (30) @(posedge ps_clk);
        debug.disp_test_part(test_part, ps_rst == 0 && pl_rstn == 1 && dac_rst == 0, "Async sys reset is still high; synch resets should not be active yet");
        test_part++;
        sys_rst = 0;
        repeat (1) @(posedge ps_clk);
        debug.disp_test_part(test_part, ps_rst == 1 && pl_rstn == 0 && dac_rst == 0, "Async sys reset just fell; synch ps resets should be active");
        test_part++;
        while(~dac_rst) @(posedge dac_clk);
        debug.disp_test_part(test_part, ps_rst == 1 && pl_rstn == 0 && dac_rst == 1, "PS synch reset should be active until dac reset ACK is recieved"); 
        test_part++;
        @(posedge dac_clk);
        debug.disp_test_part(test_part, dac_rst == 0, "Dac reset should not be active for more than one cycle"); 
        test_part++;
        while (ps_rst) @(posedge ps_clk);
        debug.disp_test_part(test_part, ps_rst == 0 && pl_rstn == 1 && dac_rst == 0, "All resets should be cleared now"); 
        test_part++;
	endtask

	task automatic synch_reset_test(inout sim_util_pkg::debug debug);
		send_reset(debug); 
		debug.disp_test_part(test_part, ps_rst == 0 && pl_rstn == 1 && dac_rst == 0, "PS synch resets should now be deactive"); 
		test_part++;
	endtask 

	task automatic reset_rw_test(inout sim_util_pkg::debug debug); 
		int small_val_index = $urandom_range(0,DAC_NUM-1);
		for (int i = 0; i < DAC_NUM; i++) begin
			bss[i] = (i == small_val_index)? MAX_DAC_BURST_SIZE/2 : $urandom();
			scales[i] = (i == small_val_index)? MAX_SCALE_FACTOR/2 : $urandom();
		end
		for (int i = 0; i < BUFF_SIZE; i++) bufft[i] = $urandom();

		for (int i = 0; i < BUFF_SIZE; i++) begin 
			ps_write(debug,BUFF_TIME_BASE_ADDR+4*i, bufft[i]);
			ps_read(BUFF_TIME_BASE_ADDR+4*i);
			debug.disp_test_part(test_part, rdata == bufft[i], $sformatf("Bufft[%0d] write didn't go through. Expected %0d got %0d.",i,bufft[i],rdata));
			test_part++;
		end 
		for (int i = 0; i < DAC_NUM; i++) begin 
			ps_write(debug,DAC_BURST_SIZE_ADDRS[i], bss[i]);
			ps_write(debug,DAC_SCALE_ADDRS[i], scales[i]);
			if (scales[i] > MAX_SCALE_FACTOR) scales[i] = MAX_SCALE_FACTOR; 
			if (bss[i] > MAX_DAC_BURST_SIZE) bss[i] = MAX_DAC_BURST_SIZE;
		end 
		for (int i = 0; i < DAC_NUM; i++) begin
			ps_read(DAC_BURST_SIZE_ADDRS[i]);
			debug.disp_test_part(test_part, rdata == bss[i], $sformatf("BS (Dac # %0d) write at index %0d didn't go through. Expected %0d got %0d.",i, ADDR2ID(DAC_BURST_SIZE_ADDRS[i]), bss[i],rdata));
			test_part++;
			ps_read(DAC_SCALE_ADDRS[i]);
			debug.disp_test_part(test_part, (scales[i] > MAX_SCALE_FACTOR)? rdata == MAX_SCALE_FACTOR : rdata == scales[i], $sformatf("Scale (Dac # %0d) write didn't go through. Expected %0d got %0d.",i, scales[i],rdata));
			test_part++;
		end 

		send_reset(debug); 

		for (int i = 0; i < BUFF_SIZE; i++) begin
			ps_read(BUFF_TIME_BASE_ADDR+4*i);
			debug.disp_test_part(test_part, rdata == {DATAW{1'b1}}, $sformatf("Bufft[%0d] reset didn't go through. Expected %h, got %h", i, {DATAW{1'b1}}, rdata));
			test_part++;
		end 
		for (int i = 0; i < DAC_NUM; i++) begin
			ps_read(DAC_BURST_SIZE_ADDRS[i]);
			debug.disp_test_part(test_part, rdata == 0, $sformatf("BS (Dac # %0d) reset didn't go through. Expected 0, got %h", i, rdata));
			test_part++;
			ps_read(DAC_SCALE_ADDRS[i]);
			debug.disp_test_part(test_part, rdata == 0, $sformatf("Scale (Dac # %0d) reset didn't go through. Expected 0, got %h", i, rdata));
			test_part++;
		end 

	endtask 

	task automatic halt_dac(inout sim_util_pkg::debug debug, input int dac_id);
		ps_write(debug,DAC_HLT_ADDRS[dac_id], 1);
		while (valid_dac_batches[dac_id]) @(posedge dac_clk);
		while (~dac_intf_rdys[dac_id]) @(posedge ps_clk);
	endtask

	task automatic send_pwl_buff(inout sim_util_pkg::debug debug, input logic[DMA_DATA_WIDTH-1:0] dma_buff [$], input int dac_id);
		int delay_timer; 
		halt_dac(debug, dac_id); 
		while (~pwl_gen_rdys[dac_id]) @(posedge ps_clk); 
		@(posedge dac_clk); 
		for (int i = 0; i < dma_buff.size(); i++) begin
			pwl_valids[dac_id] <= 1; 
			pwl_datas[dac_id] <= dma_buff[i]; 
			if (i == dma_buff.size()-1) pwl_lasts[dac_id] <= 1; 
			@(posedge dac_clk); 
			while (~pwl_rdys[dac_id]) @(posedge dac_clk); 
			{pwl_valids[dac_id],pwl_lasts[dac_id]} <= 0; 
			@(posedge dac_clk);
			delay_timer = $urandom_range(0,10);
			repeat(delay_timer) @(posedge dac_clk);				
		end
		{pwl_valids[dac_id],pwl_lasts[dac_id]} <= 0; 
		@(posedge dac_clk);		
	endtask


	task automatic dac_test(inout sim_util_pkg::debug debug, input int dac_id); 
		logic[A_BUS_WIDTH-1:0] addr = PS_SEED_BASE_ADDRS[dac_id];
		logic[DMA_DATA_WIDTH-1:0] dma_buff [$]; 
		int expc_batch [$]; 
		bit match = 0; 
		dma_buff = {64'd67216212001, 64'd70368811393875976, 64'd88101667710435352};
		expc_batch = {0, 16, 31, 47, 63, 78, 94, 110, 125, 141, 156, 172, 188, 203, 219, 235};

		while (addr != PS_SEED_VALID_ADDRS[dac_id]) begin
			ps_write(debug,addr, $urandom());
			addr+=4; 
		end
		repeat(20) @(posedge ps_clk); 
		debug.disp_test_part(0, valid_dac_batches[dac_id] == 0, "Dac shouldn't be high");
		ps_write(debug,addr, 1);
		while (~valid_dac_batches[dac_id]) @(posedge dac_clk); 
		debug.disp_test_part(1, (run_rands[dac_id] && ~run_trigs[dac_id] && ~run_pwls[dac_id]), "");
		halt_dac(debug,dac_id);

		ps_write(debug,TRIG_WAVE_ADDRS[dac_id], 1);
		while (~valid_dac_batches[dac_id]) @(posedge dac_clk); 
		debug.disp_test_part(2, (~run_rands[dac_id] && run_trigs[dac_id] && ~run_pwls[dac_id]), "");
		halt_dac(debug,dac_id);

		send_pwl_buff(debug, dma_buff, dac_id);
		ps_write(debug,RUN_PWL_ADDRS[dac_id], 1);
		while (~valid_dac_batches[dac_id]) @(posedge dac_clk); 
		debug.disp_test_part(3, (~run_rands[dac_id] && ~run_trigs[dac_id] && run_pwls[dac_id]), "");
		while (~match) begin
			@(posedge ps_clk);
			match = 1;
			for (int i = 0; i < BATCH_SIZE; i++) begin
				if (dac_batches[dac_id][i] != expc_batch[i]) match = 0;
			end
		end
		debug.disp_test_part(4, 1, "");
		halt_dac(debug, dac_id);

		debug.disp_test_part(5, (~run_rands[dac_id] && ~run_trigs[dac_id] && ~run_pwls[dac_id]), "");

		ps_write(debug,TRIG_WAVE_ADDRS[dac_id], 1);
		while (~valid_dac_batches[dac_id]) @(posedge dac_clk);
		debug.disp_test_part(6, (~run_rands[dac_id] && run_trigs[dac_id] && ~run_pwls[dac_id]), "");
		ps_write(debug,RUN_PWL_ADDRS[dac_id], 1);
		while (valid_dac_batches[dac_id]) @(posedge dac_clk);
		while (~valid_dac_batches[dac_id]) @(posedge dac_clk);
		debug.disp_test_part(7, (~run_rands[dac_id] && ~run_trigs[dac_id] && run_pwls[dac_id]), "");
		while (~match) begin
			@(posedge ps_clk);
			match = 1;
			for (int i = 0; i < BATCH_SIZE; i++) begin
				if (dac_batches[dac_id][i] != expc_batch[i]) match = 0;
			end
		end
		debug.disp_test_part(8, 1, "");
		halt_dac(debug, dac_id);
		debug.disp_test_part(9, (~run_rands[dac_id] && ~run_trigs[dac_id] && ~run_pwls[dac_id]), "");
	endtask 

	task automatic burst_test(inout sim_util_pkg::debug debug, input int bs, dac_id);		
		int test_part = 0;
		samples_expected = bs; 
		ps_write(debug,DAC_BURST_SIZE_ADDRS[dac_id], bs);
		if (bs == 0) samples_expected = MAX_DAC_BURST_SIZE+$urandom_range(50,100); 
		halt_dac(debug, dac_id);
		repeat(3) begin
			samples_seen = 0;
			ps_write(debug,TRIG_WAVE_ADDRS[dac_id], 1);
			while (~valid_dac_batches[dac_id]) @(posedge dac_clk);
			while (valid_dac_batches[dac_id]) begin
				@(posedge dac_clk);
				if (samples_seen == samples_expected) break;
				if (bs == 0 && samples_seen > 5000) break;
				samples_seen++;
			end

			if (bs == 0) begin
				debug.disp_test_part(test_part+0, valid_dac_batches[dac_id], "Dac shouldn't be in burst mode");
				test_part++;
			end 
			else begin
				debug.disp_test_part(test_part+0, ~valid_dac_batches[dac_id], "Dac output should have stopped");
				repeat (100) @(posedge dac_clk);
				debug.disp_test_part(test_part+1, ~valid_dac_batches[dac_id], "Dac output should have stopped2");
				debug.disp_test_part(test_part+2, samples_seen == samples_expected, $sformatf("Expected %0d batches. Saw %0d",samples_expected,samples_seen));
				test_part+=3;
			end 
		end 
	endtask 

	task automatic seq_run(inout sim_util_pkg::debug debug, input int dac_id);	
		halt_dac(debug, dac_id);	
		ps_write(debug,PS_SEED_VALID_ADDRS[dac_id], 1);
		do @(posedge dac_clk); while (~run_rands[dac_id]);			
		debug.disp_test_part(1, (run_rands[dac_id] && ~run_trigs[dac_id] && ~run_pwls[dac_id]), "");

		ps_write(debug,TRIG_WAVE_ADDRS[dac_id], 1);
		do @(posedge dac_clk); while (run_rands[dac_id]);
		debug.disp_test_part(2, (~run_rands[dac_id] && run_trigs[dac_id] && ~run_pwls[dac_id]), "");

		ps_write(debug,RUN_PWL_ADDRS[dac_id], 1);
		do @(posedge dac_clk); while (run_trigs[dac_id]);
		debug.disp_test_part(3, (~run_rands[dac_id] && ~run_trigs[dac_id] && run_pwls[dac_id]), "");
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

		for (int i = 0; i < SDC_DATA_WIDTH; i+=DATAW) big_reg_buff.push_back(expc_sdc[i+:DATAW]);
		fork 
			begin write_big_reg(debug, SDC_BASE_ADDR); end 
			begin
				while (~sdc_valid_out) @(posedge ps_clk);
				got_sdc <= sdc_data_out; 
				@(posedge ps_clk);
			end 
		join
		debug.disp_test_part(0, got_sdc == expc_sdc, $sformatf("SDC data incorrect: Expected %h got %h", expc_sdc, got_sdc));

		for (int i = 0; i < CHANNEL_MUX_WIDTH; i+=DATAW) big_reg_buff.push_back(expc_cmc[i+:DATAW]);
		fork 
			begin write_big_reg(debug, CHAN_MUX_BASE_ADDR); end 
			begin
				while (~cmc_valid_out) @(posedge ps_clk);
				got_cmc <= cmc_data_out; 
				@(posedge ps_clk);
			end 
		join
		debug.disp_test_part(1, got_cmc == expc_cmc, $sformatf("SDC data incorrect: Expected %h got %h", expc_cmc, got_cmc));

		fork 
			begin ps_write(debug, BUFF_CONFIG_ADDR, expc_buffc); end 
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

		for (int i = 0; i < SDC_DATA_WIDTH; i+=DATAW) big_reg_buff.push_back(expc_sdc[i+:DATAW]);
		write_big_reg(debug, SDC_BASE_ADDR);
		for (int i = 0; i < CHANNEL_MUX_WIDTH; i+=DATAW) big_reg_buff.push_back(expc_cmc[i+:DATAW]);
		write_big_reg(debug, CHAN_MUX_BASE_ADDR);
		ps_write(debug, BUFF_CONFIG_ADDR, expc_buffc);

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
		logic[A_BUS_WIDTH-1:0] addr = BUFF_TIME_BASE_ADDR;

		while (addr < BUFF_TIME_VALID_ADDR) begin
			ps_read(addr);
			big_reg_buff.push_back(rdata);
			addr+=4; 
		end 
		while (big_reg_buff.size()>0) begin 
			got_bufft[i+:DATAW] = big_reg_buff.pop_front();
			i+=DATAW; 
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
		while (rdata != 1) ps_read(BUFF_TIME_VALID_ADDR);
		fill_bufft();		
		debug.disp_test_part(1, got_bufft == bufft_data_in, $sformatf("Wrong value in time buffer. Expected %h, got %h", bufft_data_in, got_bufft));
	endtask 

	task automatic mem_test(inout sim_util_pkg::debug debug);	
		logic[A_BUS_WIDTH-1:0] addr = MEM_TEST_BASE_ADDR;
		logic [DATAW-1:0] data; 
		int i = 0;
		while (addr < MEM_TEST_END_ADDR) begin
			data = $urandom(); 
			ps_write(debug, addr, data);
			ps_read(addr);
			debug.disp_test_part(i, $signed(rdata) == $signed($signed(data)-10),$sformatf("(1) %h = %h, not %h",addr,data-10,rdata));
			ps_read(addr+4);
			if (addr+4 != MEM_TEST_END_ADDR) debug.disp_test_part(i+1, rdata == (data+10),$sformatf("(2) %h = %h, not %h",addr+4,data-10,rdata));
			addr+=4;
			i++;
		end
	endtask 

	task automatic mem_read_write_test(inout sim_util_pkg::debug debug);	
		logic[A_BUS_WIDTH-1:0] addr = PS_SEED_BASE_ADDRS[0];
		logic [DATAW-1:0] expc_data, wdata; 
		logic[MEM_WIDTH-1:0] id; 
		send_reset(debug);

		while(addr <= ABS_ADDR_CEILING) begin
			if (addr == MEM_TEST_BASE_ADDR) begin
				addr = MEM_TEST_END_ADDR+4;
				continue;
			end
			
			id = ADDR2ID(addr); 
			if (addr == VERSION_ADDR) expc_data = FIRMWARE_VERSION;
			else if (addr == MEM_SIZE_ADDR) expc_data = MEM_SIZE;
			else if (addr == MAX_DAC_BURST_SIZE_ADDR) expc_data = MAX_DAC_BURST_SIZE;
			else if (addr == ABS_ADDR_CEILING) expc_data = {(DATAW-2){1'b1}};
			else if (is_PS_VALID(id) || is_RTL_VALID(id) || addr == RST_ADDR) expc_data = 0;
			else if (addr >= DAC_BURST_SIZE_ADDRS[0] && addr <= DAC_BURST_SIZE_ADDRS[DAC_NUM-1]) expc_data = 0;
			else if (addr >= DAC_SCALE_ADDRS[0] && addr <= DAC_SCALE_ADDRS[DAC_NUM-1]) expc_data = 0; 
			else if (addr <= MAPPED_ADDR_CEILING) expc_data = {DATAW{1'b1}};
			else expc_data = 0;

			ps_read(addr);			
			debug.disp_test_part(id, rdata == expc_data, $sformatf("addr %h: Expected %h got %h",addr,expc_data,rdata));
			wdata = $urandom_range(5,10); 
			ps_write(debug, addr, wdata);
			ps_read(addr);

			if (addr == VERSION_ADDR) expc_data = FIRMWARE_VERSION;
			else if (addr == MEM_SIZE_ADDR) expc_data = MEM_SIZE;
			else if (addr == MAX_DAC_BURST_SIZE_ADDR) expc_data = MAX_DAC_BURST_SIZE;
			else if (addr == ABS_ADDR_CEILING) expc_data = {(DATAW-2){1'b1}};
			else if (addr == MAPPED_ADDR_CEILING) expc_data = {DATAW{1'b1}};
			else if (is_PS_BIGREG(id) && is_PS_VALID(id)) expc_data = 0;			
			else if (addr > MAPPED_ADDR_CEILING) expc_data = 0;
			else expc_data = wdata;

			if (is_READONLY(id)) debug.disp_test_part(id, rdata == expc_data, $sformatf("(post-write READONLY) addr %h: Expected %h got %h",addr,expc_data,rdata));
			else if (addr > MAPPED_ADDR_CEILING) debug.disp_test_part(id, rdata == expc_data, $sformatf("(post-write UNMAPPED) addr %h: Expected %h got %h",addr,expc_data,rdata));
			else debug.disp_test_part(id, rdata == expc_data, $sformatf("(post-write) addr %h: Expected %h got %h",addr,expc_data,rdata));
			addr+=4;
			debug.reset_timeout(ref_ps_clk);
		end
		send_reset(debug);
		ps_read(ABS_ADDR_CEILING+64);
		debug.disp_test_part(id+1, rdata == {(DATAW-2){1'b1}}, $sformatf("(post-write UNBOUND) addr %h: Expected %h got %h",ABS_ADDR_CEILING+64,{(DATAW-2){1'b1}},rdata));
	endtask 
endmodule 

`default_nettype wire

