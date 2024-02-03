`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module slave_tb #(parameter VERBOSE = 1)(input wire start, output logic[1:0] done);
	localparam TOTAL_TESTS = 3*`ADDR_NUM + 15; 
	localparam TIMER_DELAY = 55;
	localparam OSC_DELAY = 5;
	localparam TIMEOUT = 10_000; 

	logic clk, rst;
	logic panic = 0; 
	logic[`WD_DATA_WIDTH-1:0] rand_val, read_data;
	logic ps_read_rdy, ps_wrsp_rdy; 
	logic[`MEM_SIZE-1:0] rtl_write_reqs, rtl_read_reqs, fresh_bits, rtl_rdy; 
	logic[`MEM_SIZE-1:0][`WD_DATA_WIDTH-1:0] rtl_wd_in, rtl_rd_out;
	logic[$clog2(`ADDR_NUM)-1:0] curr_addr_idx;
	logic[7:0] timer, correct_steps, idx; 
	logic osc_sig, long_on; 
	logic[1:0] got_wresp;  //[1] == error bit (wr_if.data wasn't okay when recieved), [0] == sys saw a wr_if.data 

	enum logic[2:0] {IDLE, TEST, READ_DATA, WRESP_WAIT, CHECK, DONE} testState; 
	logic[1:0] test_check; // test_check[0] = check, test_check[1] == 1 => test passed else test failed 
	logic[7:0] test_num; 
	logic[7:0] testsPassed, testsFailed; 
	logic kill_tb; 

	logic[`WD_DATA_WIDTH-1:0] curr_data_memmap, curr_data_rtlreadout, rtlreadoutTest;
	logic[`A_DATA_WIDTH-1:0] curr_id, curr_test_id; 
	logic[1:0] wasWritten; 

	Recieve_Transmit_IF #(`A_BUS_WIDTH, `A_DATA_WIDTH)   wa_if (); 
	Recieve_Transmit_IF #(`WD_BUS_WIDTH, `WD_DATA_WIDTH) wd_if (); 
	Recieve_Transmit_IF #(`A_BUS_WIDTH, `A_DATA_WIDTH)   ra_if (); 
	Recieve_Transmit_IF #(`WD_BUS_WIDTH, `WD_DATA_WIDTH) rd_if (); 
	Recieve_Transmit_IF #(2,2) wr_if (); 
	Recieve_Transmit_IF #(2,2) rr_if ();

	assign wd_if.dev_rdy = 1;
	assign wa_if.dev_rdy = 1; 
	assign ra_if.dev_rdy = 1; 
	assign rd_if.dev_rdy = ps_read_rdy;
	assign wr_if.dev_rdy = ps_wrsp_rdy; 

	axi_slave #(.A_BUS_WIDTH(`A_BUS_WIDTH), .A_DATA_WIDTH(`A_DATA_WIDTH), .WD_BUS_WIDTH(`WD_BUS_WIDTH), .WD_DATA_WIDTH(`WD_DATA_WIDTH))
	DUT(.clk(clk), .rst(rst),
		.waddr_if(wa_if),
		.wdata_if(wd_if),
		.raddr_if(ra_if),
		.rdata_if(rd_if),
		.wresp_if(wr_if),
		.rresp_if(rr_if),
	   .rtl_write_reqs(rtl_write_reqs), .rtl_read_reqs(rtl_read_reqs),
	   .rtl_rdy(rtl_rdy),
	   .rtl_wd_in(rtl_wd_in), 				//in
	   .rtl_rd_out(rtl_rd_out),				//out 
	   .fresh_bits(fresh_bits));

	assign {rr_if.data, rr_if.valid_data} = 0;
	assign {rr_if.dev_rdy, rr_if.data_to_send, rr_if.send, rr_if.trans_rdy} = 0; 

	axi_receive #(.BUS_WIDTH(2), .DATA_WIDTH(2))
	ps_wresp_recieve(.clk(clk), .rst(rst),
	                 .bus(wr_if.receive_bus),
	                 .is_addr(1'b0)); 
	axi_receive #(.BUS_WIDTH(`WD_BUS_WIDTH), .DATA_WIDTH(`WD_DATA_WIDTH))
	ps_rdata_recieve(.clk(clk), .rst(rst),
	                 .bus(rd_if.receive_bus),
	                 .is_addr(1'b0));
	axi_transmit #(.BUS_WIDTH(`WD_BUS_WIDTH), .DATA_WIDTH(`WD_DATA_WIDTH))
	ps_wdata_transmit(.clk(clk), .rst(rst),
	                  .bus(wd_if.transmit_bus)); 
	axi_transmit #(.BUS_WIDTH(`A_BUS_WIDTH), .DATA_WIDTH(`A_DATA_WIDTH))
	ps_waddr_transmit(.clk(clk), .rst(rst),
	                  .bus(wa_if.transmit_bus));
	axi_transmit #(.BUS_WIDTH(`A_BUS_WIDTH), .DATA_WIDTH(`A_DATA_WIDTH))
	ps_raddr_transmit(.clk(clk), .rst(rst),
	                  .bus(ra_if.transmit_bus)); 

	LFSR #(.DATA_WIDTH (`WD_DATA_WIDTH))
	rand_num_gen(.clk(clk), .rst(rst),
	             .seed((`WD_DATA_WIDTH)'(-1)),
	             .run(testState != IDLE),
	             .sample_out(rand_val));
	oscillate_sig #(.DELAY (OSC_DELAY))
	oscillator(.clk(clk), .rst(rst), .long_on(long_on),
               .osc_sig_out(osc_sig));
	edetect fbit_edetect(.clk(clk), .rst(rst),
	                     .val(fresh_bits[curr_id]),
	                     .comb_posedge_out(wasWritten));

	assign curr_id = ids[curr_addr_idx];
	assign curr_data_memmap = DUT.mem_map[curr_id]; 
	assign curr_data_rtlreadout = rtl_rd_out[curr_id];
	assign curr_test_id = ids[idx]; 
	assign rtlreadoutTest = rtl_rd_out[curr_test_id];
	always_comb begin
		if (test_num <= 3*`ADDR_NUM + 1 || test_num == 3*`ADDR_NUM + 8) begin 
			if (curr_id == `MAX_BURST_SIZE_ID) 
				test_check = (rd_if.valid_data)? {(rd_if.data == `MAX_ILA_BURST_SIZE) && (curr_data_memmap == rd_if.data) && (DUT.fresh_bits[curr_id] == 0) ,1'b1} : 0;
			else if (curr_id == `MEM_SIZE_ID)
				test_check = (rd_if.valid_data)? {(rd_if.data == `MEM_SIZE) && (curr_data_memmap == rd_if.data) && (DUT.fresh_bits[curr_id] == 0) ,1'b1} : 0;
			else if (curr_id == `ILA_BURST_SIZE_ID && wd_if.data_to_send > `MAX_ILA_BURST_SIZE)
				test_check = (rd_if.valid_data)? {(rd_if.data == `MAX_ILA_BURST_SIZE) && (curr_data_memmap == `MAX_ILA_BURST_SIZE) && (DUT.fresh_bits[curr_id] == 0) ,1'b1} : 0; 
			else if (curr_id == `SCALE_DAC_OUT_ID && wd_if.data_to_send > `MAX_SCALE_FACTOR)
				test_check = (rd_if.valid_data)? {(rd_if.data == `MAX_SCALE_FACTOR) && (curr_data_memmap == `MAX_SCALE_FACTOR) && (DUT.fresh_bits[curr_id] == 0) ,1'b1} : 0; 
			else if (curr_id == `VERSION_ID)
				test_check = (rd_if.valid_data)? {(rd_if.data == `FIRMWARE_VERSION) && (curr_data_memmap == `FIRMWARE_VERSION) && (DUT.fresh_bits[curr_id] == 0) ,1'b1} : 0; 
			else test_check = (rd_if.valid_data)? {(rd_if.data == wd_if.data_to_send) && (curr_data_memmap == rd_if.data) && (DUT.fresh_bits[curr_id] == 0) ,1'b1} : 0;
		end else if (test_num == 3*`ADDR_NUM + 2) 
			test_check = (wasWritten == 1)? {(curr_data_memmap == rtl_wd_in[curr_id]), 1'b1} : 0;
		else if (test_num == 3*`ADDR_NUM + 3 || test_num == 3*`ADDR_NUM + 4) 
			test_check = (rd_if.valid_data)? {(rd_if.data == wd_if.data_to_send) && (curr_data_memmap == rd_if.data) && (DUT.fresh_bits[curr_id] == 0), 1'b1} : 0;
		else if (test_num == 3*`ADDR_NUM + 3 || test_num == 3*`ADDR_NUM + 5) 
			test_check = (rd_if.valid_data)? {(rd_if.data == rtl_wd_in[curr_id]) && (curr_data_memmap == rtl_wd_in[curr_id]) && (DUT.fresh_bits[curr_id] == 0), 1'b1} : 0;
		else if (test_num == 3*`ADDR_NUM + 6) 
			test_check = (rd_if.valid_data)? {(rd_if.data == wd_if.data_to_send) && (curr_data_rtlreadout == rtl_wd_in[curr_id]) && (curr_data_memmap == wd_if.data_to_send) && (DUT.fresh_bits[curr_id] == 0), 1'b1} : 0;
		else if (test_num == 3*`ADDR_NUM + 7) 
			test_check = (rd_if.valid_data)? {(rd_if.data == rtl_wd_in[curr_id]) && (curr_data_rtlreadout == wd_if.data_to_send) && (curr_data_memmap == rtl_wd_in[curr_id]) && (DUT.fresh_bits[curr_id] == 0), 1'b1} : 0;
		else if (test_num == 3*`ADDR_NUM + 9) 
			test_check = (rd_if.valid_data)? {(rd_if.data == 16'hBEEF) && (curr_data_rtlreadout == 16'hBEEF) && (curr_data_memmap == 16'hBEEF) && (DUT.fresh_bits[curr_id] == 0), 1'b1} : 0;
		else if (test_num == 3*`ADDR_NUM + 10) 
			test_check = (wasWritten == 2)? {(curr_data_rtlreadout == rtl_wd_in[curr_id]) && (curr_data_memmap == rtl_wd_in[curr_id]) && (DUT.fresh_bits[curr_id] == 0), 1'b1} : 0;
		else if (test_num == 3*`ADDR_NUM+11) 
			test_check = (testState == CHECK)? {correct_steps == 3, 1'b1} : 0;
		else if (test_num == 3*`ADDR_NUM+12) 
			test_check = (testState == CHECK)? {($signed(curr_data_rtlreadout) == -5), 1'b1} : 0;
		else if (test_num == 3*`ADDR_NUM + 13) 
			test_check = (testState == CHECK)? {correct_steps == 3, 1'b1} : 0;
		else if (test_num == 3*`ADDR_NUM+14) 
			test_check = (testState == TEST && timer == 14)? {correct_steps == 3, 1'b1} : 0;
		else test_check = 0;

		if (test_num < `ADDR_NUM) begin 										// ps Write to entire addr space
			curr_addr_idx = test_num; 
			{ps_read_rdy,ps_wrsp_rdy} = 3; 
			long_on = 1; 
		end 
		else if (test_num >= `ADDR_NUM && test_num < 2*`ADDR_NUM) begin    		// ps Write to entire addr space while oscillating ready signals (on more than off)
			curr_addr_idx = test_num-`ADDR_NUM;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 1;
		end 
		else if (test_num >= 2*`ADDR_NUM && test_num < 3*`ADDR_NUM) begin  		// ps Write to entire addr space while oscillating ready signals (off more than on)
			curr_addr_idx = test_num-2*`ADDR_NUM;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 0;
		end 
		else if (test_num == 3*`ADDR_NUM || test_num == 3*`ADDR_NUM+1) begin  	// Delay sending addr, then delay sending data
			curr_addr_idx = test_num%`ADDR_NUM;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 0; 
		end 
		else if (test_num == 3*`ADDR_NUM+2 || test_num == 3*`ADDR_NUM+3) begin	// ps Write while rtl is writing (ps writes last)
			curr_addr_idx = 6;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 0; 
		end 
		else if (test_num == 3*`ADDR_NUM+4 || test_num == 3*`ADDR_NUM+5) begin 	// ps Write while rtl is writing (rtl writes last)
			curr_addr_idx = 6;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 0; 
		end 
		else if (test_num == 3*`ADDR_NUM+6) begin 								// ps Write after rtl writes and reads (rtl should read what rtl wrote, ps should read what ps wrote)
			curr_addr_idx = 6;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 0; 
		end 
		else if (test_num == 3*`ADDR_NUM+7) begin 								// ps Write before rtl reads, then rtl writes (rtl should read what ps wrote, ps should read what rtl wrote)
			curr_addr_idx = 6;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 0; 
		end
		else if (test_num == 3*`ADDR_NUM+8) begin 								// rtl writes for a while, ps tries to write and eventually reads the value it wrote. Rtl also writes to other addresses simultaneously
			curr_addr_idx = 0;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 0; 
		end
		else if (test_num == 3*`ADDR_NUM+9) begin 								// rtl reads for a while, ps tries to write and eventually reads the value it wrote. Rtl also reads from other addresses simultaneously
			curr_addr_idx = 6;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 0; 
		end
		else if (test_num == 3*`ADDR_NUM+10) begin 								// rtl writes then reads the next cycle
			curr_addr_idx = 9;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 0; 
		end
		else if (test_num == 3*`ADDR_NUM+11) begin 								// rtl writes then reads on the same cycle (rtl should read what was there before)
			curr_addr_idx = 6;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 0; 
		end
		else if (test_num == 3*`ADDR_NUM+12) begin 								// ps writes, and rtl reads after freshbit is registered (standard type of handshaking that would go on in the system)						
			curr_addr_idx = 7;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 0; 
		end
		else if (test_num == 3*`ADDR_NUM+13) begin 								// rtl writes, and ps reads after freshbit is registered (standard type of handshaking that would go on in the system)
			curr_addr_idx = 8;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 0; 
		end
		else if (test_num == 3*`ADDR_NUM+14) begin 								// rtl acquires data sent by the ps to the RTLPOLL addresses. Also makes sure rtl cannot write to those addresses. 
			curr_addr_idx = 0;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 0; 
		end
		else {curr_addr_idx, ps_read_rdy, ps_wrsp_rdy, long_on} = 0; 

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
				
				{rtl_write_reqs, rtl_read_reqs, rtl_wd_in} <= 0; 
				{wa_if.send, wd_if.send, ra_if.send, wd_if.data_to_send, wa_if.data_to_send, ra_if.data_to_send} <= 0; 
				{got_wresp, read_data, correct_steps, idx} <= 0;
				for (int i = 0; i < `MEM_SIZE; i++) rtl_rdy[i] <= 0;
			end
		end else begin
			case(testState)
				IDLE: begin 
					if (start) testState <= TEST; 
					if (done) done <= 0; 
				end 
				TEST: begin
					// Write to entire addr space
					if (test_num < `ADDR_NUM) begin 
						wa_if.data_to_send <= addrs[curr_addr_idx]; 
						wd_if.data_to_send <= rand_val; 
						{wa_if.send, wd_if.send} <= 3; 
						testState <= WRESP_WAIT; 
					end 

					// ps Write to entire addr space while oscillating ready signals (on more than off)
					else if (test_num >= `ADDR_NUM && test_num < 2*`ADDR_NUM) begin 
						wa_if.data_to_send <= addrs[curr_addr_idx]; 
						wd_if.data_to_send <= rand_val; 
						{wa_if.send, wd_if.send} <= 3; 
						testState <= WRESP_WAIT; 
					end 

					// ps Write to entire addr space while oscillating ready signals (off more than on)
					else if (test_num >= 2*`ADDR_NUM && test_num < 3*`ADDR_NUM) begin 
						wa_if.data_to_send <= addrs[curr_addr_idx]; 
						wd_if.data_to_send <= rand_val; 
						{wa_if.send, wd_if.send} <= 3; 
						testState <= WRESP_WAIT; 
					end 

					// Delay sending addr 
					else if (test_num == 3*`ADDR_NUM) begin 
						if (timer == 0) begin
							wa_if.data_to_send <= addrs[curr_addr_idx]; 
							wa_if.send <= 1; 
						end else wa_if.send <= 0; 

						if (timer == TIMER_DELAY) begin
							wd_if.data_to_send <= rand_val; 
							wd_if.send <= 1; 
							testState <= WRESP_WAIT; 
							timer <= 0; 
						end else timer <= timer + 1;
					end

					// Delay sending data 
					else if (test_num == 3*`ADDR_NUM+1) begin 
						if (timer == 0) begin
							wd_if.data_to_send <= rand_val; 
							wd_if.send <= 1; 
						end else wd_if.send <= 0; 

						if (timer == TIMER_DELAY) begin
							wa_if.data_to_send <= addrs[curr_addr_idx]; 
							wa_if.send <= 1; 
							testState <= WRESP_WAIT; 
							timer <= 0; 
						end else timer <= timer + 1;
					end

					// ps Write while rtl is writing (ps writes last)
					else if (test_num == 3*`ADDR_NUM+2) begin 
						rtl_write_reqs[curr_id] <= 1; 
						rtl_wd_in[curr_id] <= rand_val; 
						wd_if.data_to_send <= rand_val + 1; 
						wa_if.data_to_send <= addrs[curr_addr_idx];
						{wa_if.send, wd_if.send} <= 3;
						testState <= CHECK; 
					end

					// ps Write while rtl is writing (ps writes last) part 1 = both write, check ps reads its own value
					else if (test_num == 3*`ADDR_NUM+4) begin 
						rtl_write_reqs[curr_id] <= 1; 
						rtl_wd_in[curr_id] <= rand_val; 
						wd_if.data_to_send <= rand_val + 1; 
						wa_if.data_to_send <= addrs[curr_addr_idx];
						{wa_if.send, wd_if.send} <= 3;
						testState <= WRESP_WAIT;
					end
					// ps Write while rtl is writing (rtl writes last) part 2 = rtl writes again, check ps reads new value
					else if (test_num == 3*`ADDR_NUM+5) begin 
						rtl_write_reqs[curr_id] <= 1; 
						ra_if.send <= 1; 
						testState <= CHECK; 
					end
					// ps Write after rtl writes and reads (rtl should read what rtl wrote, ps should read what ps wrote)
					else if (test_num == 3*`ADDR_NUM+6) begin 
						if (timer == 0) begin
							rtl_write_reqs[curr_id] <= 1; 
							rtl_wd_in[curr_id] <= rand_val; 
							wa_if.data_to_send <= addrs[curr_addr_idx];
							wd_if.data_to_send <= rand_val+1;
							timer <= 1; 
						end else begin 
							rtl_read_reqs[curr_id] <= 1; 
							{wa_if.send, wd_if.send} <= 3;
							testState <= WRESP_WAIT; 
							timer <= 0; 
						end 
					end
					// ps Write before rtl reads, then rtl writes (rtl should read what ps wrote, ps should read what rtl wrote)
					else if (test_num == 3*`ADDR_NUM+7) begin 
						if (timer == 0) begin 
							wa_if.data_to_send <= addrs[curr_addr_idx];
							wd_if.data_to_send <= rand_val;
							{wa_if.send, wd_if.send} <= 3;
							timer <= 1;
						end else begin
							if (wr_if.valid_data) begin
								rtl_write_reqs[curr_id] <= 1; 
								rtl_wd_in[curr_id] <= rand_val;
								rtl_read_reqs[curr_id] <= 1; 
								ra_if.data_to_send <= addrs[curr_addr_idx]; 
								ra_if.send <= 1; 
								timer <= 0; 
								testState <= CHECK; 
							end
						end
					end
					// rtl writes for a while, ps tries to write and eventually reads the value it wrote. Rtl also writes to other addresses simultaneously
					else if (test_num == 3*`ADDR_NUM+8) begin 
						for (int i = 0; i < `ADDR_NUM; i++) begin
							rtl_wd_in[ids[i]] <= rand_val+i; 
							if (timer == 0) rtl_write_reqs[ids[i]] <= 1; 
						end
						if (timer == 0) begin
							wa_if.data_to_send <= addrs[curr_addr_idx];
							wd_if.data_to_send <= -1;
							{wa_if.send, wd_if.send} <= 3;
						end  
						if (timer == TIMER_DELAY - 20) rtl_write_reqs[curr_id] <= 0; 

						if (timer == TIMER_DELAY) begin
							timer <= 0;
							for (int i = 0; i < `ADDR_NUM; i++) rtl_write_reqs[ids[i]] <= 0; 
							testState <= WRESP_WAIT; 
						end else timer <= timer + 1; 
					end
					// rtl reads for a while, ps tries to write and eventually reads the value it wrote. Rtl also reads from other addresses simultaneously
					else if (test_num == 3*`ADDR_NUM+9) begin 
						for (int i = 0; i < `ADDR_NUM; i++) begin
							if (timer == 0) rtl_read_reqs[ids[i]] <= 1; 
						end
						if (timer == 0) begin
							ra_if.data_to_send <= addrs[curr_addr_idx];
							rtl_write_reqs[curr_id] <= 1;
							rtl_wd_in[curr_id] <= 16'hBEEF; 
							ra_if.send <= 1; 
						end  
						if (timer == TIMER_DELAY - 20) rtl_read_reqs[curr_id] <= 0;  

						if (timer == TIMER_DELAY) begin
							timer <= 0;
							for (int i = 0; i < `ADDR_NUM; i++) rtl_read_reqs[ids[i]] <= 0; 
							testState <= CHECK; 
						end else timer <= timer + 1;
					end
					// rtl writes then reads the next cycle
					else if (test_num == 3*`ADDR_NUM+10) begin 
						if (timer == 0) begin 
							rtl_wd_in[curr_id] <= rand_val; 
							rtl_write_reqs[curr_id] <= 1; 
							timer <= 1; 
						end else begin
							rtl_read_reqs[curr_id] <= 1; 
							timer <= 0; 
							testState <= CHECK; 
						end
					end
					// rtl writes then reads on the same cycle (rtl should read what was there before)
					else if (test_num == 3*`ADDR_NUM+11) begin 
						if (timer == 4) timer <= 0;
						else timer <= timer + 1; 

						if (timer == 0) begin 
							rtl_wd_in[curr_id] <= rand_val; 
							rtl_wd_in[`ADDR_NUM+1] <= rand_val; 
							rtl_write_reqs[curr_id] <= 1; 
							correct_steps <= 0; 
						end  
						if (timer == 1) begin 
							rtl_wd_in[curr_id] <= rand_val; 
							rtl_read_reqs[curr_id] <= 1; 
						end 
						if (timer == 3) begin 
							correct_steps <= (curr_data_rtlreadout == rtl_wd_in[`ADDR_NUM+1]) + (curr_data_memmap == rtl_wd_in[curr_id]) + (DUT.fresh_bits[curr_id] == 1); 
							rtl_write_reqs[curr_id] <= 0; 
						end 
						if (timer == 4) begin
							rtl_read_reqs[curr_id] <= 0;
							testState <= CHECK; 
						end
					end
					// ps writes, and rtl reads after freshbit is registered (standard type of handshaking that would go on in the system if address is not of type RTL_POLL)						
					else if (test_num == 3*`ADDR_NUM+12) begin 
						if (timer == 10) begin
							timer <= 0; 
							testState <= CHECK; 
						end else timer <= timer + 1; 

						if (timer == 0) begin 
							wa_if.data_to_send <= addrs[curr_addr_idx];
							wd_if.data_to_send <= -5;
							{wa_if.send, wd_if.send} <= 3;
							rtl_read_reqs[curr_id] <= 1; 
						end 
						if (timer > 2) begin 
							if (fresh_bits[curr_id]) rtl_read_reqs[curr_id] <= 1; 
						end 
					end
					// rtl writes, and ps reads data address after valid address is registered (standard type of handshaking that would go on in the system)
					else if (test_num == 3*`ADDR_NUM+13) begin 
						if (timer <= 20) begin
							if (timer == 0) begin 
								correct_steps <= 0; 
								read_data <= -1; 
								timer <= timer + 1; 
							end else begin
								if (read_data == 1) begin // rtl has valid data to read
									wa_if.data_to_send <= `DAC_ILA_RESP_VALID_ADDR; 
									wd_if.data_to_send <= 0; 
									{wd_if.send, wa_if.send} <= 3; 
									correct_steps <= correct_steps + 1; 
									timer <= 21; 
									read_data <= -1; 
									testState <= WRESP_WAIT;
								end else begin
									ra_if.data_to_send <= `DAC_ILA_RESP_VALID_ADDR;
									ra_if.send <= 1; 
									timer <= timer + 1; 
									testState <= READ_DATA;
								end 
							end 
						end else 
						if (timer > 20 && timer <= 30) begin
							if ($signed(read_data) != -1) begin
								correct_steps <= correct_steps + (fresh_bits[`DAC_ILA_RESP_ID] == 0) + ($signed(read_data) == -10);
								timer <= 31; 
							end else begin 
								ra_if.data_to_send <= `DAC_ILA_RESP_ADDR;
								ra_if.send <= 1; 
								timer <= timer + 1; 
								testState <= READ_DATA; 
							end 
						end else 
						if (timer > 30) begin
							if (rtl_read_reqs[`DAC_ILA_RESP_ID]) begin
								timer <= 0; 
								testState <= CHECK; 
								rtl_read_reqs[`DAC_ILA_RESP_ID] <= 0;
								rtl_read_reqs[`DAC_ILA_RESP_VALID_ID] <= 0;
							end else begin
								rtl_read_reqs[`DAC_ILA_RESP_ID] <= 1;
								rtl_read_reqs[`DAC_ILA_RESP_VALID_ID] <= 1;
							end 
						end

						if (timer == 10) begin 
							rtl_wd_in[`DAC_ILA_RESP_ID] <= -10; 
							rtl_write_reqs[`DAC_ILA_RESP_ID] <= 1; 
							rtl_wd_in[`DAC_ILA_RESP_VALID_ID] <= 1; 
							rtl_write_reqs[`DAC_ILA_RESP_VALID_ID] <= 1; 
						end 
					end
					// rtl acquires data sent by the ps to the RTLPOLL addresses. Also makes sure rtl cannot write to those addresses. 
					else if (test_num == 3*`ADDR_NUM+14) begin 
						if (timer == 0) {idx, correct_steps, timer} <= 1; 
						if (timer == 1) begin
							if (idx == `ADDR_NUM-1) begin
								testState <= CHECK;
								timer <= 0;
								idx <= 0;
							end 
							else begin 
								if (`is_RTLPOLL(ids[idx])) begin 
									wa_if.data_to_send <= addrs[idx];
									wd_if.data_to_send <= (idx == 8 || idx == 10)? idx : 69+idx;
									{wa_if.send, wd_if.send} <= 3; 
									timer <= 2;
									testState <= WRESP_WAIT; 
								end else idx <= idx + 1; 
							end 
						end
						if (timer == 7) rtl_rdy[ids[idx]] <= 1;
						if (timer == 8) rtl_rdy[ids[idx]] <= 0;
						if (timer == 9) correct_steps <= (idx == 8 || idx == 10)? correct_steps + (fresh_bits[ids[idx]] == 0) + (rtl_rd_out[ids[idx]] == idx) : correct_steps + (fresh_bits[ids[idx]] == 0) + (rtl_rd_out[ids[idx]] == 69+idx);	
						if (timer == 10) begin
							rtl_wd_in[ids[idx]] <= 0; 
							rtl_write_reqs[ids[idx]] <= 1; 
						end	
						if (timer == 11) begin
							rtl_write_reqs[ids[idx]] <= 0; 
							rtl_read_reqs[ids[idx]] <= 1; 
						end 
						if (timer == 12) rtl_read_reqs[ids[idx]] <= 0; 
						if (timer == 13) correct_steps <= (idx == 8 || idx == 10)? correct_steps + (rtl_rd_out[ids[idx]] == idx) : correct_steps + (rtl_rd_out[ids[idx]] == 69+idx);
						
						if (timer > 1 && timer < 14) timer <= timer + 1; 
						else if (timer == 14) begin
							idx <= idx + 1; 
							correct_steps <= 0; 
							timer <= 1;
						end 
					end
				end 
				WRESP_WAIT: begin
					if (wr_if.valid_data || got_wresp[0]) begin
						if (got_wresp[0]) got_wresp <= 0; 
						if (got_wresp[1] || wr_if.data != `OKAY) begin
							kill_tb <= 1; 
							testState <= DONE; 
						end else begin
							if (test_num < 3*`ADDR_NUM+13) begin
								ra_if.data_to_send <= addrs[curr_addr_idx]; 
								ra_if.send <= 1; 
								testState <= CHECK; 
							end else testState <= TEST; 
						end
					end
				end 
				READ_DATA: begin
					if (rtl_write_reqs[`DAC_ILA_RESP_ID]) {rtl_write_reqs[`DAC_ILA_RESP_ID], rtl_write_reqs[`DAC_ILA_RESP_VALID_ID]} <= 0; 
					if (rd_if.valid_data) begin
						read_data <= rd_if.data; 
						testState <= TEST; 
					end
				end 
				CHECK: begin
					if (test_num == 3*`ADDR_NUM + 2 && fresh_bits[curr_id]) begin 
						test_num <= test_num + 1; 
						testState <= WRESP_WAIT; 
					end 
					else if (rd_if.valid_data || test_num >= 3*`ADDR_NUM + 9) begin
						test_num <= test_num + 1;
						testState <= (test_num == TOTAL_TESTS-1)? DONE : TEST; 
					end 
				end 

				DONE: begin 
					done <= {testsFailed == 0 && ~kill_tb,1'b1};
					testState <= IDLE; 
					test_num <= 0; 
				end 
			endcase

			if (testState != WRESP_WAIT && wr_if.valid_data) got_wresp <= {wr_if.data != `OKAY,1'b1}; 
			if (wd_if.send) wd_if.send <= 0;
			if (wa_if.send) wa_if.send <= 0;
			if (ra_if.send) ra_if.send <= 0;
			if (rtl_write_reqs[curr_id] && test_num != 3*`ADDR_NUM+8 && test_num != 3*`ADDR_NUM+11) rtl_write_reqs[curr_id] <= 0; 
			if (rtl_read_reqs[curr_id] && test_num != 3*`ADDR_NUM+9 && test_num != 3*`ADDR_NUM+11) rtl_read_reqs[curr_id] <= 0; 

			if (test_num == 3*`ADDR_NUM+14) begin
				if (test_check[0]) begin
					if (test_check[1]) begin 
						testsPassed <= testsPassed + 1;
						if (VERBOSE) $write("%c[1;32m",27); 
						if (VERBOSE) $write("t%0d_%0d+ ",test_num,idx);
						if (VERBOSE) $write("%c[0m",27); 
					end 
					else begin 
						testsFailed <= testsFailed + 1; 
						if (VERBOSE) $write("%c[1;31m",27); 
						if (VERBOSE) $write("t%0d_%0d+ ",test_num,idx);
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
	logic go; 
	enum logic {WATCH, PANIC} panicState;
	logic[$clog2(TIMEOUT):0] timeout_cntr; 
	edetect #(.DATA_WIDTH(8))
	testNum_edetect (.clk(clk), .rst(rst),
	 				 .val(test_num),
	 				 .comb_posedge_out(testNum_edge)); 

	always_ff @(posedge clk) begin 
		if (rst || testState == IDLE) begin 
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
        if (VERBOSE) $display("\n############ Starting Axi-Slave Tests ############");
        #100;
        while (testState != DONE && timeout_cntr < TIMEOUT) #10;
        if (timeout_cntr < TIMEOUT) begin
	        if (testsFailed != 0) begin 
	        	if (VERBOSE) $write("%c[1;31m",27); 
	        	if (VERBOSE) $display("\nAxi-Slave Tests Failed :((\n");
	        	if (VERBOSE) $write("%c[0m",27);
	        end else begin 
	        	if (VERBOSE) $write("%c[1;32m",27); 
	        	if (VERBOSE) $display("\nAxi-Slave Tests Passed :))\n");
	        	if (VERBOSE) $write("%c[0m",27); 
	        end
	        #100;
	    end else begin
	    	$write("%c[1;31m",27); 
	        $display("\nAxi-Slave Tests Timed out on test %d!\n", test_num);
	        $write("%c[0m",27);
	        #100; 
	    end
    end 

endmodule 

`default_nettype wire
/*
New Tests to Make:
1. Write past MEM_SIZE, make sure it doesn't crash the system and writes aren't registed. Read past MEM_SIZE, make sure you get the data in the last valid address. (perform at top)
2. rtl and ps writes to readonly unmapped address: contents remain the same
3. ps performs memory test (perform at top)
4. rtl and ps writes to readonly MAX_BURST_SIZE and MEM_SIZE addresses. Reading should return the correct values. (perform at top)
*/