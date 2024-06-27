`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"

module cdc_tb #(parameter PS_CMD_WIDTH, parameter DAC_RSP_WIDTH)
			   (input  wire ps_clk, dac_clk, 
			   	input  wire[PS_CMD_WIDTH-1:0] ps_cmd_out,
			   	input  wire ps_cmd_valid_out, ps_cmd_transfer_rdy, ps_cmd_transfer_done,
			   	input  wire[DAC_RSP_WIDTH-1:0] dac_resp_out,
 				input  wire dac_resp_valid_out, dac_resp_transfer_rdy, dac_resp_transfer_done,
			   	output logic ps_rst, dac_rst, 
			   	output logic[PS_CMD_WIDTH-1:0] ps_cmd_in,
			   	output logic ps_cmd_valid_in,
			   	output logic[DAC_RSP_WIDTH-1:0] dac_resp_in, 
			   	output logic dac_resp_valid_in);

	task automatic init();
		{ps_cmd_in,ps_cmd_valid_in} <= 0;
		{dac_resp_in,dac_resp_valid_in} <= 0; 
		fork 
			begin `flash_signal(ps_rst,ps_clk) end 
			begin `flash_signal(dac_rst, dac_clk) end 
		join 
	endtask 

	task automatic send_ps_cmds(inout sim_util_pkg::debug debug, input int cmds_to_send, input bit rand_wait = 0);
		repeat(cmds_to_send) begin
			while (~ps_cmd_transfer_rdy) @(posedge ps_clk);
			for (int i = 0; i < PS_CMD_WIDTH; i+=32) ps_cmd_in[i+:32] <= $urandom();
			`flash_signal(ps_cmd_valid_in,ps_clk); 
			fork 
				begin
					debug.disp_test_part(1,ps_cmd_in != ps_cmd_out,$sformatf("ps_cmd should not have transferred yet: %h == %h",ps_cmd_in, ps_cmd_out)); 
					while (~ps_cmd_valid_out) @(posedge dac_clk); 
					debug.disp_test_part(2,ps_cmd_in == ps_cmd_out,$sformatf("Recieved ps_cmd is incorrect: %h != %h",ps_cmd_in, ps_cmd_out)); 
				end 
				begin 
					while (~ps_cmd_transfer_done) @(posedge ps_clk); 
					debug.disp_test_part(3,1'b1,"");
				end 
			join 
			if (rand_wait) repeat($urandom_range(10,50)) @(posedge ps_clk); 
		end 
	endtask 

	task automatic send_dac_resp(inout sim_util_pkg::debug debug, input int cmds_to_send, input bit rand_wait = 0);
		repeat(cmds_to_send) begin 
			while (~dac_resp_transfer_rdy) @(posedge dac_clk);
			for (int i = 0; i < DAC_RSP_WIDTH; i+=32) dac_resp_in[i+:32] <= $urandom();
			`flash_signal(dac_resp_valid_in, dac_clk); 
			fork 
				begin
					debug.disp_test_part(1,dac_resp_in != dac_resp_out,$sformatf("dac_resp should not have transferred yet: %h == %h",dac_resp_out, dac_resp_in)); 
					while (~dac_resp_valid_out) @(posedge ps_clk); 
					debug.disp_test_part(2,dac_resp_in == dac_resp_out,$sformatf("Recieved dac_resp is incorrect: %h != %h",dac_resp_out, dac_resp_in)); 
				end 
				begin 
					while (~dac_resp_transfer_done) @(posedge dac_clk); 
					debug.disp_test_part(3,1'b1,"");
				end 
			join 
			if (rand_wait) repeat($urandom_range(10,50)) @(posedge dac_clk); 
		end 
	endtask 
endmodule 

`default_nettype wire

