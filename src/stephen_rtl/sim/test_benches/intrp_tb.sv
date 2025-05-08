`default_nettype none
`timescale 1ns / 1ps



module intrp_tb #(parameter BATCH_SIZE, parameter SAMPLE_WIDTH, parameter INTERPOLATER_DELAY, parameter M, parameter N)
					   (input wire clk,
	                    input wire[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] intrp_batch,
                        input wire[BATCH_SIZE-1:0][(2*SAMPLE_WIDTH)-1:0] slopet,xpslopet,
	                    output logic[(2*SAMPLE_WIDTH)-1:0] x,slope);
	logic[INTERPOLATER_DELAY-1:0] intrp_pipe;
    logic intrp_batch_valid; 
    int expc_batch [$]; 
    logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] line; 
    logic ref_clk; 

    assign ref_clk = clk; 
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

    task automatic check_intrped_batch(inout sim_util_pkg::debug debug, input logic[(2*SAMPLE_WIDTH)-1:0] x_in, input real slope_in);
        logic[(M+N)-1:0] fixed;
    	int expc_sample;
    	for (int i = 0; i < BATCH_SIZE; i++) expc_batch.push_front($floor((fixed_to_float(x_in) + slope_in*i)+0.5));
    	slope <= float_to_fixed(slope_in); 
    	x <= x_in; 
        @(posedge clk);
    	sim_util_pkg::flash_signal(intrp_pipe[0],ref_clk);
    	while (~intrp_batch_valid) @(posedge clk); 
    	for (int i = 0; i < BATCH_SIZE; i++) begin
    		expc_sample = expc_batch.pop_back(); 
    		debug.disp_test_part(i+1, $signed(intrp_batch[i]) == expc_sample,$sformatf("Error on %0dth sample: Expected %0d, Got %0d",i+1, expc_sample, $signed(intrp_batch[i])));
    	end
        repeat (20) @(posedge clk);
    endtask 

    task automatic check_slope_bursts(inout sim_util_pkg::debug debug, input int burst_size);
        logic[(M+N)-1:0] fixed;
        int expc_sample, samples_seen;
        logic[(2*SAMPLE_WIDTH)-1:0] x_in;        
        real slope_in;
        bit done = 0;

        fork 
            begin 
                samples_seen = 0;
                while (~done) begin
                    @(posedge clk);
                    for (int i = 0; i < BATCH_SIZE; i++) line[BATCH_SIZE-1-i] = expc_batch[i]; 
                    if (intrp_batch_valid) begin    
                        for (int i = 0; i < BATCH_SIZE; i++) begin
                            expc_sample = expc_batch.pop_back();
                            debug.disp_test_part(samples_seen, $signed(intrp_batch[i]) == $signed(expc_sample),$sformatf("Error on %0dth sample: Expected %0d, Got %0d",i+1, $signed(expc_sample), $signed(intrp_batch[i])));
                            samples_seen++;
                        end 
                    end
                end
            end 
            begin 
                @(posedge clk);
                slope_in = 0;
                x_in = 0;
                for (int i = 0; i < burst_size; i++) begin
                    slope <= float_to_fixed(slope_in); 
                    x <= x_in;
                    for (int j = 0; j < BATCH_SIZE; j++) expc_batch.push_front($floor((fixed_to_float(x_in) + slope_in*j)+0.5));
                    x_in = $urandom_range(-16'h7500,16'h7500);
                    slope_in = gen_rand_real({-100,100});
                    @(posedge clk);
                    intrp_pipe[0] <= 1;
                end
                intrp_pipe[0] <= 0;
                while (intrp_batch_valid) @(posedge clk);
                done = 1; 
            end 
        join 
    endtask 
    
endmodule 

`default_nettype wire

