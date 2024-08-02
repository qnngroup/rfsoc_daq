`default_nettype none
`timescale 1ns / 1ps

import mem_layout_pkg::*;
import axi_params_pkg::*;
import daq_params_pkg::MAX_DAC_BURST_SIZE;
import daq_params_pkg::MAX_SCALE_FACTOR;
import daq_params_pkg::FIRMWARE_VERSION;
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
	
	logic clk2;
	logic[DATAW-1:0] rdata;
	logic[MEM_SIZE-1:0][DATAW-1:0] mapped_memory = 0;
	assign clk2 = clk; 
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
		sim_util_pkg::flash_signal(ra_if.send,clk2); 
		while (1) begin
			if (rd_if.valid_data) begin
				data = rd_if.data; 
				break;
			end else @(posedge clk);
		end
	endtask 

	task automatic rtl_read(input logic[$clog2(MEM_SIZE)-1:0] id, output logic[DATAW-1:0] data, input bit clr = 1);
		if (clr) sim_util_pkg::flash_signal(clr_rd_out,clk2);
		sim_util_pkg::flash_signal(rtl_read_reqs[id],clk2); 
		@(posedge clk);
		data = rtl_rd_out[id]; 
	endtask 

	task automatic ps_write(inout sim_util_pkg::debug debug, input logic[ADDRW-1:0] addr, 
							input logic[DATAW-1:0] data, input int delay = 0, input bit addr_first = 1);
		wa_if.data_to_send <= addr; 
		wd_if.data_to_send <= data; 
		if (delay == 0) begin
			fork 
				begin sim_util_pkg::flash_signal(wa_if.send,clk2); end
				begin sim_util_pkg::flash_signal(wd_if.send,clk2); end
			join
		end else begin
			if (addr_first) sim_util_pkg::flash_signal(wa_if.send,clk2);
			else sim_util_pkg::flash_signal(wd_if.send,clk2); 

			for (int i = 1; i < delay; i++) @(posedge clk); 
			if (addr_first) sim_util_pkg::flash_signal(wd_if.send,clk2);
			else sim_util_pkg::flash_signal(wa_if.send,clk2);
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
		sim_util_pkg::flash_signal(rtl_write_reqs[id],clk2); 
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
			debug.reset_timeout(clk2);
		end 
	endtask 

	task automatic write_addr_space(inout sim_util_pkg::debug debug);
		for (int addr = PS_BASE_ADDR; addr < MAPPED_ADDR_CEILING; addr+=4) begin
			ps_write(debug, addr,16'hff92);
			debug.reset_timeout(clk2);
		end 
		for (int addr = PS_BASE_ADDR; addr < MAPPED_ADDR_CEILING; addr+=4) begin
			ps_read(addr,rdata);
			mapped_memory[ADDR2ID(addr)] = rdata;
			debug.reset_timeout(clk2);
		end 
	endtask 

	task automatic check_addr_space(inout sim_util_pkg::debug debug, input bit has_written=0);
		if (has_written) begin
			for (int i = 0; i < MAPPED_ID_CEILING; i++) begin
				if (i == MAX_DAC_BURST_SIZE_ID) debug.disp_test_part(i,mapped_memory[i] == MAX_DAC_BURST_SIZE, "Max burst size incorrect");
				else if (i == DAC_BURST_SIZE_ID) debug.disp_test_part(i,mapped_memory[i] == MAX_DAC_BURST_SIZE, "Burst size should be maxed out");
				else if (i == SCALE_DAC_OUT_ID) debug.disp_test_part(i,mapped_memory[i] == MAX_SCALE_FACTOR, "Scale factor should be maxed out");
				else if (i == VERSION_ID) debug.disp_test_part(i,mapped_memory[i] == FIRMWARE_VERSION, "Version number incorrect");
				else if (i == MEM_SIZE_ID) debug.disp_test_part(i,mapped_memory[i] == MEM_SIZE, "Memory size incorrect");
				else if (is_PS_BIGREG(i) && is_PS_VALID(i)) debug.disp_test_part(i,mapped_memory[i] == 0, "Valid registers apart of big registers should be cleared after being written to");
				else debug.disp_test_part(i,mapped_memory[i] == 16'hff92, $sformatf("Memory ID %0d should have been written to. Expected %0d, Got %0d.", i,16'hff92, mapped_memory[i]));
			end
		end else begin
			for (int i = 0; i < MAPPED_ID_CEILING; i++) begin
				rtl_read(i,rdata);
				debug.reset_timeout(clk2);
				if (i == MAX_DAC_BURST_SIZE_ID) debug.disp_test_part(i,rdata == MAX_DAC_BURST_SIZE, "Default max burst size incorrect");
				else if (i == DAC_BURST_SIZE_ID) debug.disp_test_part(i,rdata == 0, "Default burst size incorrect");  
				else if (i == SCALE_DAC_OUT_ID) debug.disp_test_part(i,rdata == 0, "Default scale factor incorrect"); 
				else if (is_PS_VALID(i) || is_RTL_VALID(i)) debug.disp_test_part(i,rdata == 0, "Valid addresses reset incorrectly");
				else if (i == MEM_SIZE_ID) debug.disp_test_part(i,rdata == MEM_SIZE, "Default memory size incorrect");
				else if (i == VERSION_ID) debug.disp_test_part(i,rdata == FIRMWARE_VERSION, "Default version number incorrect");
				else debug.disp_test_part(i,$signed(rdata) == $signed(-1), $sformatf("Default value for memory ID %0d should be 0xffff. Got 0x%04x.", i, mapped_memory[i]));
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

