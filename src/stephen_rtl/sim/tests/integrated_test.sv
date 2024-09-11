`default_nettype none
`timescale 1ns / 1ps

module integrated_test();
	localparam TIMEOUT = 1000;
	localparam VERBOSE = sim_util_pkg::DEFAULT;
	int total_errors = 0; 

	sim_util_pkg::debug debug = new(VERBOSE,1,"INTEGRATED_TEST"); 

	axi_transmit_test #(.IS_INTEGRATED(1'b1),  .VERBOSE(VERBOSE)) at_test();
	axi_recieve_test  #(.IS_INTEGRATED(1'b1),  .VERBOSE(VERBOSE)) ar_test();
	slave_test     	  #(.IS_INTEGRATED(1'b1),  .VERBOSE(VERBOSE)) slave_test();
	dac_intf_test  	  #(.IS_INTEGRATED(1'b1),  .VERBOSE(VERBOSE)) dac_intf_test();
	intrp_test     	  #(.IS_INTEGRATED(1'b1),  .VERBOSE(VERBOSE)) intrp_test();
	bram_intf_test 	  #(.IS_INTEGRATED(1'b1),  .VERBOSE(VERBOSE)) bram_intf_test();
	cdc_test       	  #(.IS_INTEGRATED(1'b1),  .VERBOSE(VERBOSE)) cdc_test();
	adc_intf_test  	  #(.IS_INTEGRATED(1'b1),  .VERBOSE(VERBOSE)) adc_intf_test();
	pwl_test       	  #(.IS_INTEGRATED(1'b1),  .VERBOSE(VERBOSE)) pwl_test();
	top_test       	  #(.IS_INTEGRATED(1'b1),  .VERBOSE(VERBOSE)) top_test();

	`define any_timed_out at_test.debug.timed_out || ar_test.debug.timed_out || slave_test.debug.timed_out || dac_intf_test.debug.timed_out \
						  || intrp_test.debug.timed_out || cdc_test.debug.timed_out || adc_intf_test.debug.timed_out || pwl_test.debug.timed_out\
						  || top_test.debug.timed_out
	initial begin
        $dumpfile("integrated_test.vcd");
        $dumpvars(0,integrated_test); 
        #1;
        debug.displayc("\n\n### BEGINNING INTEGRATED TEST ###\n\n");
        fork
        	begin
		       	at_test.run_tests();
		       	total_errors+=at_test.debug.get_error_count();
		       	
		       	ar_test.run_tests();
		       	total_errors+=ar_test.debug.get_error_count();
		       	
		       	slave_test.run_tests();
		       	total_errors+=slave_test.debug.get_error_count();
		       	
		       	dac_intf_test.run_tests();
		       	total_errors+=dac_intf_test.debug.get_error_count();	
		       		
		       	intrp_test.run_tests();
		       	total_errors+=intrp_test.debug.get_error_count();

		       	bram_intf_test.run_tests();
		       	total_errors+=bram_intf_test.debug.get_error_count();
		       			
		       	cdc_test.run_tests();
		       	total_errors+=cdc_test.debug.get_error_count();
		       			
		       	adc_intf_test.run_tests();
		       	total_errors+=adc_intf_test.debug.get_error_count();

		       	pwl_test.run_tests();
		       	total_errors+=pwl_test.debug.get_error_count();		

		       	top_test.run_tests();
		       	total_errors+=top_test.debug.get_error_count();		       		       
		    end 
		    begin
		    	while (1) begin
		    		if (`any_timed_out) break;
		    		#1;
		    	end
		    	total_errors+=1;
		    end 
		join_any

		if (total_errors > 0) debug.displayc($sformatf("\n\n### FAILED INTEGRATED TEST SUITE (%0d ERRORS) ###\n\n",total_errors),sim_util_pkg::RED);
		else debug.displayc("\n\n### PASSED INTEGRATED TEST SUITE ###\n\n",sim_util_pkg::GREEN);
		$finish;
    end    
endmodule 

`default_nettype wire

