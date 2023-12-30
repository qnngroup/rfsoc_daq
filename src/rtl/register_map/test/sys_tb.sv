`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module sys_tb #(parameter VERBOSE = 1)(input wire start, output logic[1:0] done);
    localparam TOTAL_TESTS = 9; 
    localparam STARTING_TEST = 0; 
    localparam TIMEOUT = 10_000; 
    localparam SKIP_TRIVIAL_TESTS = 0;
    localparam SKIP_ILA_TEST = 0;
    logic clk, rst;
    logic[15:0] timer; 

    enum logic[2:0] {IDLE, TEST, WRESP, CHECK, DONE} testState; 
    logic[1:0] test_check; // test_check[0] = check, test_check[1] == 1 => test passed else test failed 
    logic[7:0] test_num; 
    logic[7:0] testsPassed, testsFailed; 
    logic kill_tb; 
    logic panic = 0; 

    logic[1:0] got_wresp;  //[1] == error bit (wr_if.data wasn't okay when recieved), [0] == sys saw a wr_if.data 
    logic[(`BATCH_WIDTH)-1:0] dac_batch;
    logic valid_dac_batch;
    logic dac0_rdy;
    logic pl_rstn;
    logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] init_samples, dac_samples;
    logic[`BATCH_SAMPLES-1:0] test_check_vector; 
    logic[1:0] dac_check, valid_dac_edge; 

    Recieve_Transmit_IF #(`A_BUS_WIDTH, `A_DATA_WIDTH)   wa_if (); 
    Recieve_Transmit_IF #(`WD_BUS_WIDTH, `WD_DATA_WIDTH) wd_if (); 
    Recieve_Transmit_IF #(`A_BUS_WIDTH, `A_DATA_WIDTH)   ra_if (); 
    Recieve_Transmit_IF #(`WD_BUS_WIDTH, `WD_DATA_WIDTH) rd_if (); 
    Recieve_Transmit_IF #(2,2) wr_if (); 
    Recieve_Transmit_IF #(2,2) rr_if ();

    Axis_IF #(`DMA_DATA_WIDTH) pwl_dma_if(); 

    assign wa_if.dev_rdy    = 1;
    assign wd_if.dev_rdy    = 1;
    assign ra_if.dev_rdy    = 1;
    assign rr_if.dev_rdy    = 1;
    assign {rr_if.data_to_send, rr_if.data, rr_if.send, rr_if.trans_rdy} = 0;

    axi_transmit #(.BUS_WIDTH(`A_BUS_WIDTH), .DATA_WIDTH(`A_DATA_WIDTH))
    waddr_ps_transmitter(.clk(clk), .rst(rst),
                         .bus(wa_if.transmit_bus));
    axi_transmit #(.BUS_WIDTH(`WD_BUS_WIDTH), .DATA_WIDTH(`A_DATA_WIDTH))
    wdata_ps_transmitter(.clk(clk), .rst(rst),
                         .bus(wd_if.transmit_bus));
    axi_transmit #(.BUS_WIDTH(`A_BUS_WIDTH), .DATA_WIDTH(`A_DATA_WIDTH))
    raddr_ps_transmitter(.clk(clk), .rst(rst),
                         .bus(ra_if.transmit_bus));      
    axi_receive #(.BUS_WIDTH(`WD_BUS_WIDTH), .DATA_WIDTH(`WD_DATA_WIDTH))
    ps_rdata_recieve(.clk(clk), .rst(rst),
                     .bus(rd_if.receive_bus),
                     .is_addr(1'b0));               
    axi_receive #(.BUS_WIDTH(2), .DATA_WIDTH(2))
    ps_wresp_recieve(.clk(clk), .rst(rst),
                     .bus(wr_if.receive_bus),
                     .is_addr(1'b0)); 
    axi_receive #(.BUS_WIDTH(2), .DATA_WIDTH(2))
    ps_rresp_recieve(.clk(clk), .rst(rst),
                     .bus(rr_if.receive_bus),
                     .is_addr(1'b0));

    sys sys (.clk(clk), .sys_rst(rst),
             .dac0_rdy(dac0_rdy),
             .dac_batch(dac_batch),
             .valid_dac_batch(valid_dac_batch),
             .pl_rstn(pl_rstn),
             .wa_if(wa_if), .wd_if(wd_if),
             .ra_if(ra_if), .rd_if(rd_if),
             .wr_if(wr_if), .rr_if(rr_if),
             .pwl_dma_if(pwl_dma_if)); 

    oscillate_sig #(.DELAY (10))
    dac_rdy_oscillator(.clk(clk), .rst(rst), .long_on(1'b1),
                       .osc_sig_out(dac0_rdy));
    oscillate_sig #(.DELAY (25))
    read_rdy_oscillator(.clk(clk), .rst(rst), .long_on(1'b1),
                        .osc_sig_out(rd_if.dev_rdy));
    oscillate_sig #(.DELAY (30))
    wresp_rdy_oscillator(.clk(clk), .rst(rst), .long_on(1'b1),
                        .osc_sig_out(wr_if.dev_rdy));

    generate
        for (genvar i = 0; i < `BATCH_SAMPLES; i++) begin: batch_splices
            data_splicer #(.DATA_WIDTH(`BATCH_WIDTH), .SPLICE_WIDTH(`SAMPLE_WIDTH))
            dac_out_splice(.data(dac_batch),
                           .i(int'(i)),
                           .spliced_data(dac_samples[i]));
        end
    endgenerate

  
    edetect valid_dac_edetect(.clk(clk), .rst(rst),
                              .val(valid_dac_batch),
                              .comb_posedge_out(valid_dac_edge)); 
    //processor ILA statemachine (for pulling and examing samples stored on the ila)
    enum logic[2:0] {IDLE0, POLL, WAIT, PASS, FAIL} psIlaState; 
    logic[7:0] ila_timer, delay_timer;
    logic[15:0] expected_out, curr_ila_sample_response; 
    logic start_psila_statemachine; 

    assign curr_ila_sample_response = sys.slave.mem_map[`DAC_ILA_RESP_ID];
    always_ff @(posedge clk) begin
        if (rst) begin
            {ila_timer,start_psila_statemachine,expected_out,delay_timer} <= 0; 
            psIlaState <= IDLE0; 
        end else begin
            case(psIlaState)
                IDLE0: begin
                    if (start_psila_statemachine) psIlaState <= POLL; 
                end 
                POLL: begin 
                    if (expected_out == 192) begin
                        expected_out <= 0;
                        psIlaState <= PASS; 
                    end else begin
                        if (ila_timer == 0) begin 
                            ra_if.data_to_send <= `DAC_ILA_RESP_VALID_ADDR;
                            ra_if.send <= 1; 
                            ila_timer <= 1; 
                        end 
                        if (ila_timer == 1) begin
                            if (rd_if.valid_data) begin
                                if (rd_if.data) ila_timer <= 2; 
                                else begin 
                                    ila_timer <= 0; 
                                    psIlaState <= WAIT;
                                end 
                            end
                        end 
                        if (ila_timer == 2) begin 
                            ra_if.data_to_send <= `DAC_ILA_RESP_ADDR;
                            ra_if.send <= 1; 
                            ila_timer <= 3; 
                        end 
                        if (ila_timer == 3) begin
                            if (rd_if.valid_data) begin
                                if (rd_if.data != expected_out) psIlaState <= FAIL; 
                                else begin
                                    expected_out <= expected_out + 1; 
                                    ila_timer <= 0;
                                    psIlaState <= WAIT; 
                                end 
                            end
                        end
                    end 
                end 
                WAIT: begin
                    if (delay_timer == 150) begin
                        delay_timer <= 0;
                        psIlaState <= POLL;
                    end else delay_timer <= delay_timer + 1;
                end 
            endcase 
            if (~start_psila_statemachine) psIlaState <= IDLE0;
        end
    end
    always_comb begin
        if (test_num == 0) 
            test_check = {sys.rst, sys.rst}; 
        else if (test_num == 1)  
            test_check = dac_check;
        else if (test_num == 2) begin 
            if (valid_dac_batch && testState == TEST) begin
                for (int i = 1; i < `BATCH_SAMPLES; i++) test_check_vector[i] = dac_samples[i] == dac_samples[i-1]+1; 
                test_check_vector[0] = 1; 
                test_check = {&test_check_vector, 1'b1};
            end else test_check = 0; 
        end 
        else if (test_num == 3)  
            test_check = (~valid_dac_batch && dac0_rdy && testState == TEST)? {1'b1, 1'b1} : 0;
        else if (test_num == 4)  
            test_check = (testState == TEST && rd_if.valid_data && ila_timer == 3)? {rd_if.data == expected_out, 1'b1} : 0;
        else if (test_num == 5)  
            test_check = (rd_if.valid_data)? {rd_if.data == `MAX_ILA_BURST_SIZE, 1'b1} : 0;
        else if (test_num == 6)  
            test_check = (testState == CHECK)? {1'b1, 1'b1} : 0;
        else if (test_num == 7)  
            test_check = (testState == CHECK)? {1'b1, 1'b1} : 0;
        else if (test_num == 8) begin
            if (timer == 1 && valid_dac_edge == 1 && sys.dac_intf.produce_rand_samples) test_check = {(dac_samples[0] == 16'hBEEF && sys.dac_intf.produce_rand_samples), 1'b1};
            else if (timer == 3 && valid_dac_edge == 1 && sys.dac_intf.produce_trig_wave) test_check = {(dac_samples[5:0] == {16'd5, 16'd4, 16'd3, 16'd2, 16'd1, 16'd0} && sys.dac_intf.produce_trig_wave), 1'b1};
            else if (timer == 5 && valid_dac_edge == 1 && sys.dac_intf.produce_pwl) test_check = {(dac_samples[0] != 16'hBEEF && dac_samples[5:0] != {16'd5, 16'd4, 16'd3, 16'd2, 16'd1, 16'd0} && sys.dac_intf.produce_pwl), 1'b1};
            else test_check = 0; 
        end else test_check = 0; 
    end

    always_ff @(posedge clk) begin
        if (rst || panic) begin
            if (panic) begin
                testState <= DONE;
                kill_tb <= 1; 
                panic <= 0;
            end else begin
                testState <= IDLE;
                {testsPassed,testsFailed, kill_tb} <= 0; 
                {done, timer} <= 0;
                test_num <= STARTING_TEST; 

                {wa_if.data_to_send, wd_if.data_to_send, ra_if.data_to_send} <= 0;
                {wa_if.send, wd_if.send, ra_if.send} <= 0;
                for (int i = 0; i < `BATCH_SAMPLES; i++) init_samples[i] <= 16'hBEEF + i; 
            end
        end else begin
            case(testState)
                IDLE: begin 
                    if (start) testState <= TEST; 
                    if (done) done <= 0; 
                end 
                TEST: begin
                    // Reset the system and ensure reset goes high
                    if (test_num == 0) begin  
                        if (timer == 0) begin
                            wa_if.data_to_send <= `RST_ADDR;
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            timer <= 1;  
                            testState <= WRESP;  
                        end else if (timer == 1) begin
                            if (sys.rst) begin
                                testState <= CHECK; 
                                timer <= 0; 
                            end
                        end
                    end
                    // Send seed values and make sure random wave gets generated; halt dac
                    if (test_num == 1) begin 
                        if (`PS_SEED_BASE_ADDR + 4*timer < `TRIG_WAVE_ADDR) begin        
                            wa_if.data_to_send <= `PS_SEED_BASE_ADDR + 4*timer; 
                            wd_if.data_to_send <= (`PS_SEED_BASE_ADDR + 4*timer == `PS_SEED_VALID_ADDR)? 1 : init_samples[timer]; 
                            {wa_if.send, wd_if.send} <= 3;
                            timer <= timer + 1;
                            testState <= WRESP;
                        end else if (valid_dac_batch || $signed(timer) == -1) begin
                            if ($signed(timer) == -1) begin
                                dac_check[0] <= 1; 
                                timer <= 0;
                                testState <= CHECK; 
                            end else begin
                                wa_if.data_to_send <= `DAC_HLT_ADDR;
                                wd_if.data_to_send <= 1; 
                                {wa_if.send, wd_if.send} <= 3;
                                timer <= -1; 
                                testState <= WRESP; 
                            end 
                        end 
                    end
                    // Ensure trig wave can get generated
                    if (test_num == 2) begin         
                        if (timer == 0) begin
                            wa_if.data_to_send <= `TRIG_WAVE_ADDR;
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            timer <= 1; 
                            testState <= WRESP; 
                        end else if (valid_dac_batch) begin
                            timer <= 0;
                            testState <= CHECK;
                        end 
                    end
                    // Ensure dac can be halted
                    if (test_num == 3) begin         
                        if (timer == 0) begin
                            wa_if.data_to_send <= `DAC_HLT_ADDR;
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            timer <= 1; 
                            testState <= WRESP; 
                        end else if (~valid_dac_batch) begin
                            timer <= 0;
                            testState <= CHECK;
                        end 
                    end
                    // Trigger the ila and send 3 lines of data from twave. Make sure each recieved sample is +1 from the other. 
                    if (test_num == 4) begin  
                        if (timer == 151) begin
                            if (psIlaState == PASS || psIlaState == FAIL) begin
                                timer <= 0;
                                start_psila_statemachine <= 0;
                                $write("\n\n"); 
                                testState <= CHECK;
                            end 
                        end else timer <= timer + 1; 

                        if (timer == 0) begin
                            wa_if.data_to_send <= `DAC_ILA_TRIG_ADDR;
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP; 
                        end

                        if (timer == 25) begin
                            wa_if.data_to_send <= `ILA_BURST_SIZE_ADDR;
                            wd_if.data_to_send <= 3; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end 

                        if (timer == 50) begin
                            wa_if.data_to_send <= `TRIG_WAVE_ADDR;
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end 

                        if (timer == 150) start_psila_statemachine <= 1; 
                    end
                    // Read the max burst size from the sys 
                    if (test_num == 5) begin
                        if (timer == 0) begin   
                            ra_if.data_to_send <= `MAX_BURST_SIZE_ADDR; 
                            ra_if.send <= 1;  
                            timer <= 1; 
                        end else begin
                            if (rd_if.valid_data) begin
                                testState <= CHECK; 
                                timer <= 0; 
                            end 
                        end    
                    end
                    // Send random signal and scale the dac output by 1, 2, 5, and 15 (passes trivially, look to wave-viewer to ensure waves get smaller)
                    if (test_num == 6) begin  
                        if (timer == 2000) begin
                            timer <= 0;
                            testState <= CHECK; 
                        end else timer <= timer + 1; 

                        if (timer == 0) begin
                            wa_if.data_to_send <= `ILA_BURST_SIZE_ADDR;
                            wd_if.data_to_send <= 0; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == 1) begin
                            wa_if.data_to_send <= `PS_SEED_VALID_ADDR;
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == 50) begin
                            wa_if.data_to_send <= `SCALE_DAC_OUT_ADDR;
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == 600) begin
                            wa_if.data_to_send <= `SCALE_DAC_OUT_ADDR;
                            wd_if.data_to_send <= 2; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == 1200) begin
                            wa_if.data_to_send <= `SCALE_DAC_OUT_ADDR;
                            wd_if.data_to_send <= 5; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == 1600) begin
                            wa_if.data_to_send <= `SCALE_DAC_OUT_ADDR;
                            wd_if.data_to_send <= 15; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == 1800) begin
                            wa_if.data_to_send <= `SCALE_DAC_OUT_ADDR;
                            wd_if.data_to_send <= 16; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == 1900) begin
                            wa_if.data_to_send <= `SCALE_DAC_OUT_ADDR;
                            wd_if.data_to_send <= 1501; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                    end
                    // Send twave signal and scale the dac output by 1, 2, 5, and 15 (passes trivially, look to wave-viewer to ensure waves get smaller)
                    if (test_num == 7) begin  
                        if (timer == 5100) begin
                            timer <= 0;
                            testState <= CHECK; 
                        end else timer <= timer + 1; 

                        if (timer == 0) begin
                            wa_if.data_to_send <= `DAC_HLT_ADDR;
                            wd_if.data_to_send <= 1;
                            {wa_if.send, wd_if.send} <= 3; 
                            testState <= WRESP;
                        end
                        if (timer == 1) begin
                            wa_if.data_to_send <= `SCALE_DAC_OUT_ADDR;
                            wd_if.data_to_send <= 0;
                            {wa_if.send, wd_if.send} <= 3; 
                            testState <= WRESP;
                        end
                        if (timer == 2) begin
                            wa_if.data_to_send <= `TRIG_WAVE_ADDR;
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == 2000) begin
                            wa_if.data_to_send <= `SCALE_DAC_OUT_ADDR;
                            wd_if.data_to_send <= 1;
                            {wa_if.send, wd_if.send} <= 3; 
                            testState <= WRESP;
                        end
                        if (timer == 4000) begin
                            wa_if.data_to_send <= `SCALE_DAC_OUT_ADDR;
                            wd_if.data_to_send <= 2; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == 5000) begin
                            wa_if.data_to_send <= `SCALE_DAC_OUT_ADDR;
                            wd_if.data_to_send <= 5; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == 5050) begin
                            wa_if.data_to_send <= `SCALE_DAC_OUT_ADDR;
                            wd_if.data_to_send <= 15; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == 5080) begin
                            wa_if.data_to_send <= `SCALE_DAC_OUT_ADDR;
                            wd_if.data_to_send <= 16; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == 5090) begin
                            wa_if.data_to_send <= `SCALE_DAC_OUT_ADDR;
                            wd_if.data_to_send <= 1501; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == 5091) begin
                            wa_if.data_to_send <= `SCALE_DAC_OUT_ADDR;
                            wd_if.data_to_send <= 0; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == 5099) begin
                            wa_if.data_to_send <= `DAC_HLT_ADDR;
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP; 
                        end
                    end    
                    // Start up different modes sequentially and ensure they get initiated. 
                    if (test_num == 8) begin 
                        if (timer == 1 && valid_dac_edge == 1 && sys.dac_intf.produce_rand_samples) begin
                            timer <= 2;
                            testState <= WRESP; 
                        end 
                        if (timer == 3 && valid_dac_edge == 1 && sys.dac_intf.produce_trig_wave) begin
                            timer <= 4;
                            testState <= WRESP; 
                        end 
                        if (timer == 5 && valid_dac_edge == 1 && sys.dac_intf.produce_pwl) begin
                            timer <= 0; 
                            testState <= CHECK;
                        end 

                        if (timer == 0) begin
                            wa_if.data_to_send <= `PS_SEED_VALID_ADDR;
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            timer <= 1;
                        end
                        if (timer == 2) begin
                            wa_if.data_to_send <= `TRIG_WAVE_ADDR;
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            timer <= 3;
                        end
                         if (timer == 4) begin
                            wa_if.data_to_send <= `RUN_PWL_ADDR;
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            timer <= 5;
                        end
                            
                    end            
                end 
                WRESP: begin
                    if (wr_if.valid_data || got_wresp[0]) begin
                        if (got_wresp[0]) got_wresp <= 0; 
                        if (got_wresp[1] || wr_if.data != `OKAY) begin
                            kill_tb <= 1; 
                            testState <= DONE; 
                        end else testState <= TEST; 
                    end
                end 
                CHECK: begin
                    if (test_num == 5 && SKIP_TRIVIAL_TESTS) begin
                        test_num <= 8;
                        $display("\nSkipping trivial tests 6 and 7");
                    end else if (test_num == 3 && SKIP_ILA_TEST) begin
                        test_num <= 5;
                        $display("\nSkipping ila test");
                    end else test_num <= test_num + 1;
                    testState <= (test_num < TOTAL_TESTS-1)? TEST : DONE; 
                end 

                DONE: begin 
                    done <= {testsFailed == 0 && ~kill_tb,1'b1}; 
                    testState <= IDLE; 
                    test_num <= 0; 
                end 
            endcase

            if (test_num == 1 && valid_dac_edge == 1 && dac_batch == init_samples) dac_check[1] <= 1; 

            if (wa_if.send) wa_if.send <= 0; 
            if (wd_if.send) wd_if.send <= 0; 
            if (ra_if.send) ra_if.send <= 0; 
            if (testState != WRESP && wr_if.valid_data) got_wresp <= {wr_if.data != `OKAY,1'b1}; 
            if (dac_check[0]) dac_check <= 0; 

            if (test_num == 4) begin
                if (test_check[0]) begin
                    if (test_check[1]) begin 
                        testsPassed <= testsPassed + 1;
                        if (VERBOSE) $write("%c[1;32m",27); 
                        if (VERBOSE) $write("t%0d_%0d+ ",test_num,expected_out);
                        if (VERBOSE) $write("%c[0m",27); 
                    end else begin 
                        testsFailed <= testsFailed + 1; 
                        if (VERBOSE) $write("%c[1;31m",27); 
                        if (VERBOSE) $write("t%0d_%0d- ",test_num,expected_out);
                        if (VERBOSE) $write("%c[0m",27); 
                    end 
                end 
            end else if (test_num == 8) begin
                if (test_check[0]) begin
                    if (test_check[1]) begin 
                        testsPassed <= testsPassed + 1;
                        if (VERBOSE) $write("%c[1;32m",27); 
                        if (VERBOSE) $write("t%0d_%0d+ ",test_num,timer/2);
                        if (VERBOSE) $write("%c[0m",27); 
                    end else begin 
                        testsFailed <= testsFailed + 1; 
                        if (VERBOSE) $write("%c[1;31m",27); 
                        if (VERBOSE) $write("t%0d_%0d- ",test_num,timer/2);
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
                    end else begin 
                        testsFailed <= testsFailed + 1; 
                        if (VERBOSE) $write("%c[1;31m",27); 
                        if (VERBOSE) $write("t%0d- ",test_num,);
                        if (VERBOSE) $write("%c[0m",27); 
                    end 
                    if (test_num == 3) $write("\n\n");
                end 
            end 
        end
    end

    logic[1:0] testNum_edge, new_sample_edge;
    enum logic {WATCH, PANIC} panicState;
    logic go; 
    logic[$clog2(TIMEOUT):0] timeout_cntr; 
    edetect testNum_edetect(.clk(clk), .rst(rst),
                            .val(test_num),
                            .comb_posedge_out(testNum_edge)); 
    edetect sample_edetect(.clk(clk), .rst(rst),
                            .val(sys.dac_sample_pulled),
                            .comb_posedge_out(new_sample_edge)); 

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
                            if (testNum_edge == 1 || new_sample_edge == 1) timeout_cntr <= 0;
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
        if (VERBOSE) $display("\n############ Starting Full System Test ############");
        #100;
        while (testState != DONE && timeout_cntr < TIMEOUT) #10;
        if (timeout_cntr < TIMEOUT) begin
            if (testsFailed != 0) begin 
                if (VERBOSE) $write("%c[1;31m",27); 
                if (VERBOSE) $display("\nFull System Tests Failed :((\n");
                if (VERBOSE) $write("%c[0m",27);
            end else begin 
                if (VERBOSE) $write("%c[1;32m",27); 
                if (VERBOSE) $display("\nFull System Tests Passed :))\n");
                if (VERBOSE) $write("%c[0m",27); 
            end
            #100;
        end else begin
            $write("%c[1;31m",27); 
            $display("\nFull System Tests Timed out on test %d!\n", test_num);
            $write("%c[0m",27);
            #100; 
        end
    end 

endmodule 

`default_nettype wire
