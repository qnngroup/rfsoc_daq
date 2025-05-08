`default_nettype none
`timescale 1ns / 1ps

import mem_layout_pkg::*;
import axi_params_pkg::*;
import daq_params_pkg::MAX_DAC_BURST_SIZE;
import daq_params_pkg::MAX_SCALE_FACTOR;
import daq_params_pkg::FIRMWARE_VERSION;
import daq_params_pkg::DAC_NUM;
module slave_tb (input wire clk,
				 input wire[MEM_SIZE-1:0][DATAW-1:0] rtl_rd_out,
				 input wire[MEM_SIZE-1:0] fresh_bits,
				 output logic clr_rd_out,
				 output logic[MEM_SIZE-1:0] rtl_write_reqs, rtl_read_reqs, rtl_rdy, 
				 output logic[MEM_SIZE-1:0][DATAW-1:0] rtl_wd_in,
				 Recieve_Transmit_IF wa_if,
				 Recieve_Transmit_IF wd_if,
				 Recieve_Transmit_IF ra_if,
				 Recieve_Transmit_IF rd_if,
				 Recieve_Transmit_IF wr_if,
				 Recieve_Transmit_IF rr_if); 
	
	logic ref_clk;
	logic[DATAW-1:0] rdata;
	assign ref_clk = clk; 

	`define iinside(i, ids) (i inside {[ids[0] : ids[DAC_NUM-1]]})

	task automatic init();
		{wa_if.data_to_send, wa_if.send} <= 0;
		{wd_if.data_to_send, wd_if.send} <= 0;
		{ra_if.data_to_send, ra_if.send} <= 0;
		{rtl_rdy, wd_if.dev_rdy, wa_if.dev_rdy , ra_if.dev_rdy, rd_if.dev_rdy, wr_if.dev_rdy} <= -1;	
		{clr_rd_out, rtl_write_reqs, rtl_read_reqs} <= 0;
		@(posedge clk);
	endtask 	

	task automatic ps_read(input logic[ADDRW-1:0] addr, output logic[DATAW-1:0] data);
		ra_if.data_to_send <= addr; 
		sim_util_pkg::flash_signal(ra_if.send,ref_clk); 
		while (1) begin
			if (rd_if.valid_data) begin
				data = rd_if.data; 
				break;
			end else @(posedge clk);
		end
	endtask 

	task automatic disp_mem_map(inout sim_util_pkg::debug debug, input int start = 0, input int end_id = MEM_SIZE);
		for (int i = start; i < end_id; i++) begin
			rtl_read(i,rdata);
			$display("%0d = %0d, %h",i, rdata, rdata);
			debug.reset_timeout(ref_clk);
		end
	endtask 

	task automatic rtl_read(input logic[$clog2(MEM_SIZE)-1:0] id, output logic[DATAW-1:0] data, input bit clr = 1);
		if (clr) sim_util_pkg::flash_signal(clr_rd_out,ref_clk);
		sim_util_pkg::flash_signal(rtl_read_reqs[id],ref_clk); 
		@(posedge clk);
		data = rtl_rd_out[id]; 
	endtask 

	task automatic ps_write(inout sim_util_pkg::debug debug, input logic[ADDRW-1:0] addr, 
							input logic[DATAW-1:0] data, input int delay = 0, input bit addr_first = 1);
		wa_if.data_to_send <= addr; 
		wd_if.data_to_send <= data; 
		if (delay == 0) begin
			fork 
				begin sim_util_pkg::flash_signal(wa_if.send,ref_clk); end
				begin sim_util_pkg::flash_signal(wd_if.send,ref_clk); end
			join
		end else begin
			if (addr_first) sim_util_pkg::flash_signal(wa_if.send,ref_clk);
			else sim_util_pkg::flash_signal(wd_if.send,ref_clk); 

			for (int i = 1; i < delay; i++) @(posedge clk); 
			if (addr_first) sim_util_pkg::flash_signal(wd_if.send,ref_clk);
			else sim_util_pkg::flash_signal(wa_if.send,ref_clk);
		end 

		while (1) begin
			if (wr_if.valid_data) begin
				if (wr_if.data != OKAY) debug.fatalc("### WRITE REQUEST FAILED ###");
				break; 
			end else @(posedge clk);
		end
	endtask 

	task automatic rtl_write(input logic[$clog2(MEM_SIZE)-1:0] id, input logic[DATAW-1:0] wdata);
		rtl_wd_in[id] <= wdata; 
		sim_util_pkg::flash_signal(rtl_write_reqs[id],ref_clk); 
	endtask 

	task automatic mem_test(inout sim_util_pkg::debug debug);
		int n = 0;	
		int j;	
		for (int addr = MEM_TEST_BASE_ADDR; addr < MEM_TEST_END_ADDR; addr+=4) begin
			j = addr-MEM_TEST_BASE_ADDR;
			ps_write(debug,addr,100+j);
			ps_read(addr,rdata);
			debug.disp_test_part(n,rdata == (100+j)-10,$sformatf("Expected %0d, Got %0d",(100+j)-10, rdata));
			if (addr < (MEM_TEST_END_ADDR-4)) begin
				ps_read(addr+4,rdata);
				debug.disp_test_part(n+1,rdata == (100+j)+10,$sformatf("Expected %0d, Got %0d",(100+j)+10, rdata));
			end 
			n+=2; 
			debug.reset_timeout(ref_clk);
		end 
	endtask 

	task automatic write_addr_space(inout sim_util_pkg::debug debug, output int written_val);
		written_val = $urandom_range(2,{DATAW{1'b1}});
		for (int addr = PS_BASE_ADDR; addr < ABS_ADDR_CEILING; addr+=4) begin
			ps_write(debug, addr, written_val);
			debug.reset_timeout(ref_clk);
		end 
	endtask 

	task automatic check_addr_space(inout sim_util_pkg::debug debug, input int written_val = 0, input bit has_written=0);
		logic[MEM_WIDTH-1:0] expc_data; 
		int maxed_val, ps_rdata; 

		if (has_written) begin
			for (int i = 0; i <= ABS_ID_CEILING; i++) begin
				ps_read(ID2ADDR(i),ps_rdata);
				rtl_read(i,rdata);
				debug.disp_test_part(i,rdata == ps_rdata, $sformatf("PS and RTL read different data at id %0d! PS read 0x%04x, RTL read 0x%04x", i, ps_rdata, rdata));

				if (`iinside(i,DAC_BURST_SIZE_IDS)) maxed_val = (written_val > MAX_DAC_BURST_SIZE)? MAX_DAC_BURST_SIZE : written_val;
				if (`iinside(i,DAC_SCALE_IDS)) maxed_val = (written_val > MAX_SCALE_FACTOR)? MAX_SCALE_FACTOR : written_val;

				if (i == MAX_DAC_BURST_SIZE_ID) debug.disp_test_part(i,rdata == MAX_DAC_BURST_SIZE, $sformatf("Max burst size incorrect. Expected 0x%04x, got 0x%04x",MAX_DAC_BURST_SIZE, rdata));
				else if (`iinside(i,DAC_BURST_SIZE_IDS)) debug.disp_test_part(i,rdata == maxed_val, $sformatf("Burst size incorrect. Expected 0x%04x, got 0x%04x",maxed_val, rdata));
				else if (`iinside(i,DAC_SCALE_IDS))  debug.disp_test_part(i,rdata == maxed_val, $sformatf("Scale factor incorrect. Expected 0x%04x, got 0x%04x",maxed_val, rdata));
				else if (i == VERSION_ID) debug.disp_test_part(i,rdata == FIRMWARE_VERSION, $sformatf("Version number incorrect. Expected %0d, got 0x%04x", FIRMWARE_VERSION, rdata)); 
				else if (i == MEM_SIZE_ID) debug.disp_test_part(i,rdata == MEM_SIZE, $sformatf("Memory size incorrect. Expected %0d, got 0x%04x", MEM_SIZE, rdata)); 
				else if (is_PS_BIGREG(i) && is_PS_VALID(i)) debug.disp_test_part(i,rdata == 0, "Valid registers apart of big registers should be cleared after being written to");
				else if (i inside {[MEM_TEST_BASE_ID : (MEM_TEST_END_ID-1)]}) debug.disp_test_part(i,rdata == (written_val-10), $sformatf("Mem test default value incorrect. At id %0d, Expected 0x%04x, got 0x%04x.", i, written_val-10, rdata));
				else if (i == MEM_TEST_END_ID) debug.disp_test_part(i,rdata == (written_val+10), $sformatf("Mem test default value incorrect. At id %0d, Expected 0x%04x, got 0x%04x.", i, written_val+10, rdata));
				else if (i == ABS_ID_CEILING) debug.disp_test_part(i,rdata == {(DATAW-2){1'b1}}, $sformatf("Absolute ceiling value incorrect. Expected 0x%04x, got 0x%04x.", {(DATAW-2){1'b1}}, rdata));
				else if (i < MAPPED_ID_CEILING) debug.disp_test_part(i,rdata == written_val, $sformatf("mapped value incorrect. Expected 0x%04x, got 0x%04x.", written_val, rdata));
				else if (i == MAPPED_ID_CEILING) debug.disp_test_part(i,rdata == {DATAW{1'b1}}, $sformatf("mapped ceiling value incorrect. Expected 0x%04x, got 0x%04x.", {DATAW{1'b1}}, rdata));
				else if (i > MAPPED_ID_CEILING) debug.disp_test_part(i,rdata == 0, $sformatf("Can't write to unmapped memory. At id %0d, expected 0, got 0x%04x.", i, rdata));
				else debug.disp_test_part(i,rdata == written_val, $sformatf("Memory ID %0d should have been written to. Expected 0x%04x, Got 0x%04x.", i, written_val, rdata));
				debug.reset_timeout(ref_clk);
			end
		end else begin
			for (int i = 0; i <= ABS_ID_CEILING; i++) begin
				ps_read(ID2ADDR(i),ps_rdata);
				rtl_read(i,rdata);
				debug.disp_test_part(i,rdata == ps_rdata, $sformatf("PS and RTL read different data at id %0d! PS read 0x%04x, RTL read 0x%04x", i, ps_rdata, rdata));

				if (i == RST_ID) debug.disp_test_part(i,rdata == 0, $sformatf("RST should be 0, got 0x%04x", rdata));
				else if (i == MAX_DAC_BURST_SIZE_ID) debug.disp_test_part(i,rdata == MAX_DAC_BURST_SIZE, "Default max burst size incorrect");
				else if (`iinside(i,DAC_BURST_SIZE_IDS)) debug.disp_test_part(i,rdata == 0, $sformatf("Default burst size incorrect. Got 0x%04x", rdata));  
				else if (`iinside(i,DAC_SCALE_IDS)) debug.disp_test_part(i,rdata == 0, $sformatf("Default scale factor incorrect. Got 0x%04x", rdata)); 
				else if (is_PS_VALID(i) || is_RTL_VALID(i)) debug.disp_test_part(i,rdata == 0, $sformatf("Valid addresses reset incorrectly. Expected %0d, got 0x%04x.", 0, rdata));
				else if (i == MEM_SIZE_ID) debug.disp_test_part(i,rdata == MEM_SIZE, $sformatf("Default memory size incorrect. Expected %0d, got 0x%04x.", MEM_SIZE, rdata));
				else if (i == VERSION_ID) debug.disp_test_part(i,rdata == FIRMWARE_VERSION, $sformatf("Default version number incorrect. Expected %0d, got 0x%04x.", FIRMWARE_VERSION, rdata));
				else if (i == ABS_ID_CEILING) debug.disp_test_part(i,rdata == {(DATAW-2){1'b1}}, $sformatf("Absolute ceiling value incorrect. Expected 0x%04x, got 0x%04x.", {(DATAW-2){1'b1}}, rdata));
				else if (i inside {[MEM_TEST_BASE_ID : MEM_TEST_END_ID]}) debug.disp_test_part(i,rdata == {(DATAW-1){1'b1}}, $sformatf("Mem test default value incorrect. At id %0d, Expected 0x%04x, got 0x%04x.", i, {(DATAW-1){1'b1}}, rdata));
				else if (i <= MAPPED_ID_CEILING) debug.disp_test_part(i,rdata == {DATAW{1'b1}}, $sformatf("mapped ceiling value incorrect. Expected 0x%04x, got 0x%04x.", {DATAW{1'b1}}, rdata));
				else debug.disp_test_part(i,rdata == 0, $sformatf("Default value for memory ID %0d should be 0. Got 0x%04x.", i, rdata));
				debug.reset_timeout(ref_clk);
			end 
		end
	endtask

	task automatic oscillate_rdys(ref bit halt_osc);
		bit[6:0][3:0] delay_timers;
		fork 
			begin
				while (~halt_osc) begin
					delay_timers[0] = $urandom_range(1,8);
					wa_if.dev_rdy <= 0; 
					for (int i = 0; i < delay_timers[0]; i++) @(posedge clk); 
					wa_if.dev_rdy <= 1;
					@(posedge clk); 
				end
			end
			begin
				while (~halt_osc) begin
					delay_timers[1] = $urandom_range(1,8);
					wd_if.dev_rdy <= 0; 
					for (int i = 0; i < delay_timers[1]; i++) @(posedge clk); 
					wd_if.dev_rdy <= 1;
					@(posedge clk); 
				end
			end
			begin
				while (~halt_osc) begin
					delay_timers[2] = $urandom_range(1,8);
					ra_if.dev_rdy <= 0; 
					for (int i = 0; i < delay_timers[2]; i++) @(posedge clk); 
					ra_if.dev_rdy <= 1;
					@(posedge clk); 
				end
			end
			begin
				while (~halt_osc) begin
					delay_timers[3] = $urandom_range(1,8);
					rd_if.dev_rdy <= 0; 
					for (int i = 0; i < delay_timers[3]; i++) @(posedge clk); 
					rd_if.dev_rdy <= 1;
					@(posedge clk); 
				end
			end
			begin
				while (~halt_osc) begin
					delay_timers[4] = $urandom_range(1,8);
					wr_if.dev_rdy <= 0; 
					for (int i = 0; i < delay_timers[4]; i++) @(posedge clk); 
					wr_if.dev_rdy <= 1;
					@(posedge clk); 
				end
			end
			begin
				while (~halt_osc) begin
					delay_timers[5] = $urandom_range(1,8);
					rr_if.dev_rdy <= 0; 
					for (int i = 0; i < delay_timers[5]; i++) @(posedge clk); 
					rr_if.dev_rdy <= 1;
					@(posedge clk); 
				end
			end
			begin
				while (~halt_osc) begin
					delay_timers[6] = $urandom_range(1,8);
					rtl_rdy <= 0; 
					for (int i = 0; i < delay_timers[6]; i++) @(posedge clk); 
					rtl_rdy <= -1;
					@(posedge clk); 
				end
			end
		join_none
	endtask 
	
endmodule 

`default_nettype wire

// Make sure rresp has the correct values

