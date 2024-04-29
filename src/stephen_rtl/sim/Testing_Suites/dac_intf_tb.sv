`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module dac_intf_tb #(parameter VERBOSE = 1)(input wire start, output logic[1:0] done);
	localparam TOTAL_TESTS = 5; 
	localparam TIMEOUT = 10_000; 
	logic clk, rst;
	logic[15:0] timer; 

	enum logic[1:0] {IDLE, TEST, CHECK, DONE} testState; 
	logic[1:0] test_check; // test_check[0] = check, test_check[1] == 1 => test passed else test failed 
	logic[7:0] test_num; 
	logic[7:0] testsPassed, testsFailed; 
	logic kill_tb; 
	logic panic = 0; 

	Axis_IF #(`DMA_DATA_WIDTH) pwl_dma_if(); 
	assign pwl_dma_if.valid = 0;
	assign pwl_dma_if.data = 0;
	assign pwl_dma_if.ready = 0;
	assign pwl_dma_if.last = 0; 

	logic[`MEM_SIZE-1:0] fresh_bits; 
	logic[`MEM_SIZE-1:0][`WD_DATA_WIDTH-1:0] mem_map, read_resps; 
	logic[`BATCH_WIDTH-1:0] dac_batch; 
	logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] dac_samples, last_dac_out; 
	logic[`BATCH_SAMPLES-1:0][31:0] sample_diffs; 
	logic[`BATCH_SAMPLES-1:0] test_values;
	logic halt, dac0_rdy, valid_dac_batch; 
	logic[15:0] samples_seen; 

	DAC_Interface DUT (.clk(clk), .rst(rst),
	                   .fresh_bits(fresh_bits),
	                   .read_resps(read_resps),
	                   .halt(halt),
	                   .dac0_rdy(dac0_rdy),
	                   .dac_batch(dac_batch),
	                   .valid_dac_batch(valid_dac_batch),
	                   .pwl_dma_if(pwl_dma_if));

   	always_comb begin
   		for (int i = 0; i < `BATCH_SAMPLES; i++) dac_samples[i] = dac_batch[`SAMPLE_WIDTH*i+:`SAMPLE_WIDTH]; 
   	end
    oscillate_sig oscillator(.clk(clk), .rst(rst), .long_on(1'b1),
               				 .osc_sig_out(dac0_rdy));

	always_comb begin
		if (test_num == 0 || test_num == 3) begin 
			for (int i = 0; i < `BATCH_SAMPLES; i++) test_values[i] = (samples_seen != 0)? (sample_diffs[i]/samples_seen) >= 327 : 0; 
			test_check = (testState == CHECK)? {&test_values,1'b1} : 0; 
		end
		else if (test_num == 1 || test_num == 4) begin 
			test_check = (testState == CHECK)? {samples_seen == sample_diffs[0],1'b1} : 0; 
		end 
		else if (test_num == 2) begin 
			test_check = (testState == TEST && timer >= 1)? {~valid_dac_batch,valid_dac_batch || timer == 50} : 0; 			
		end 
		else test_check = 0; 
	end

	always_ff @(posedge clk) begin
		if (rst || panic) begin
			if (panic) begin
				testState <= DONE;
				kill_tb <= 1; 
				panic <= 0;
			end else begin
				testState <= IDLE;
				{test_num,testsPassed,testsFailed, kill_tb} <= 0; 
				{done,timer} <= 0;

				{fresh_bits, halt, mem_map, read_resps} <= 0; 
				{last_dac_out, sample_diffs, samples_seen} <= 0; 
			end
		end else begin
			case(testState)
				IDLE: begin 
					if (start) testState <= TEST; 
					if (done) done <= 0; 
				end 
				TEST: begin
					// Send random samples and ensure they're random enough (ie average difference between subsequent samples is large enough => greater than 1%  of the full range 0-2**15-1 => roughly 327). Do again after halting
					if (test_num == 0 || test_num == 3) begin  		
						if (timer == 300) begin
							timer <= 0; 
							testState <= CHECK; 
						end else timer <= timer + 1; 
						if (timer < `BATCH_SAMPLES) begin
							mem_map[`PS_SEED_BASE_ID + timer] <= 16'hBEEF+(timer);
							fresh_bits[`PS_SEED_BASE_ID + timer] <= 1;
						end 
						if (timer == `BATCH_SAMPLES) begin
							mem_map[`PS_SEED_VALID_ID] <= 1;
							fresh_bits[`PS_SEED_VALID_ID] <= 1; 
							{sample_diffs,samples_seen, last_dac_out} <= 0; 
						end
						if (timer > `BATCH_SAMPLES) begin						
							if (valid_dac_batch) begin
								last_dac_out <= dac_samples; 
								for (int i = 0; i < `BATCH_SAMPLES; i++) sample_diffs[i] <= (dac_samples[i] > last_dac_out[i])? (dac_samples[i] - last_dac_out[i]) + sample_diffs[i] : last_dac_out[i] - dac_samples[i] + sample_diffs[i]; 
								samples_seen <= samples_seen + 1; 
							end
						end
					end 
					// Trigger a triangle wave. Ensure the dac output is what we expect for a few cycles. Do again after halting
					if (test_num == 1 || test_num == 4) begin  		
						if (timer == 1000) begin
							timer <= 0;
							testState <= CHECK; 
						end else timer <= timer + 1;

						if (timer == 0) begin 
							mem_map[`TRIG_WAVE_ID] <= 1; 
							fresh_bits[`TRIG_WAVE_ID] <= 1;
							{samples_seen, sample_diffs} <= 0;
						end else if (timer > 3) begin
							if (valid_dac_batch) begin
								sample_diffs[0] <= (DUT.twg.trigGenState == 0)? (dac_samples[`BATCH_SAMPLES-1] >= sample_diffs[1]) + sample_diffs[0] : (dac_samples[`BATCH_SAMPLES-1] <= sample_diffs[1]) + sample_diffs[0];
								sample_diffs[1] <= dac_samples[`BATCH_SAMPLES-1]; 
								samples_seen <= samples_seen + 1; 
							end
						end
					end
					// Halt the dac, make sure it goes low the next cycle and stays that way. 
					if (test_num == 2) begin  		
						if (timer == 50 || (timer >= 1 && (valid_dac_batch || dac_batch != 0))) begin
							timer <= 0; 
							testState <= CHECK; 
						end	else timer <= timer + 1; 

						if (timer == 0) halt <= 1; 
					end
				end 
				CHECK: begin
					test_num <= test_num + 1;
					if (test_num >= TOTAL_TESTS-1) begin
                        testState <= DONE;
                        halt <= 1; 
                    end else testState <= TEST;               
				end 

				DONE: begin 
					done <= {testsFailed == 0 && ~kill_tb,1'b1}; 
					testState <= IDLE; 
					test_num <= 0; 
				end 
			endcase

			if (halt) halt <= 0; 
			`define dac_sig_rdy(index) (index >= `PS_SEED_BASE_ID && index <= `PS_SEED_VALID_ID && DUT.state_rdy) || (index == `RUN_PWL_ID && DUT.state_rdy)
			for (int i = 0; i < `MEM_SIZE; i++) begin
				if (fresh_bits[i] && (`dac_sig_rdy(i))) begin
					read_resps[i] <= mem_map[i]; 
					fresh_bits[i] <= 0; 
				end 
			end

			if (test_check[0]) begin
				if (test_check[1]) begin 
					testsPassed <= testsPassed + 1;
					if (VERBOSE) $write("%c[1;32m",27); 
					if (VERBOSE) $write("t%0d+ ",test_num);
					if (VERBOSE) $write("%c[0m",27); 
				end 
				else begin 
					testsFailed <= testsFailed + 1; 
					if (VERBOSE) $write("%c[1;31m",27); 
					if (VERBOSE) $write("t%0d- ",test_num);
					if (VERBOSE) $write("%c[0m",27); 
				end 
			end	

		end
	end

	logic[1:0] testNum_edge;
	enum logic {WATCH, PANIC} panicState; 
	logic go; 
	logic[$clog2(TIMEOUT):0] timeout_cntr; 
	edetect #(.DATA_WIDTH(8))
	testNum_edetect (.clk(clk), .rst(rst),
	 				 .val(test_num),
	 				 .comb_posedge_out(testNum_edge)); 

	always_ff @(posedge clk) begin 
		if (rst) begin 
			{timeout_cntr,panic} <= 0;
			panicState <= WATCH;
			if (start) go <= 1; 
			else go <= 0; 
		end 
		else begin
			if (start) go <= 1;
			if (go) begin
				case(panicState) 
					WATCH: begin
						if (timeout_cntr <= TIMEOUT) begin
							if (testNum_edge == 1) timeout_cntr <= 0;
							else timeout_cntr <= timeout_cntr + 1;
						end else begin
							panic <= 1; 
							panicState <= PANIC; 
						end 
					end 
					PANIC: if (panic) panic <= 0; 
				endcase
			end 
		end
	end 

	always begin
	    #5;  
	    clk = !clk;
	end
	 
    initial begin
        clk = 0;
        rst = 0; 
        `flash_sig(rst); 
        while (~start) #1; 
        if (VERBOSE) $display("\n############ Starting DAC-Interface Tests ############");
        #100;
        while (testState != DONE && timeout_cntr < TIMEOUT) #10;
        if (timeout_cntr < TIMEOUT) begin
	        if (testsFailed != 0) begin 
	        	if (VERBOSE) $write("%c[1;31m",27); 
	        	if (VERBOSE) $display("\nDAC-Interface Tests Failed :((\n");
	        	if (VERBOSE) $write("%c[0m",27);
	        end else begin 
	        	if (VERBOSE) $write("%c[1;32m",27); 
	        	if (VERBOSE) $display("\nDAC-Interface Tests Passed :))\n");
	        	if (VERBOSE) $write("%c[0m",27); 
	        end
	        #100;
	    end else begin
	    	$write("%c[1;31m",27); 
	        $display("\nDAC-Interface Tests Timed out on test %d!\n", test_num);
	        $write("%c[0m",27);
	        #100; 
	    end
    end 

endmodule 

`default_nettype wire
