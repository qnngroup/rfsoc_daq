`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module test_tb #(parameter VERBOSE = 1)(input wire start, output logic[1:0] done);
    localparam TOTAL_TESTS = 5; 
    localparam TIMEOUT = 10_000; 
    localparam PERIODS_TO_CHECK = 3; 
    logic clk, rst;
    logic[15:0] timer; 

    enum logic[1:0] {IDLE, TEST, CHECK, DONE} testState; 
    logic[1:0] test_check; // test_check[0] = check, test_check[1] == 1 => test passed else test failed 
    logic[7:0] test_num; 
    logic[7:0] testsPassed, testsFailed; 
    logic kill_tb; 
    logic panic = 0; 
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
        if (VERBOSE) $display("\n############ Starting PWL Tests ############");
        #100;
        while (testState != DONE && timeout_cntr < TIMEOUT) #10;
        if (timeout_cntr < TIMEOUT) begin
            if (testsFailed != 0) begin 
                if (VERBOSE) $write("%c[1;31m",27); 
                if (VERBOSE) $display("\nPWL Tests Failed :((\n");
                if (VERBOSE) $write("%c[0m",27);
            end else begin 
                if (VERBOSE) $write("%c[1;32m",27); 
                if (VERBOSE) $display("\nPWL Tests Passed :))\n");
                if (VERBOSE) $write("%c[0m",27); 
            end
            #100;
        end else begin
            $write("%c[1;31m",27); 
            $display("\nPWL Tests Timed out on test %d!\n", test_num);
            $write("%c[0m",27);
            #100; 
        end
    end 

endmodule 

`default_nettype wire
