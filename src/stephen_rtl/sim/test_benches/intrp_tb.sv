`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"
// import mem_layout_pkg::flash_signal;
module intrp_tb #(parameter BATCH_SIZE, parameter SAMPLE_WIDTH, parameter INTERPOLATER_DELAY, parameter M, parameter N)
					   (input wire clk,
	                    input wire[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] intrp_batch,
                        input wire[BATCH_SIZE-1:0][(2*SAMPLE_WIDTH)-1:0] slopet,xpslopet,
					    output logic[SAMPLE_WIDTH-1:0] x,
	                    output logic[(2*SAMPLE_WIDTH)-1:0] slope);
	logic[INTERPOLATER_DELAY-1:0] intrp_pipe;
    logic intrp_batch_valid; 
    logic clk2;
    int expc_batch [$]; 

    assign clk2 = clk;
    assign intrp_batch_valid = intrp_pipe[INTERPOLATER_DELAY-1]; 
    always_ff @(posedge clk) intrp_pipe[INTERPOLATER_DELAY-1:1] <= intrp_pipe[INTERPOLATER_DELAY-2:0];

    task automatic init();                
        {x,slope,intrp_pipe[0]} <= 0;
        @(posedge clk); 
    endtask 

    function automatic logic[(M+N)-1:0]  float_to_fixed(real num);
    	real fixed = (num < 0)? -(num*2**N) : num*2**N;
    	logic[(M+N)-1:0] fixed_vector;
    	int fixed_i = fixed;
    	fixed_vector = fixed_i;    	
    	if (num < 0) fixed_vector = (~fixed_vector)+1; 
    	return fixed_vector;
    endfunction 

     function automatic real fixed_to_float(logic[(M+N)-1:0] fixed);
    	real out = 0; 
    	for (int i = M+N-1; i >= 0; i--) begin
			if (fixed[i]) out = (i==M+N-1)?  out - real'(2)**(i-N) : out + real'(2)**(i-N);   		
    	end
    	return out; 
    endfunction

    function automatic real gen_rand_real(int range[2]);
        real fract = real'($urandom_range(0,(1<<16)-1)) / real'((1<<16)-1);
        int rand_real = $urandom_range(range[0],range[1]);
        return real'(rand_real)+fract;
    endfunction 

    task automatic check_intrped_batch(inout sim_util_pkg::debug debug, int x_in, real slope_in);
        logic[(M+N)-1:0] fixed;
    	int expc_sample;
    	for (int i = 0; i < BATCH_SIZE; i++) expc_batch.push_front($floor((x_in + slope_in*i)+0.5));
    	slope <= float_to_fixed(slope_in); 
    	x <= x_in; 
    	`flash_signal(intrp_pipe[0],clk2);
    	while (~intrp_batch_valid) @(posedge clk); 
    	for (int i = 0; i < BATCH_SIZE; i++) begin
    		expc_sample = expc_batch.pop_back(); 
    		debug.disp_test_part(i+1, $signed(intrp_batch[i]) == expc_sample,$sformatf("Error on %0dth sample: Expected %0d, Got %0d",i+1, expc_sample, $signed(intrp_batch[i])));
    	end 
    endtask 
    
endmodule 

`default_nettype wire

