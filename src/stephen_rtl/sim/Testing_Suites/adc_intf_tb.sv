`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module adc_intf_tb #(parameter VERBOSE = 1)(input wire start, output logic[1:0] done);
	localparam TOTAL_TESTS = 1; 
	localparam TIMEOUT = 10_000; 
	logic clk, rst;

	enum logic[1:0] {IDLE, TEST, CHECK, DONE} testState; 
	logic[1:0] test_check; // test_check[0] = check, test_check[1] == 1 => test passed else test failed 
	logic[7:0] test_num; 
	logic[7:0] testsPassed, testsFailed;
	logic[7:0] timer, correct_steps; 
	logic[1:0] correct_steps_changed;
	logic kill_tb; 
	logic panic = 0; 

	Axis_IF #(`BUFF_TIMESTAMP_WIDTH) bufft_if(); 
    Axis_IF #(`BUFF_CONFIG_WIDTH) buffc_if();
    Axis_IF #(`CHANNEL_MUX_WIDTH) cmc_if();
    Axis_IF #(`SDC_DATA_WIDTH) sdc_if(); 

	logic[`MEM_SIZE-1:0] fresh_bits; 
	logic[`MEM_SIZE-1:0][`WD_DATA_WIDTH-1:0] mem_map, read_resps; 
	logic[`CHAN_SAMPLES-1:0][`WD_DATA_WIDTH-1:0] exp_cmc_data; 
	logic[`SDC_SAMPLES-1:0][`WD_DATA_WIDTH-1:0] exp_sdc_data; 

	assign bufft_if.last = bufft_if.valid;
	ADC_Interface DUT(.clk(clk), .rst(rst),
                      .fresh_bits(fresh_bits),
                      .read_resps(read_resps),
                      .bufft(bufft_if.stream_in),
                      .buffc(buffc_if.stream_out),
                      .cmc(cmc_if.stream_out),
                      .sdc(sdc_if.stream_out));

	edetect #(.DATA_WIDTH(8))
	correct_ed(.clk(clk), .rst(rst),
	           .val(correct_steps),
	           .comb_posedge_out(correct_steps_changed)); 

	always_comb begin
		for (int i = 0; i < `CHAN_SAMPLES; i++) exp_cmc_data[i] = i+69;
		for (int i = 0; i < `SDC_SAMPLES; i++) exp_sdc_data[i] = i;
		if (test_num == 0) 
			test_check = (correct_steps_changed != 0)? {correct_steps_changed == 1, 1'b1} : 0;
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
				{done,timer,correct_steps} <= 0;

				{fresh_bits, mem_map, read_resps} <= 0; 
				{buffc_if.ready, cmc_if.ready, sdc_if.ready} <= 0;
				{bufft_if.data, bufft_if.valid} <= 0; 
			end
		end else begin
			case(testState)
				IDLE: begin 
					if (start) testState <= TEST; 
					if (done) done <= 0; 
				end 
				TEST: begin
					// Write to all ADC addresses, and ensure the correct quantities are recorded. 
					if (test_num == 0) begin
						if (sdc_if.valid && sdc_if.ready)          correct_steps <= (sdc_if.data == exp_sdc_data)? correct_steps + 1 : correct_steps - 1; 
						else if (cmc_if.valid && cmc_if.ready)     correct_steps <= (cmc_if.data == exp_cmc_data)? correct_steps + 1 : correct_steps - 1; 
						else if (buffc_if.valid && buffc_if.ready) correct_steps <= (buffc_if.data == 4'hA)? correct_steps + 1 : correct_steps - 1; 

						if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+59) begin
							timer <= 0;
							testState <= CHECK;
						end else timer <= timer + 1; 

						if (timer == 0) correct_steps <= 0; 
						if (timer >= 0 && timer < `SDC_SAMPLES) begin
							mem_map[`SDC_BASE_ID+timer] <= timer; 
							fresh_bits[`SDC_BASE_ID+timer] <= 1;
						end	
						if (timer == `SDC_SAMPLES) begin
							mem_map[`SDC_VALID_ID] <= 1; 
							fresh_bits[`SDC_VALID_ID] <= 1;
						end
						if (timer > `SDC_SAMPLES && timer <= `SDC_SAMPLES+`CHAN_SAMPLES) begin
							mem_map[`CHAN_MUX_BASE_ID+(timer-`SDC_SAMPLES-1)] <= (timer-`SDC_SAMPLES-1)+69;
							fresh_bits[`CHAN_MUX_BASE_ID+(timer-`SDC_SAMPLES-1)] <= 1; 
						end
						if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+1) begin 
							mem_map[`CHAN_MUX_VALID_ID] <= 1; 
							fresh_bits[`CHAN_MUX_VALID_ID] <= 1;
						end 
						if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+3) begin
							mem_map[`BUFF_CONFIG_ID] <= 4'hA; 
							fresh_bits[`BUFF_CONFIG_ID] <= 1; 
						end	
						if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+40) begin
							correct_steps <= (buffc_if.valid && cmc_if.valid && sdc_if.valid)? correct_steps + 1 : correct_steps - 1;
						end 
						if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+50) buffc_if.ready <= 1;
						if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+52) correct_steps <= (~buffc_if.valid)? correct_steps + 1 : correct_steps - 1;												
						if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+53) cmc_if.ready <= 1;	
						if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+55) correct_steps <= (~cmc_if.valid)? correct_steps + 1 : correct_steps - 1;					
						if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+56) sdc_if.ready <= 1;	
						if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+58) correct_steps <= (~sdc_if.valid)? correct_steps + 1 : correct_steps - 1;					
					end 
				end 
				CHECK: begin
					test_num <= test_num + 1;
					if (test_num >= TOTAL_TESTS-1) testState <= DONE;
                    else testState <= TEST;               
				end 

				DONE: begin 
					done <= {testsFailed == 0 && ~kill_tb,1'b1}; 
					testState <= IDLE; 
					test_num <= 0; 
				end 
			endcase

			if (sdc_if.ready) sdc_if.ready <= 0; 
			if (cmc_if.ready) cmc_if.ready <= 0; 
			if (buffc_if.ready) buffc_if.ready <= 0; 
			for (int i = 0; i < `MEM_SIZE; i++) begin
				if (fresh_bits[i] && DUT.state_rdy) begin
					read_resps[i] <= mem_map[i]; 
					fresh_bits[i] <= 0; 
				end 
			end

			if (test_num == 0) begin
				if (test_check[0]) begin
					if (test_check[1]) begin 
						testsPassed <= testsPassed + 1;
						if (VERBOSE) $write("%c[1;32m",27); 
						if (VERBOSE) $write("t%0d_%0d+ ",test_num,correct_steps);
						if (VERBOSE) $write("%c[0m",27); 
					end 
					else begin 
						testsFailed <= testsFailed + 1; 
						if (VERBOSE) $write("%c[1;31m",27); 
						if (VERBOSE) $write("t%0d_%0d- ",test_num,correct_steps);
						if (VERBOSE) $write("%c[0m",27); 
					end 
				end	
			end else begin
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
        if (VERBOSE) $display("\n############ Starting ADC-Interface Tests ############");
        #100;
        while (testState != DONE && timeout_cntr < TIMEOUT) #10;
        if (timeout_cntr < TIMEOUT) begin
	        if (testsFailed != 0) begin 
	        	if (VERBOSE) $write("%c[1;31m",27); 
	        	if (VERBOSE) $display("\nADC-Interface Tests Failed :((\n");
	        	if (VERBOSE) $write("%c[0m",27);
	        end else begin 
	        	if (VERBOSE) $write("%c[1;32m",27); 
	        	if (VERBOSE) $display("\nADC-Interface Tests Passed :))\n");
	        	if (VERBOSE) $write("%c[0m",27); 
	        end
	        #100;
	    end else begin
	    	$write("%c[1;31m",27); 
	        $display("\nADC-Interface Tests Timed out on test %d!\n", test_num);
	        $write("%c[0m",27);
	        #100; 
	    end
    end 

endmodule 

`default_nettype wire
