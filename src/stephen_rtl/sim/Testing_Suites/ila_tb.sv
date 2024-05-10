`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module ila_tb #(parameter VERBOSE = 1)(input wire start, output logic[1:0] done);
    // localparam TOTAL_TESTS = 3; 
    // localparam TIMEOUT = 10_000; 
    // logic clk, rst;
    // logic[15:0] timer; 

    // enum logic[1:0] {IDLE, TEST, CHECK, DONE} testState; 
    // logic[1:0] test_check; // test_check[0] = check, test_check[1] == 1 => test passed else test failed 
    // logic[7:0] test_num; 
    // logic[7:0] testsPassed, testsFailed; 
    // logic kill_tb; 
    // logic panic = 0; 

    // logic got_sample;
    // logic[15:0] sample_buff,sample_out; 
    // logic[255:0] ila_line_in; 
    // logic[9:0][255:0] lines; 
    // logic[159:0][15:0] all_samples; 
    // logic[3:0] ila_index; 
    // logic valid_sample; 
    // logic set_trigger,trigger_event;
    // logic[7:0] sample_buff_ptr;
    // logic[15:0] curr_expected_sample;
    // logic[1:0] save_condition; 
    // logic[$clog2(`MAX_ILA_BURST_SIZE):0] ila_burst_size_in; 

    // assign lines = {16'h2417,16'hc723,16'hce30,16'he6ad,16'h4a86,16'h991a,16'hc9c2,16'h7988,16'h6e92,16'haa3d,16'h161d,16'h297b,16'h736d,16'h2976,16'h102b,16'hc6c7,
    //                 16'h0b35,16'haec5,16'h9b40,16'h8065,16'hb9d3,16'ha186,16'h520d,16'h480b,16'h3540,16'h01e3,16'h5a8b,16'h3e79,16'h5831,16'h5668,16'h46ac,16'h3beb,
    //                 16'h8445,16'h494a,16'h3330,16'h4113,16'h43bc,16'h6d89,16'h8758,16'hb158,16'h430c,16'h372a,16'h2bcd,16'ha303,16'h0c26,16'h8ac8,16'h7876,16'h9a55,
    //                 16'h8a20,16'h80a3,16'h7b25,16'h3998,16'h021b,16'h6732,16'h494e,16'hd5c5,16'haada,16'h7176,16'h6a07,16'hba35,16'h90b0,16'h3c08,16'h1d0b,16'h87e7,
    //                 16'h5c7d,16'hb122,16'h7276,16'he64a,16'h71be,16'h9c29,16'h930b,16'h4bd9,16'hd8a7,16'hc532,16'h9da1,16'h8709,16'ha7b6,16'hec75,16'h6b1d,16'ha16d,
    //                 16'hd723,16'h1455,16'h360c,16'h5695,16'he882,16'hbb27,16'h44e3,16'ha28b,16'ha335,16'hb019,16'h015b,16'h750b,16'h578e,16'hb84b,16'h51e6,16'h19e5,
    //                 16'he443,16'h8655,16'ha242,16'h04e4,16'hca13,16'h2067,16'h8332,16'he8d9,16'ha86c,16'h1910,16'hc6a8,16'h9c92,16'h11e7,16'he126,16'h9cad,16'h704e,
    //                 16'h2979,16'ha29d,16'hc07d,16'h9be1,16'h152a,16'h13ca,16'hc57a,16'hc09a,16'h6c99,16'h9a9e,16'h94e2,16'h3533,16'h900a,16'hd193,16'he6ae,16'h2e07,
    //                 16'h591b,16'h757d,16'h7251,16'h35a3,16'he534,16'h6442,16'h364c,16'hcc2a,16'h5eb3,16'h2247,16'heca4,16'h675b,16'h5cc8,16'hca71,16'hd09a,16'h564e,
    //                 16'h9175,16'h94dc,16'h7642,16'hbb63,16'hdc1c,16'hbaba,16'he8bd,16'hdbd6,16'hebb7,16'h1d44,16'h1783,16'h0100,16'heab8,16'h9e44,16'hd8a3,16'h5873};
    // assign all_samples = lines; 
    // assign ila_line_in = lines[ila_index]; 
    // always @(*) begin 
    //     if (sample_buff_ptr != 0) begin
    //         curr_expected_sample = (test_num == 2 && sample_buff_ptr%16 == 0)? all_samples[(sample_buff_ptr-16)-1] : all_samples[sample_buff_ptr-1];
    //     end else curr_expected_sample = 0; 
    // end 
    // ila #(.LINE_WIDTH(256), .SAMPLE_WIDTH (16), .MAX_ILA_BURST_SIZE (`MAX_ILA_BURST_SIZE))
    // DUT(.clk(clk), .rst(rst),
    //     .ila_line_in(ila_line_in),
    //     .set_trigger(set_trigger),
    //     .trigger_event(trigger_event),
    //     .save_condition(save_condition),
    //     .sample_pulled(got_sample),
    //     .ila_burst_size_in(ila_burst_size_in),
    //     .sample_to_send(sample_out),
    //     .valid_sample_out(valid_sample));

    // //State machine for saving lines to the ila and simulating reciveing samples as the ps. 
    // enum logic[1:0] {IDLE0, TRIGGER, SAVE_LINES, GET_SAMPLES} psIlaState; 
    // always_ff @(posedge clk) begin
    //     if (rst) begin
    //         psIlaState <= IDLE0; 
    //         {set_trigger, trigger_event, got_sample, timer, ila_index} <= 0; 
    //         {sample_buff_ptr, sample_buff, save_condition, ila_burst_size_in} <= 0;
    //     end else begin 
    //         case(psIlaState) 
    //             IDLE0: begin
    //                 if (testState == TEST) begin 
    //                     if (timer == 20) begin
    //                         timer <= 0; 
    //                         set_trigger <= 1; 
    //                         if (test_num == 0) ila_burst_size_in <= 5; 
    //                         else ila_burst_size_in <= 10; 
    //                         psIlaState <= TRIGGER;
    //                     end else timer <= timer + 1; 
    //                 end
    //             end 

    //             TRIGGER: begin
    //                 if (timer == 25) begin
    //                     timer <= 0; 
    //                     trigger_event <= 1; 
    //                     psIlaState <= SAVE_LINES;
    //                     if (test_num == 2) save_condition <= {1'b1, 1'b1};
    //                 end else timer <= timer + 1; 
    //             end 

    //             SAVE_LINES: begin
    //                 if (ila_index == 9) begin
    //                     ila_index <= 0; 
    //                     save_condition <= 0; 
    //                     psIlaState <= GET_SAMPLES; 
    //                 end else begin 
    //                     ila_index <= ila_index + 1;
    //                     if (test_num == 2) save_condition <= {1'b1, (ila_index+1)%2 == 0};
    //                 end 
    //             end 

    //             GET_SAMPLES: begin
    //                 if ((test_num == 0 && sample_buff_ptr < 80) || (test_num == 1 && sample_buff_ptr < 160) || (test_num == 2 && sample_buff_ptr < 144)) begin
    //                      if (timer == 10) begin
    //                         if (valid_sample) begin
    //                             timer <= 0; 
    //                             sample_buff <= sample_out; 
    //                             sample_buff_ptr <= (test_num == 2 && (sample_buff_ptr+1)%16 == 0)? (sample_buff_ptr+1)+16 : sample_buff_ptr + 1;
    //                             got_sample <= 1;
    //                         end
    //                     end else timer <= timer + 1; 
    //                 end else begin
    //                     sample_buff_ptr <= 0;  
    //                     psIlaState <= IDLE0;  
    //                 end 
    //             end 
    //         endcase 

    //         if (set_trigger) set_trigger <= 0; 
    //         if (trigger_event) trigger_event <= 0; 
    //         if (got_sample) got_sample <= 0;
    //     end 
    // end

    // always_comb begin
    //     if ((test_num == 0  || test_num == 1 ) && psIlaState == GET_SAMPLES) begin 
    //         test_check = (got_sample)? {sample_buff == curr_expected_sample,1'b1} : 0;
    //     end else if (test_num == 2 && psIlaState == GET_SAMPLES) begin 
    //         test_check = (got_sample)? {sample_buff == curr_expected_sample,1'b1} : 0;
    //     end
    //     else test_check = 0; 
    // end

    // always_ff @(posedge clk) begin
    //     if (rst || panic) begin
    //         if (panic) begin
    //             testState <= DONE;
    //             kill_tb <= 1; 
    //             panic <= 0;
    //         end else begin
    //             testState <= IDLE;
    //             {test_num,testsPassed,testsFailed, kill_tb} <= 0; 
    //             done <= 0;
    //         end
    //     end else begin
    //         case(testState)
    //             IDLE: begin 
    //                 if (start) testState <= TEST; 
    //                 if (done) done <= 0; 
    //             end 
    //             TEST: begin
    //                 // Let the ila read in half the lines from the line buffer and ensure that every samples comes out in the right order (and also that it can handle arbitrary ps delay). 
    //                 if (test_num == 0) begin         
    //                     if (sample_buff_ptr == 80) testState <= CHECK; 
    //                 end
    //                 // Let the ila read all the lines from the line buffer and ensure that every samples comes out in the right order (and also that it can handle arbitrary ps delay). This tests that ila_burst_size can change and be reflected in the ILA 
    //                 if (test_num == 1) begin         
    //                     if (sample_buff_ptr == 160) testState <= CHECK; 
    //                 end
    //                 // Use the save condition to select for every other line to be saved and ensure that every samples comes out in the right order (and also that it can handle arbitrary ps delay). 
    //                 if (test_num == 2) begin         
    //                     if (sample_buff_ptr == 160) testState <= CHECK; 
    //                 end
    //             end 
    //             CHECK: begin
    //                 test_num <= test_num + 1;
    //                 if (test_num < TOTAL_TESTS-1) begin
    //                     testState <= TEST;
    //                     $write("\n\n"); 
    //                 end else testState <= DONE;                     
    //             end 

    //             DONE: begin 
    //                 done <= {testsFailed == 0 && ~kill_tb,1'b1}; 
    //                 testState <= IDLE; 
    //                 test_num <= 0; 
    //             end 
    //         endcase

    //         if (test_check[0]) begin
    //             if (test_check[1]) begin 
    //                 testsPassed <= testsPassed + 1;
    //                 if (VERBOSE) $write("%c[1;32m",27); 
    //                 if (VERBOSE) $write("t%0d_%0d+ ",test_num,sample_buff_ptr-1);
    //                 if (VERBOSE) $write("%c[0m",27); 
    //             end 
    //             else begin 
    //                 testsFailed <= testsFailed + 1; 
    //                 if (VERBOSE) $write("%c[1;31m",27); 
    //                 if (VERBOSE) $write("t%0d_%0d- ",test_num,sample_buff_ptr-1);
    //                 if (VERBOSE) $write("%c[0m",27); 
    //             end 
    //         end 

    //     end
    // end

    // logic[1:0] testNum_edge;
    // logic go; 
    // enum logic {WATCH, PANIC} panicState; 
    // logic[$clog2(TIMEOUT):0] timeout_cntr; 
    // edetect #(.DATA_WIDTH(8))
    // testNum_edetect (.clk(clk), .rst(rst),
    //                  .val(test_num),
    //                  .comb_posedge_out(testNum_edge));  

    // always_ff @(posedge clk) begin 
    //     if (rst) begin 
    //         {timeout_cntr,panic} <= 0;
    //         panicState <= WATCH;
    //         go <= 0; 
    //     end 
    //     else begin
    //         if (go) begin
    //             case(panicState) 
    //                 WATCH: begin
    //                     if (timeout_cntr <= TIMEOUT) begin
    //                         if (testNum_edge == 1) timeout_cntr <= 0;
    //                         else timeout_cntr <= timeout_cntr + 1;
    //                     end else begin
    //                         panic <= 1; 
    //                         panicState <= PANIC; 
    //                     end 
    //                 end 
    //                 PANIC: if (panic) panic <= 0; 
    //             endcase
    //         end 
    //         if (start) go <= 1; 
    //     end
    // end 

    // always begin
    //     #5;  
    //     clk = !clk;
    // end
     
    // initial begin
    //     clk = 0;
    //     rst = 0; 
    //     `flash_sig(rst); 
    //     while (~start) #1; 
    //     if (VERBOSE) $display("\n############ Starting ILA Test ############");
    //     #100;
    //     while (testState != DONE && timeout_cntr < TIMEOUT) #10;
    //     if (timeout_cntr < TIMEOUT) begin
    //         if (testsFailed != 0) begin 
    //             if (VERBOSE) $write("%c[1;31m",27); 
    //             if (VERBOSE) $display("\nILA Tests Failed :((\n");
    //             if (VERBOSE) $write("%c[0m",27);
    //         end else begin 
    //             if (VERBOSE) $write("%c[1;32m",27); 
    //             if (VERBOSE) $display("\nILA Tests Passed :))\n");
    //             if (VERBOSE) $write("%c[0m",27); 
    //         end
    //         #100;
    //     end else begin
    //         $write("%c[1;31m",27); 
    //         $display("\nILA Tests Timed out on test %d!\n", test_num);
    //         $write("%c[0m",27);
    //         #100; 
    //     end
    // end 

endmodule 


`default_nettype wire
