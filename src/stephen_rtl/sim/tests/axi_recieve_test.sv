`default_nettype none
`timescale 1ns / 1ps


module axi_recieve_test #(parameter IS_INTEGRATED = 0,parameter VERBOSE=sim_util_pkg::DEBUG)();
	localparam TIMEOUT = 1000;
	localparam TEST_NUM = 1*12+6; // 1 test for all plus 1 additional address tests for the 32 data widths
	localparam int CLK_RATE_MHZ = 150;
	localparam MAN_SEED = 0;

	sim_util_pkg::debug debug = new(VERBOSE,TEST_NUM,"AXI_RECIEVE",IS_INTEGRATED); 

	logic clk, rst; 
	int total_errors = 0;
	int seed;
	int i,j,done_tests; 
	bit addr_test = 0;
	bit stall = 1;
	logic[5:0][1:0] run,done; 
	localparam[5:0][7:0] bus_widths = {8'd111, 8'd32, 8'd16, 8'd11, 8'd2, 8'd1};
	localparam[1:0][7:0] data_widths = {8'd32, 8'd16};

	generate
		for (genvar i = 0; i < 6; i++) begin : test_sets1
			for (genvar j = 0; j < 2; j++) begin : test_sets2
				Recieve_Transmit_IF #(bus_widths[i], data_widths[j]) intf(); 

				axi_recieve_tb #(.BUS_WIDTH(bus_widths[i]), .DATA_WIDTH(data_widths[j]))
				tb_i(.clk(clk), .rst(rst),
				     .intf(intf));

				axi_receive #(.BUS_WIDTH(bus_widths[i]), .DATA_WIDTH(data_widths[j]))
				dut(.clk(clk), .rst(rst),
				    .is_addr(addr_test),
				    .bus(intf.receive_bus));

				initial begin
					while (stall) @(posedge clk);
					tb_i.init();
					while (~run[i][j]) @(posedge clk); 
					// Tests x: Send random packets with altering bus/data widths
					debug.displayc($sformatf("%0d: Receive 20 random packets (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[i], data_widths[j]), .msg_verbosity(sim_util_pkg::VERBOSE));
					addr_test = 0;
					tb_i.prepare_rand_samples(20);
					tb_i.send_samples();
					debug.check_test(tb_i.check_samples(debug),.has_parts(1));
					reset_errors();

					//Tests y: Send random packets and address space with alternating bus/data widths (only for data widths equal to address width)
					if (j == 1) begin
						debug.displayc($sformatf("%0d: Receive address space (bus_width = %0d, data_width = %0d)",debug.test_num,bus_widths[i], data_widths[j]), .msg_verbosity(sim_util_pkg::VERBOSE));
						addr_test = 1;
						tb_i.prepare_addr_samples();
						tb_i.send_samples();
						if (i == 5) begin
							combine_errors();
							debug.check_test(tb_i.check_samples(debug,.is_addr(1)),.has_parts(1));
						end else begin 
							debug.check_test(tb_i.check_samples(debug,.is_addr(1)),.has_parts(1));
							reset_errors();
						end 
					end 
					done[i][j]= 1; 
				end
			end 
		end
	endgenerate

	always #(0.5s/(CLK_RATE_MHZ*1_000_000)) clk = ~clk;
	initial begin
		if (~IS_INTEGRATED) begin 
	        $dumpfile("axi_recieve_test.vcd");
	        $dumpvars(0,axi_recieve_test);
	        run_tests();	        	
	     end         
    end 

	task automatic reset_errors();
        total_errors += debug.get_error_count();
        debug.clear_error_count(); 
    endtask 
    task automatic combine_errors();
        total_errors += debug.get_error_count();
        debug.set_error_count(total_errors);
    endtask 

    task automatic run_tests();
    	{clk,rst} = 0;
     	repeat (20) @(posedge clk);
        debug.displayc($sformatf("\n\n### TESTING %s ###\n\n",debug.get_test_name()));
     	if (MAN_SEED > 0) begin
            seed = MAN_SEED;
            debug.displayc($sformatf("Using manually selected seed value %0d",seed),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));
        end else begin
            seed = sim_util_pkg::generate_rand_seed();
            debug.displayc($sformatf("Using random seed value %0d",seed),.msg_color(sim_util_pkg::BLUE),.msg_verbosity(sim_util_pkg::VERBOSE));            
        end
        $srandom(seed);
     	debug.timeout_watcher(clk,TIMEOUT);
        repeat (5) @(posedge clk);
        sim_util_pkg::flash_signal(rst,clk);        
       	repeat (20) @(posedge clk);
		{i,j,done_tests,run,done} = '0; 
		stall = 0; 
		while (done_tests < 12) begin
			run[i][j] = 1; 
			while (~done[i][j]) @(posedge clk); 
			if (j == 1) begin
				j = 0;
				i+=1; 
			end else j+=1;
			done_tests+=1; 
		end 
        if (~IS_INTEGRATED) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        else if (debug.test_num < TEST_NUM) debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
        debug.set_test_complete();
    endtask
endmodule 

`default_nettype wire

// 243 lines of code -> 