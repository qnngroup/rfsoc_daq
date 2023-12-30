`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module axi_recieve_transmit_tb #(parameter VERBOSE = 1)(input wire start, output logic[1:0] done);
  localparam TOTAL_TESTS = `ADDR_NUM + 18; 
  localparam TIMEOUT = 10_000;

  logic clk, rst;
  logic kill_test; 

  Recieve_Transmit_IF #(`A_BUS_WIDTH, `A_DATA_WIDTH) a_if (); 
  Recieve_Transmit_IF #(`WD_BUS_WIDTH, `WD_DATA_WIDTH) wd_if (); 
  assign a_if.dev_rdy = 1'b1; 
  assign wd_if.dev_rdy = 1'b1; 

  axi_receive #(.BUS_WIDTH(`A_BUS_WIDTH), .DATA_WIDTH(`A_DATA_WIDTH))
  addr_recieve(.clk(clk), .rst(rst),
               .bus(a_if.receive_bus),
               .is_addr(1'b1));  

  axi_receive #(.BUS_WIDTH(`WD_BUS_WIDTH), .DATA_WIDTH(`WD_DATA_WIDTH))
  data_recieve(.clk(clk), .rst(rst),
               .bus(wd_if.receive_bus),
               .is_addr(1'b0));

  axi_transmit #(.BUS_WIDTH(`A_BUS_WIDTH), .DATA_WIDTH(`A_DATA_WIDTH))
  addr_transmit(.clk(clk), .rst(rst),
                .bus(a_if.transmit_bus));

  axi_transmit #(.BUS_WIDTH(`WD_BUS_WIDTH), .DATA_WIDTH(`WD_DATA_WIDTH))
  wd_transmit(.clk(clk), .rst(rst),
              .bus(wd_if.transmit_bus));

  enum logic[1:0] {IDLE, TEST, CHECK, DONE} testState; 
  logic[1:0] test_check; // test_check[0] = check, test_check[1] == 1 => test passed else test failed 
  logic[7:0] test_num; 
  logic[7:0] testsPassed, testsFailed; 

  logic[`WD_DATA_WIDTH-1:0] curr_id;
  assign curr_id = (test_num < `ADDR_NUM)? ids[test_num] : 0; 

  always_comb begin
    if (testState == CHECK) begin
      if (test_num < `ADDR_NUM) test_check = (a_if.valid_data)? {(a_if.data == curr_id),1'b1} : 0;
      else test_check = (wd_if.valid_data)? {(wd_if.data_to_send == wd_if.data),1'b1} : 0;
    end
    else test_check = 0; 
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
        
        {a_if.data_to_send, wd_if.data_to_send} <= 0;
        {wd_if.send, a_if.send} <= 0; 
      end
    end else begin
      case(testState)
        IDLE: begin 
          if (start) testState <= TEST; 
          if (done) done <= 0; 
        end 
        TEST: begin
          // Send all addrs and ensure the correct mem_id is recieved 
          if (test_num < `ADDR_NUM && a_if.trans_rdy) begin 
            a_if.data_to_send <= addrs[test_num];
            a_if.send <= 1;
          end 
          // Send random data and ensure that data is recieved. 
          else if (wd_if.trans_rdy) begin 
            wd_if.data_to_send <= (test_num != `ADDR_NUM + 17)? 32'hBEEF << test_num-13 : -1;
            wd_if.send <= 1; 
          end
          testState <= CHECK;
        end 
        CHECK: begin
          {a_if.send,wd_if.send} <= 0; 
          if (a_if.valid_data || wd_if.valid_data) begin
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

