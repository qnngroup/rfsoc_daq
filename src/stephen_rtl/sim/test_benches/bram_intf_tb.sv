`default_nettype none
`timescale 1ns / 1ps

module bram_intf_tb #(parameter DATA_WIDTH, parameter BRAM_DEPTH)
					 (input wire clk,
					  input wire[DATA_WIDTH-1:0] line_out,
					  input wire valid_line_out,
					  input wire[$clog2(BRAM_DEPTH)-1:0] generator_addr,
					  input wire write_rdy,
					  output logic rst, 
					  output logic [$clog2(BRAM_DEPTH)-1:0] addr,
					  output logic[DATA_WIDTH-1:0] line_in,
					  output logic we, en, 
					  output logic generator_mode, clr_bram, 
					  output logic next);
	logic clk2; 
	assign clk2 = clk; 
	logic[DATA_WIDTH-1:0] expc [$]; 
	
	task automatic init(input bit do_rst = 1);
		clear_expc();
		{addr,line_in,we,en,generator_mode,clr_bram,next} <= 0;
		if (do_rst) sim_util_pkg::flash_signal(rst,clk2);
		else @(posedge clk);
	endtask 

	function void clear_expc();
		while (expc.size() > 0) expc.pop_back();
	endfunction


	task automatic write_rands(int write_depth);
		init(.do_rst(0));
		clear_bram();  
		while (~write_rdy) @(posedge clk); 
		{we,en} <= 3; 
		do begin 
			for (int i = 0; i < DATA_WIDTH; i+=32) line_in[i+:32] <= $urandom();			
			@(posedge clk);
			expc.push_front(line_in); 
			addr <= addr + 1; 
		end while (addr < write_depth-1);
		{addr,we,en,line_in} <= 0;
		generator_mode <= 1;
		while (~valid_line_out) @(posedge clk); 
	endtask  

	task automatic check_bram_vals(inout sim_util_pkg::debug debug, input int cycles_to_check = 1, input bit osc_next = 0);
		int bram_len = expc.size();
		bit done = 0; 
		bit err = 0;
		string err_msg; 
		logic[DATA_WIDTH-1:0] expc_data;
		next <= 0;
		do begin @(posedge clk); end while (~valid_line_out); 
		if (osc_next) begin
			fork
				begin 
					while (~done) begin
						next <= ~next;
						repeat($urandom_range(1,20)) @(posedge clk); 
					end 
					next <= 0;
					@(posedge clk);
				end 
			join_none
		end else next <= 1;
		repeat(cycles_to_check) begin 
			for (int i = 0; i < bram_len; i++) begin
				do begin @(posedge clk); end while (~next); 
				expc_data = expc.pop_back(); 
				expc.push_front(expc_data); 
				if (line_out != expc_data || generator_addr != i) err = 1;
				err_msg = (line_out == expc_data)? $sformatf("expc addr %h != %h", i, generator_addr) : $sformatf("addr %h == %h, not %h", i, expc_data, line_out);
				debug.disp_test_part(i+1, ~err,err_msg);
				err = 0;
			end
		end 
		done = 1; 
	endtask 

	task automatic check_few_bram_vals(inout sim_util_pkg::debug debug, input int vals_to_check);
		logic[DATA_WIDTH-1:0] tmp1 [$];
		logic[DATA_WIDTH-1:0] tmp2 [$];
		int bram_len = expc.size();
		if (vals_to_check > bram_len) vals_to_check = bram_len;
		for (int i = 0; i < vals_to_check; i++) tmp1.push_front(expc.pop_back());
		tmp2 = expc; 
		expc = tmp1; 
		check_bram_vals(debug,.cycles_to_check(1), .osc_next(1));
		expc = tmp2; 
		for (int i = 0; i < vals_to_check; i++) expc.push_back(tmp1.pop_front());
	endtask 

	task automatic clear_bram();
		generator_mode <= 0;
		sim_util_pkg::flash_signal(clr_bram,clk2);  
	endtask 

	task automatic reset_generator(input bit rand_flash = 0);
		generator_mode <= 0;
		if (rand_flash) begin
			repeat($urandom_range(1,10)) begin
				generator_mode <= 1;
				repeat($urandom_range(1,5)) @(posedge clk);
				generator_mode <= 0;
				repeat($urandom_range(1,5)) @(posedge clk);
			end
		end
		@(posedge clk);
		generator_mode <= 1;
		@(posedge clk);
	endtask 

endmodule 

`default_nettype wire

