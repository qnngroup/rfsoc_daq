`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module axi_recieve_transmit_tb #(parameter VERBOSE = 1)(input wire start, output logic[1:0] done);
	localparam TOTAL_TESTS = `ADDR_NUM + 19; 
	localparam TIMEOUT = 10_000;

	logic clk, rst;
	logic kill_test; 

	Recieve_Transmit_IF #(`A_BUS_WIDTH, `A_DATA_WIDTH) wa_if (); 
	Recieve_Transmit_IF #(`WD_BUS_WIDTH, `WD_DATA_WIDTH) wd_if (); 
	assign wa_if.dev_rdy = 1'b1; 
	assign wd_if.dev_rdy = 1'b1; 

	axi_receive #(.BUS_WIDTH(`A_BUS_WIDTH), .DATA_WIDTH(`A_DATA_WIDTH))
	addr_recieve(.clk(clk), .rst(rst),
	             .bus(wa_if.receive_bus),
	             .is_addr(1'b1));	

	axi_receive #(.BUS_WIDTH(`WD_BUS_WIDTH), .DATA_WIDTH(`WD_DATA_WIDTH))
	data_recieve(.clk(clk), .rst(rst),
	             .bus(wd_if.receive_bus),
	             .is_addr(1'b0));

	axi_transmit #(.BUS_WIDTH(`A_BUS_WIDTH), .DATA_WIDTH(`A_DATA_WIDTH))
	addr_transmit(.clk(clk), .rst(rst),
	              .bus(wa_if.transmit_bus));

	axi_transmit #(.BUS_WIDTH(`WD_BUS_WIDTH), .DATA_WIDTH(`WD_DATA_WIDTH))
	wd_transmit(.clk(clk), .rst(rst),
	            .bus(wd_if.transmit_bus));

	edetect #(.DATA_WIDTH(8))
	correct_ed(.clk(clk), .rst(rst),
	           .val(correct_steps),
	           .comb_posedge_out(correct_steps_edge));

	enum logic[2:0] {IDLE, TEST, ADDR_VALID, CHECK, DONE} testState; 
	logic[1:0] test_check; // test_check[0] = check, test_check[1] == 1 => test passed else test failed 
	logic[7:0] test_num; 
	logic[7:0] testsPassed, testsFailed; 

	logic[`WD_DATA_WIDTH-1:0] curr_id;
	logic[7:0] correct_steps, timer;
	logic[1:0] correct_steps_edge, bigreg_cnter; 
	logic[$clog2(`MEM_SIZE):0] curr_bigreg_width;
	assign curr_id = (test_num < `ADDR_NUM)? ids[test_num] : 0; 

	always_comb begin
		if (test_num < `ADDR_NUM) 
			test_check = (testState == CHECK && wa_if.valid_data)? {(wa_if.data == curr_id),1'b1} : 0;
		else if (test_num >= `ADDR_NUM && test_num <= `ADDR_NUM + 17)
			test_check = (testState == CHECK && wd_if.valid_data)? {(wd_if.data_to_send == wd_if.data),1'b1} : 0;
		else if (test_num == `ADDR_NUM + 18)
			test_check = (correct_steps_edge != 0)? {(correct_steps_edge == 1),1'b1} : 0; 
		else test_check = 0; 

		case(bigreg_cnter)
			0: curr_bigreg_width = (`PS_SEED_VALID_ID - `PS_SEED_BASE_ID)+1;
			1: curr_bigreg_width = (`BUFF_TIME_VALID_ID - `BUFF_TIME_BASE_ID)+1;
			2: curr_bigreg_width = (`CHAN_MUX_VALID_ID - `CHAN_MUX_BASE_ID)+1;
			3: curr_bigreg_width = (`SDC_VALID_ID - `SDC_BASE_ID)+1;
		endcase
	end

	always_ff @(posedge clk) begin
		if (rst || panic) begin
			if (panic) begin
				testState <= DONE;
				kill_test <= 1; 
				panic <= 0;
			end else begin
				testState <= IDLE;
				{test_num,testsPassed,testsFailed} <= 0; 
				{done,kill_test} <= 0;
				
				{wa_if.data_to_send, wd_if.data_to_send} <= 0;
				{wd_if.send, wa_if.send} <= 0; 
				{timer, correct_steps, bigreg_cnter} <= 0; 
			end
		end else begin
			case(testState)
				IDLE: begin 
					if (start) testState <= TEST; 
					if (done) done <= 0; 
				end 
				TEST: begin
					// Send all addrs and ensure the correct mem_id is recieved 
					if (test_num < `ADDR_NUM) begin 
						if (wa_if.trans_rdy) begin
							wa_if.data_to_send <= addrs[test_num];
							wa_if.send <= 1;
							testState <= CHECK;
						end 
					end 
					// Send random data and ensure that data is recieved. 
					if (test_num >= `ADDR_NUM && test_num <= `ADDR_NUM + 17) begin 
						if (wd_if.trans_rdy) begin 
							wd_if.data_to_send <= (test_num != `ADDR_NUM + 17)? 32'hBEEF << test_num-13 : -1;
							wd_if.send <= 1; 
							testState <= CHECK;
						end
					end 

					// Send data to areas between base and valid addresses (many address wide registers) 
					if (test_num == `ADDR_NUM + 18) begin 
						if (timer == curr_bigreg_width) begin
							timer <= 0;
							if (bigreg_cnter == 3) testState <= CHECK;
							else bigreg_cnter <= bigreg_cnter + 1; 
						end else  
						if (timer <= (`PS_SEED_VALID_ID - `PS_SEED_BASE_ID)) begin 
							if (wa_if.trans_rdy) begin
								case(bigreg_cnter)
									0:wa_if.data_to_send <= `PS_SEED_BASE_ADDR + (timer << 2); 
									1:wa_if.data_to_send <= `BUFF_TIME_BASE_ADDR + (timer << 2); 
									2:wa_if.data_to_send <= `CHAN_MUX_BASE_ADDR + (timer << 2); 
									3:wa_if.data_to_send <= `SDC_BASE_ADDR + (timer << 2); 
								endcase 
								wa_if.send <= 1;
								testState <= ADDR_VALID; 
							end
						end 
					end 
				end 
				ADDR_VALID: begin
					if (wa_if.valid_data) begin
						case(bigreg_cnter)
							0: correct_steps <= (wa_if.data == `PS_SEED_BASE_ID + timer)? correct_steps + 1 : correct_steps - 1;
							1: correct_steps <= (wa_if.data == `BUFF_TIME_BASE_ID + timer)? correct_steps + 1 : correct_steps - 1;
							2: correct_steps <= (wa_if.data == `CHAN_MUX_BASE_ID + timer)? correct_steps + 1 : correct_steps - 1;
							3: correct_steps <= (wa_if.data == `SDC_BASE_ID + timer)? correct_steps + 1 : correct_steps - 1; 
						endcase 
						timer <= timer + 1; 
						testState <= TEST;  
					end
				end 
				CHECK: begin
					if (test_num < `ADDR_NUM + 18) begin 
						if (wa_if.valid_data || wd_if.valid_data) begin
							test_num <= test_num + 1;
							testState <= (test_num == TOTAL_TESTS-1)? DONE : TEST; 
						end
					end else begin
						test_num <= test_num + 1;
						testState <= (test_num == TOTAL_TESTS-1)? DONE : TEST; 
					end
				end 
				DONE: begin 
					done <= {testsFailed == 0 && ~kill_test,1'b1};
					testState <= IDLE; 
					test_num <= 0; 
				end 
			endcase 

			if (wa_if.send) wa_if.send <= 0; 
			if (wd_if.send) wd_if.send <= 0; 

			if (test_num == `ADDR_NUM + 18) begin
				if (test_check[0]) begin
					if (test_check[1]) begin 
						testsPassed <= testsPassed + 1;
						if (VERBOSE) $write("%c[1;32m",27); 
						if (VERBOSE) $write("t%0d_%0d+ ",test_num,timer);
						if (VERBOSE) $write("%c[0m",27); 
					end 
					else begin 
						testsFailed <= testsFailed + 1; 
						if (VERBOSE) $write("%c[1;31m",27); 
						if (VERBOSE) $write("t%0d_%0d- ",test_num,timer);
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
	logic panic = 0; 
	logic go; 
	enum logic {WATCH, PANIC} panicState; 
	logic[$clog2(TIMEOUT):0] timeout_cntr; 
	edetect testNum_edetect(.clk(clk), .rst(rst),
                            .val(test_num),
                            .comb_posedge_out(testNum_edge)); 

	always_ff @(posedge clk) begin 
		if (rst) begin 
			{timeout_cntr,panic} <= 0;
			panicState <= WATCH;
			go <= 0; 
		end 
		else begin
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
			if (start) go <= 1; 
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
        if (VERBOSE) $display("\n############ Starting Axi-Recieve/Transmit Tests ############");
        #100;
        while (testState != DONE && timeout_cntr < TIMEOUT) #10;
        if (timeout_cntr < TIMEOUT) begin
	        if (testsFailed != 0) begin 
	        	if (VERBOSE) $write("%c[1;31m",27); 
	        	if (VERBOSE) $display("\nAxi-Recieve/Transmit Tests Failed :((\n");
	        	if (VERBOSE) $write("%c[0m",27);
	        end else begin 
	        	if (VERBOSE) $write("%c[1;32m",27); 
	        	if (VERBOSE) $display("\nAxi-Recieve/Transmit Tests Passed :))\n");
	        	if (VERBOSE) $write("%c[0m",27); 
	        end
	        #100; 
		end else begin
	    	$write("%c[1;31m",27); 
	        $display("\nAxi-Recieve/Transmi Tests Timed out on test %d!\n", test_num);
	        $write("%c[0m",27);
	    end
	    #100; 
    end 

endmodule 

`default_nettype wire

