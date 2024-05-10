`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module slave_tb #(parameter VERBOSE = 1)(input wire start, output logic[1:0] done);
	localparam STARTING_TEST = 0; 
	localparam TOTAL_TESTS = 14; 
	localparam OSC_DELAY = 5;
	localparam TIMEOUT = 10_000; 

	logic clk, rst;
	logic panic = 0; 
	logic[`WD_DATA_WIDTH-1:0] rand_val, read_data;
	logic ps_read_rdy, ps_wrsp_rdy; 
	logic[`MEM_SIZE-1:0] rtl_write_reqs, rtl_read_reqs, fresh_bits, rtl_rdy; 
	logic[`MEM_SIZE-1:0][`WD_DATA_WIDTH-1:0] rtl_wd_in, rtl_rd_out;
	logic[$clog2(`ADDR_NUM)-1:0] curr_addr_idx;
	logic[15:0] timer, curr_id_clkd, correct_steps;
	logic test_start; 
	logic[1:0] correct_edge; 
	logic wrong_step;
	logic osc_sig, long_on; 
	logic[1:0] got_wresp;  //[1] == error bit (wr_if.data wasn't okay when recieved), [0] == sys saw a wr_if.data 

	enum logic[2:0] {IDLE, TEST, WRESP_WAIT, READ_DATA, POLL_CHECK, CHECK, DONE} testState; 
	logic[1:0] test_check; // test_check[0] = check, test_check[1] == 1 => test passed else test failed 
	logic[7:0] test_num; 
	logic[7:0] testsPassed, testsFailed; 
	logic kill_tb; 

	logic[`WD_DATA_WIDTH-1:0] curr_data_memmap, curr_data_rtlreadout, curr_rtl_wd, curr_rtl_rd, rtlreadoutTest;
	logic curr_freshbit;
	logic[`A_DATA_WIDTH-1:0] curr_id, curr_addr, curr_addr_clkd; 
	logic clr_rd_out; 

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
	    .clr_rd_out(clr_rd_out),
	    .rtl_rdy(rtl_rdy),
	    .rtl_wd_in(rtl_wd_in), 				//in
	    .rtl_rd_out(rtl_rd_out),			//out 
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
	edetect #(.DATA_WIDTH(16))
    correct_ed(.clk(clk), .rst(rst),
               .val(correct_steps),
               .comb_posedge_out(correct_edge));

	assign curr_id = ids[curr_addr_idx];
	assign curr_addr = addrs[curr_addr_idx]; 
	assign curr_data_memmap = DUT.mem_map[curr_id]; 
	assign curr_data_rtlreadout = rtl_rd_out[curr_id];
	assign curr_rtl_wd = rtl_wd_in[curr_id]; 
	assign curr_rtl_rd = rtl_rd_out[curr_id]; 
	assign curr_freshbit = fresh_bits[curr_id];

	always_comb begin
		test_check = (test_start == 0)? {correct_edge == 1, correct_edge != 0} : 0;
		if (test_num < 6) begin 
			curr_addr_idx = 8;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 1;
		end else begin
			curr_addr_idx = 9;
			{ps_read_rdy,ps_wrsp_rdy} = {osc_sig, osc_sig}; 
			long_on = 0;
		end 
	end

	always_ff @(posedge clk) begin
		if (rst || panic) begin
			if (panic) begin
				testState <= DONE;
				kill_tb <= 1; 
				panic <= 0;
			end else begin
				testState <= IDLE;
				test_num <= STARTING_TEST; 
				{testsPassed,testsFailed, kill_tb} <= 0; 
				{done,timer,curr_id_clkd,test_start} <= 0;
				
				{rtl_write_reqs, rtl_read_reqs, rtl_wd_in} <= 0; 
				{wa_if.send, wd_if.send, ra_if.send, wd_if.data_to_send, wa_if.data_to_send, ra_if.data_to_send} <= 0; 
				{got_wresp, read_data, correct_steps, curr_addr_clkd, clr_rd_out, wrong_step} <= 0;
				for (int i = 0; i < `MEM_SIZE; i++) rtl_rdy[i] <= 1;
			end
		end else begin
			case(testState)
				IDLE: begin 
					if (start) testState <= TEST; 
					if (done) done <= 0; 
				end 
				TEST: begin
					// Delay sending addr 
					if (test_num == 0) begin 
						if (timer == 22) begin
							correct_steps <= (read_data == wd_if.data_to_send)? correct_steps + 1 : correct_steps - 1; 
							timer <= 0;
							testState <= CHECK; 
						end else timer <= timer + 1;

						if (timer == 0) begin
							wa_if.data_to_send <= curr_addr; 
							wa_if.send <= 1; 
							{correct_steps,test_start} <= 1;
						end 
						if (timer == 20) begin
							wd_if.data_to_send <= rand_val; 
							wd_if.send <= 1; 
							testState <= WRESP_WAIT; 
						end 
						if (timer == 21) begin
							ra_if.data_to_send <= curr_addr; 
							ra_if.send <= 1;
							testState <= READ_DATA; 
						end
					end
					// Delay sending data 
					if (test_num == 1) begin 
						if (timer == 22) begin
							correct_steps <= (read_data == wd_if.data_to_send)? correct_steps + 1 : correct_steps - 1; 
							timer <= 0;
							testState <= CHECK; 
						end else timer <= timer + 1;

						if (timer == 0) begin
							wd_if.data_to_send <= rand_val; 
							wd_if.send <= 1; 
							{correct_steps,test_start} <= 1;
						end 
						if (timer == 20) begin
							wa_if.data_to_send <= curr_addr; 
							wa_if.send <= 1; 
							testState <= WRESP_WAIT; 
						end 
						if (timer == 21) begin
							ra_if.data_to_send <= curr_addr; 
							ra_if.send <= 1;
							testState <= READ_DATA; 
						end
					end
					// ps Write while rtl is writing (ps writes last so its read data is its own). Then rtl writes again. Check ps reads new value
					if (test_num == 2) begin 
						if (timer == 11) begin
							correct_steps <= (read_data == curr_rtl_wd)? correct_steps + 1 : correct_steps - 1; 
							testState <= CHECK;
							timer <= 0; 
							rtl_wd_in <= 0;
						end else timer <= timer + 1;

						if (timer == 0) begin
							wd_if.data_to_send <= rand_val; 
							wa_if.data_to_send <= curr_addr;
							{wa_if.send, wd_if.send} <= 3;
							{correct_steps,test_start} <= 1;
						end
						if (timer == 3) begin //It'll take 5 cycles for the slave to be prepared to write the ps request
							rtl_write_reqs[curr_id] <= 1; 
							rtl_wd_in[curr_id] <= rand_val; 
						end 
						if (timer == 5) correct_steps <= (curr_data_memmap == curr_rtl_wd)? correct_steps + 1 : correct_steps - 1; 
						if (timer == 6) correct_steps <= (curr_data_memmap == wd_if.data_to_send)? correct_steps + 1 : correct_steps - 1; 
						if (timer == 7) testState <= WRESP_WAIT; 
						if (timer == 8) begin
							ra_if.data_to_send <= addrs[curr_addr_idx];
							ra_if.send <= 1; 
							testState <= READ_DATA; 
						end
						if (timer == 9) begin
							correct_steps <= (read_data == wd_if.data_to_send)? correct_steps + 1 : correct_steps - 1; 
							rtl_write_reqs[curr_id] <= 1; 
						end 
						if (timer == 10) begin 
							ra_if.send <= 1;
							testState <= READ_DATA; 
						end 
					end
					// ps Write after rtl writes and reads (rtl should read what rtl wrote, ps should read what ps wrote)
					if (test_num == 3) begin 
						if (timer == 9) begin
							testState <= CHECK;
							timer <= 0;
						end else timer <= timer + 1;

						if (timer == 0) begin
							wa_if.data_to_send <= curr_addr;
							wd_if.data_to_send <= rand_val;
							{wa_if.send, wd_if.send} <= 3;
							{correct_steps,test_start} <= 1;
						end
						if (timer == 3) begin
							rtl_write_reqs[curr_id] <= 1; 
							rtl_wd_in[curr_id] <= rand_val; 
						end
						if (timer == 4) rtl_read_reqs[curr_id] <= 1;
						if (timer == 6) correct_steps <= (curr_rtl_rd == curr_rtl_wd)? correct_steps + 1 : correct_steps - 1; 
						if (timer == 7) begin
							correct_steps <= (curr_data_memmap == wd_if.data_to_send)? correct_steps + 1 : correct_steps - 1; 
							ra_if.data_to_send <= curr_addr;
							ra_if.send <= 1;
							testState <= READ_DATA; 
						end 
						if (timer == 8) begin
							correct_steps <= (read_data == wd_if.data_to_send)? correct_steps + 1 : correct_steps - 1;
							testState <= WRESP_WAIT; 
						end
					end
					// ps Write before rtl reads, then rtl writes (rtl should read what ps wrote, ps should read what rtl wrote)
					if (test_num == 4) begin 
						if (timer == 9) begin
							correct_steps <= (read_data == curr_rtl_wd)? correct_steps + 1 : correct_steps - 1;
							testState <= CHECK;
							timer <= 0;
						end else timer <= timer + 1;

						if (timer == 0) begin
							wa_if.data_to_send <= curr_addr;
							wd_if.data_to_send <= rand_val;
							{wa_if.send, wd_if.send} <= 3;
							{correct_steps,test_start} <= 1;
						end
						if (timer == 5) begin
							rtl_read_reqs[curr_id] <= 1;
							rtl_write_reqs[curr_id] <= 1; 
							rtl_wd_in[curr_id] <= rand_val; 
						end
						if (timer == 7) begin
							correct_steps <= (curr_rtl_rd == wd_if.data_to_send)? correct_steps + 1 : correct_steps - 1;
							testState <= WRESP_WAIT; 
						end
						if (timer == 8) begin
							ra_if.data_to_send <= curr_addr;
							ra_if.send <= 1;
							testState <= READ_DATA;
						end
					end
					// rtl writes for a while, ps tries to write and eventually reads the value it wrote. Rtl also writes to other addresses simultaneously
					if (test_num == 5) begin 
						if (timer == 48) begin
							correct_steps <= (read_data == wd_if.data_to_send)? correct_steps + 1 : correct_steps - 1;
							testState <= CHECK;
							timer <= 0;
						end else timer <= timer + 1;

						if (timer == 0) begin
							wa_if.data_to_send <= curr_addr;
							wd_if.data_to_send <= rand_val;
							{wa_if.send, wd_if.send} <= 3;
							for (int i = 0; i < `MEM_SIZE; i++) begin 
								rtl_write_reqs[i] <= 1;
								rtl_wd_in[i] <= rand_val + i; 
							end 
							{correct_steps,test_start} <= 1;
						end

						if (timer == 20) correct_steps <= (curr_data_memmap == wd_if.data_to_send+curr_id)? correct_steps + 1 : correct_steps - 1;
						if (timer == 35) correct_steps <= (curr_data_memmap == wd_if.data_to_send+curr_id)? correct_steps + 1 : correct_steps - 1;
						if (timer == 40) begin
							rtl_write_reqs <= 0;
							rtl_read_reqs[curr_id] <= 1; 
						end
						if (timer == 42) correct_steps <= (curr_rtl_rd == wd_if.data_to_send+curr_id)? correct_steps + 1 : correct_steps - 1;
						if (timer == 43) correct_steps <= (curr_data_memmap == wd_if.data_to_send)? correct_steps + 1 : correct_steps - 1;
						if (timer == 44) testState <= WRESP_WAIT;
						if (timer == 45) begin
							ra_if.data_to_send <= curr_addr;
							ra_if.send <= 1; 
							rtl_read_reqs <= (`MEM_SIZE)'(-1);
							testState <= READ_DATA; 
						end
						if (timer == 47) rtl_read_reqs <= 0;
					end 
					// rtl reads for a while, ps tries to write and eventually reads the value it wrote. Rtl also reads from other addresses simultaneously
					if (test_num == 6) begin 
						if (timer == 42) begin
							correct_steps <= (read_data == wd_if.data_to_send)? correct_steps + 1 : correct_steps - 1;
							testState <= CHECK;
							timer <= 0;
						end else timer <= timer + 1;

						if (timer == 0) begin
							wa_if.data_to_send <= curr_addr;
							wd_if.data_to_send <= rand_val;
							{wa_if.send, wd_if.send} <= 3;
							for (int i = 0; i < `ADDR_NUM; i++) rtl_read_reqs[ids[i]] <= 1;
							{correct_steps,test_start} <= 1;
						end

						if (timer == 20) begin
							for (int i = 0; i < `ADDR_NUM; i++) begin 
								if (ids[i] != curr_id) rtl_read_reqs[ids[i]] <= 0;
							end 
							correct_steps <= (curr_data_memmap == curr_rtl_rd)? correct_steps + 1 : correct_steps - 1;
						end
						if (timer == 40) begin
							correct_steps <= (curr_data_memmap == curr_rtl_rd && got_wresp == 0)? correct_steps + 1 : correct_steps - 1;
							rtl_read_reqs <= 0;
							testState <= WRESP_WAIT;
						end
						if (timer == 41) begin 
							correct_steps <= (curr_data_memmap == wd_if.data_to_send)? correct_steps + 1 : correct_steps - 1;
							ra_if.data_to_send <= curr_addr;
							ra_if.send <= 1;
							testState <= READ_DATA;
						end 
					end 
					// rtl writes then reads the next cycle
					if (test_num == 7) begin 
						if (timer == 3) begin
							correct_steps <= (curr_rtl_rd == curr_rtl_wd)? correct_steps + 1 : correct_steps - 1;
							testState <= CHECK;
							timer <= 0;
						end else timer <= timer + 1;

						if (timer == 0) begin
							rtl_write_reqs[curr_id] <= 1; 
							rtl_wd_in[curr_id] <= rand_val; 
							{correct_steps,test_start} <= 1;
						end
						if (timer == 1) rtl_read_reqs[curr_id] <= 1;
					end 
					// rtl writes then reads on the same cycle (rtl should read what was there before), then reads again (should read what was written)
					if (test_num == 8) begin 
						if (timer == 4) begin
							correct_steps <= (curr_rtl_rd == curr_rtl_wd)? correct_steps + 1 : correct_steps - 1;
							testState <= CHECK;
							timer <= 0;
						end else timer <= timer + 1;

						if (timer == 0) begin
							rtl_write_reqs[curr_id] <= 1; 
							rtl_read_reqs[curr_id] <= 1;
							read_data <= curr_data_memmap; 
							rtl_wd_in[curr_id] <= rand_val; 
							{correct_steps,test_start} <= 1;
						end
						if (timer == 2) begin
							correct_steps <= (curr_rtl_rd == read_data)? correct_steps + 1 : correct_steps - 1;
							rtl_read_reqs[curr_id] <= 1;
						end 
						if (timer == 3) correct_steps <= (curr_data_memmap == curr_rtl_wd)? correct_steps + 1 : correct_steps - 1;
					end 
					// ps writes, and rtl reads after freshbit is registered (The kind of handshaking that would go on in the system if address is not of type RTL_POLL)						
					if (test_num == 9) begin 
						if (timer == 0) begin
							wa_if.data_to_send <= curr_addr;
							wd_if.data_to_send <= rand_val;
							{correct_steps,test_start} <= 1;
							{wa_if.send, wd_if.send} <= 3;
							timer <= 1;
						end
						if (timer == 1) begin
							if (curr_freshbit) begin
								rtl_read_reqs[curr_id] <= 1;
								testState <= WRESP_WAIT; 
								timer <= 2;
							end
						end 
						if (timer == 2) begin
							correct_steps <= (curr_rtl_rd == wd_if.data_to_send && curr_freshbit == 0)? correct_steps + 1 : correct_steps - 1;
							timer <= 0;
							testState <= CHECK; 
						end
					end 
					// rtl acquires data sent by the ps to the RTLPOLL addresses. Also makes sure rtl cannot write to those addresses. 
					if (test_num == 10) begin 
						if (timer == 0) begin
							{correct_steps,rtl_rdy,test_start} <= 1;
							clr_rd_out <= 1;
							curr_addr_clkd <= `PS_BASE_ADDR; 
							timer <= 1; 
						end
						if (timer == 1) begin
							if (`is_RTLPOLL(`ADDR2ID(curr_addr_clkd))) begin 
								wa_if.data_to_send <= curr_addr_clkd; 
								wd_if.data_to_send <= ((curr_addr_clkd-`PS_BASE_ADDR)>>2)+25;
								{wa_if.send, wd_if.send} <= 3;
								testState <= WRESP_WAIT;
							end  
							if (curr_addr_clkd == `ABS_ADDR_CEILING) begin
								curr_addr_clkd <= 0;
								curr_id_clkd <= `RST_ID; 
								timer <= 2;
							end else curr_addr_clkd <= curr_addr_clkd + 4;
						end
						if (timer == 2) begin
							if (`is_RTLPOLL(curr_id_clkd)) correct_steps <= (fresh_bits[curr_id_clkd] == 1 && rtl_rd_out[curr_id_clkd] == 0)? correct_steps + 1 : correct_steps - 1;
							if (curr_id_clkd == `MEM_SIZE-1) begin
								curr_id_clkd <= `RST_ID;
								timer <= 3; 
							end else curr_id_clkd <= curr_id_clkd + 1; 
						end
						if (timer == 3) begin
							rtl_rdy[curr_id_clkd] <= 1;
							if (`is_RTLPOLL(curr_id_clkd)) timer <= 4; 
							else timer <= 6;
						end
						if (timer == 4) begin
							correct_steps <= (fresh_bits[curr_id_clkd] == 1 && rtl_rd_out[curr_id_clkd] == 0)? correct_steps + 1 : correct_steps - 1;
							timer <= 5;
						end 
						if (timer == 5) begin
							if (curr_id_clkd == `SCALE_DAC_OUT_ID) begin
								if ((curr_id_clkd+25) > `MAX_SCALE_FACTOR) correct_steps <= (fresh_bits[curr_id_clkd] == 0 && rtl_rd_out[curr_id_clkd] == `MAX_SCALE_FACTOR)? correct_steps + 1 : correct_steps - 1;
								else correct_steps <= (fresh_bits[curr_id_clkd] == 0 && rtl_rd_out[curr_id_clkd] == curr_id_clkd+25)? correct_steps + 1 : correct_steps - 1;
							end 
							else if (curr_id_clkd == `DAC_BURST_SIZE_ID) begin
								if ((curr_id_clkd+25) > `MAX_DAC_BURST_SIZE) correct_steps <= (fresh_bits[curr_id_clkd] == 0 && rtl_rd_out[curr_id_clkd] == `MAX_DAC_BURST_SIZE)? correct_steps + 1 : correct_steps - 1;
								else correct_steps <= (fresh_bits[curr_id_clkd] == 0 && rtl_rd_out[curr_id_clkd] == curr_id_clkd+25)? correct_steps + 1 : correct_steps - 1;
							end 
							else correct_steps <= (fresh_bits[curr_id_clkd] == 0 && rtl_rd_out[curr_id_clkd] == curr_id_clkd+25)? correct_steps + 1 : correct_steps - 1;
							timer <= 6;
						end
						if (timer == 6) begin
							if (curr_id_clkd == `MEM_SIZE-1) begin
								curr_id_clkd <= 0;
								timer <= 7;
							end else begin 
								curr_id_clkd <= curr_id_clkd + 1;
								timer <= 3;
							end 
						end
						if (timer == 7) begin
							timer <= 0;
							testState <= CHECK; 
						end 
					end 
					// Write to entire addr space
					if (test_num == 11) begin
						if (timer == 0) begin
							{correct_steps,test_start} <= 1;
							curr_addr_clkd <= `PS_BASE_ADDR; 
							timer <= 1;
						end
						if (timer == 1) begin 
							wa_if.data_to_send <= curr_addr_clkd; 
							wd_if.data_to_send <= rand_val; 
							{wa_if.send, wd_if.send} <= 3; 
							timer <= 2;
							testState <= WRESP_WAIT; 
						end 
						if (timer == 2) begin
							ra_if.data_to_send <= curr_addr_clkd; 
							ra_if.send <= 1; 
							timer <= 3; 
							testState <= READ_DATA; 
						end
						if (timer == 3) begin
							case(curr_addr_clkd)
								`DAC_BURST_SIZE_ADDR: begin
									if (wd_if.data_to_send > `MAX_DAC_BURST_SIZE) correct_steps <= (read_data == `MAX_DAC_BURST_SIZE)? correct_steps + 1 : correct_steps - 1;  
									else correct_steps <= (read_data == wd_if.data_to_send)? correct_steps + 1 : correct_steps - 1;  
								end 
								`SCALE_DAC_OUT_ADDR: begin
									if (wd_if.data_to_send > `MAX_SCALE_FACTOR) correct_steps <= (read_data == `MAX_SCALE_FACTOR)? correct_steps + 1 : correct_steps - 1;  
									else correct_steps <= (read_data == wd_if.data_to_send)? correct_steps + 1 : correct_steps - 1;  
								end 
								`MAX_DAC_BURST_SIZE_ADDR : correct_steps <= (read_data == `MAX_DAC_BURST_SIZE)? correct_steps + 1 : correct_steps - 1;  
								`MEM_SIZE_ADDR 			 : correct_steps <= (read_data == `MEM_SIZE)? correct_steps + 1 : correct_steps - 1;  
								`VERSION_ADDR 		     : correct_steps <= (read_data == `FIRMWARE_VERSION)? correct_steps + 1 : correct_steps - 1;  
								`ABS_ADDR_CEILING 		 : correct_steps <= ($signed(read_data) == -2)? correct_steps + 1 : correct_steps - 1;  
								default: begin 
									if (curr_addr_clkd >= `MAPPED_ADDR_CEILING && curr_addr_clkd < `MEM_TEST_BASE_ADDR) 
										correct_steps <= ($signed(read_data) == -1)? correct_steps + 1 : correct_steps - 1;  							
									else if (curr_addr_clkd >= `MEM_TEST_BASE_ADDR && curr_addr_clkd < `MEM_TEST_END_ADDR) 
										correct_steps <= (read_data == wd_if.data_to_send - 10)? correct_steps + 1 : correct_steps - 1; 	
									else if (curr_addr_clkd >= `MEM_TEST_END_ADDR && curr_addr_clkd < `ABS_ADDR_CEILING) 
										correct_steps <= ($signed(read_data) == -1)? correct_steps + 1 : correct_steps - 1; 	
									else if (`is_PS_VALID(`ADDR2ID(curr_addr_clkd)))
										correct_steps <= (read_data == 0)? correct_steps + 1 : correct_steps - 1; 	
									else 
										correct_steps <= (read_data == wd_if.data_to_send)? correct_steps + 1 : correct_steps - 1;  
								end 
							endcase 
							curr_addr_clkd <= curr_addr_clkd + 4; 
							timer <= (curr_addr_clkd == `ABS_ADDR_CEILING)? 4 : 1;
						end
						if (timer == 4) begin
							timer <= 0;
							testState <= CHECK; 
						end
					end
					// Read/Write past memory space
					if (test_num == 12) begin
						if (timer == 0) begin
							wa_if.data_to_send <= `ABS_ADDR_CEILING + 4; 
							wd_if.data_to_send <= rand_val; 
							{wa_if.send, wd_if.send} <= 3; 
							timer <= 1;
							{correct_steps,test_start} <= 1;
						end 
						if (timer == 1) begin 
							if (wa_if.valid_data) begin
								correct_steps <= (wa_if.data == `ABS_ID_CEILING)? correct_steps + 1 : correct_steps - 1;
								ra_if.data_to_send <= `ABS_ADDR_CEILING + 4; 
								ra_if.send <= 1;
								testState <= READ_DATA;
								timer <= 2;
							end
						end 
						if (timer == 2) begin
							correct_steps <= ($signed(read_data) == -2)? correct_steps + 1 : correct_steps - 1;
							testState <= WRESP_WAIT; 
							timer <= 3;
						end
						if (timer == 3) begin
							timer <= 0;
							testState <= CHECK;
						end
					end
					// Confirm big reg back pressure is implemented correctly (ie valid register is written 0 after rtl reads)
					if (test_num == 13) begin
						if (timer < 100) begin
							if (timer == 0) {correct_steps,rtl_rdy,test_start} <= 1; 
							if (timer != `SDC_SAMPLES) begin
								wa_if.data_to_send <= `SDC_BASE_ADDR + (timer << 2); 
								wd_if.data_to_send <= timer; 
								{wa_if.send, wd_if.send} <= 3;  
								testState <= WRESP_WAIT; 
								timer <= timer + 1;
							end else timer <= 100; 
						end
						if (timer == 100) begin
							ra_if.data_to_send <= `SDC_VALID_ADDR; 
							ra_if.send <= 1; 
							testState <= READ_DATA; 
							timer <= 101; 
						end
						if (timer == 101) begin
							correct_steps <= (read_data == 0)? correct_steps + 1 : correct_steps - 1; 
							wa_if.data_to_send <= `SDC_VALID_ADDR; 
							wd_if.data_to_send <= 1; 
							{wa_if.send, wd_if.send} <= 3;  
							testState <= WRESP_WAIT; 
							timer <= 102;
						end
						if (timer == 102) begin
							ra_if.data_to_send <= `SDC_VALID_ADDR; 
							ra_if.send <= 1; 
							testState <= READ_DATA; 
							timer <= 103; 
						end
						if (timer == 103) begin
							correct_steps <= (read_data == 1)? correct_steps + 1 : correct_steps - 1; 
							rtl_rdy[`SDC_BASE_ID+:`SDC_SAMPLES+1] <= -1; 
							timer <= 104;
						end
						if (timer == 104) begin
							rtl_rdy[`SDC_BASE_ID+:`SDC_SAMPLES+1] <= 0; 
							ra_if.data_to_send <= `SDC_VALID_ADDR; 
							ra_if.send <= 1; 
							testState <= READ_DATA; 
							timer <= 105; 
						end 
						if (timer == 105) begin
							correct_steps <= (read_data == 0)? correct_steps + 1 : correct_steps - 1; 
							timer <= 106;
						end
						if (timer == 106) begin
							correct_steps <= (fresh_bits == 0)? correct_steps + 1 : correct_steps - 1; 
							timer <= 0;
							testState <= CHECK; 
						end
					end
				end
				WRESP_WAIT: begin
					if (wr_if.valid_data || got_wresp[0]) begin
						if (got_wresp[0]) got_wresp <= 0; 
						if (got_wresp[1] || wr_if.data != `OKAY) begin
							kill_tb <= 1; 
							testState <= DONE; 
						end else testState <= TEST; 
					end
				end 
				READ_DATA: begin
					if (rd_if.valid_data) begin
						read_data <= rd_if.data; 
						testState <= TEST; 
					end
				end 
				POLL_CHECK: begin
					if (~fresh_bits[ids[timer-100]]) begin
						correct_steps <= (rtl_rd_out[ids[timer-100]] == 500+(timer-100))? correct_steps + 1 : correct_steps - 1; 
						testState <= TEST; 
					end 
				end 
				CHECK: begin
					test_num <= test_num + 1;
					testState <= (test_num == TOTAL_TESTS-1)? DONE : TEST; 
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
			if (rtl_write_reqs[curr_id] && test_num != 5) rtl_write_reqs[curr_id] <= 0; 
			if (rtl_read_reqs[curr_id] && test_num != 6) rtl_read_reqs[curr_id] <= 0; 
			if (test_start) test_start <= 0; 
			if (clr_rd_out) clr_rd_out <= 0; 
			if (correct_edge == 2) wrong_step <= 1;
			else wrong_step <= 0; 

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
		end
	end

	logic[1:0] testNum_edge;
	logic go; 
	enum logic {WATCH, PANIC} panicState;
	logic[$clog2(TIMEOUT):0] timeout_cntr; 
	edetect #(.DATA_WIDTH(16))
	testNum_edetect (.clk(clk), .rst(rst),
	 				 .val(test_num|correct_steps),
	 				 .comb_posedge_out(testNum_edge)); 

	always_ff @(posedge clk) begin 
		if (rst || testState == IDLE) begin 
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
3. ps performs memory test (perform at top)
*/