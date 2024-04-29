`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module top_level_tb #(parameter VERBOSE = 1)(input wire start, output logic[1:0] done);
    localparam TOTAL_TESTS = 4; 
    localparam STARTING_TEST = 0;
    localparam SKIP_PWL_TEST = 0; 
    localparam TIMEOUT = 10_000; 
    localparam PERIODS_TO_CHECK = 3; 
    localparam BUFF_LEN = 67;
    logic clk, rst;
    logic[15:0] timer, correct_steps;
    logic test_start;  
    logic[1:0] correct_edge;

    enum logic[2:0] {IDLE, TEST,READ_DATA, WRESP, CHECK, DONE} testState; 
    logic[1:0] test_check; // test_check[0] = check, test_check[1] == 1 => test passed else test failed 
    logic[7:0] test_num; 
    logic[7:0] testsPassed, testsFailed; 
    logic kill_tb; 
    logic panic = 0; 

    logic[`A_BUS_WIDTH-1:0] raddr_packet, waddr_packet, mem_test_addr;
    logic[`WD_BUS_WIDTH-1:0] rdata_packet, wdata_packet, mem_test_data;
    logic[`WD_DATA_WIDTH-1:0] read_data; 
    logic[`DMA_DATA_WIDTH-1:0] pwl_tdata;
    logic[3:0] pwl_tkeep;
    logic pwl_tlast, pwl_tready, pwl_tvalid; 
    logic raddr_valid_packet, waddr_valid_packet, wdata_valid_packet, rdata_valid_out, wresp_valid_out, rresp_valid_out;
    logic ps_wresp_rdy,ps_read_rdy; 
    logic[1:0] wresp_out, rresp_out; 
    logic[(`BATCH_WIDTH)-1:0] dac_batch;
    logic valid_dac_batch, dac0_rdy;
    logic pl_rstn;
    logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] init_samples, dac_samples;

    enum logic[1:0] {IDLE_PWL, SEND_BUFF,VERIFY} pwlTestState; 
    logic[$clog2(BUFF_LEN):0] dma_i;
    logic[$clog2(`SPARSE_BRAM_DEPTH):0] exp_i;
    logic send_dma_buff,run_pwl; 
    logic checked_full_wave;
    logic[$clog2(PERIODS_TO_CHECK):0] periods; 
    logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] curr_expected_batch;
    logic[`BATCH_SAMPLES-1:0] error_vec;

    edetect #(.DATA_WIDTH(16))
    correct_ed(.clk(clk), .rst(rst),
               .val(correct_steps),
               .comb_posedge_out(correct_edge));

    
    top_level tl(.clk(clk),
                 .sys_rst(rst),
                 .dac0_rdy(dac0_rdy),
                 .dac_batch(dac_batch),
                 .valid_dac_batch(valid_dac_batch),
                 .pl_rstn(pl_rstn),
                 .raddr_packet(raddr_packet),
                 .raddr_valid_packet(raddr_valid_packet),
                 .waddr_packet(waddr_packet),
                 .waddr_valid_packet(waddr_valid_packet),
                 .wdata_packet(wdata_packet),
                 .wdata_valid_packet(wdata_valid_packet),
                 .ps_wresp_rdy(ps_wresp_rdy),
                 .ps_read_rdy(ps_read_rdy),
                 .wresp_out(wresp_out),
                 .rresp_out(rresp_out),
                 .wresp_valid_out(wresp_valid_out),
                 .rresp_valid_out(rresp_valid_out),
                 .rdata_packet(rdata_packet),
                 .rdata_valid_out(rdata_valid_out),
                 .pwl_tdata(pwl_tdata),
                 .pwl_tkeep(pwl_tkeep),
                 .pwl_tlast(pwl_tlast),
                 .pwl_tvalid(pwl_tvalid),
                 .pwl_tready(pwl_tready));

    oscillate_sig #(.DELAY (10))
    dac_rdy_oscillator(.clk(clk), .rst(rst), .long_on(1'b0),
                       .osc_sig_out(dac0_rdy));
    oscillate_sig #(.DELAY (25))
    read_rdy_oscillator(.clk(clk), .rst(rst), .long_on(1'b0),
                        .osc_sig_out(ps_read_rdy));
    oscillate_sig #(.DELAY (30))
    wresp_rdy_oscillator(.clk(clk), .rst(rst), .long_on(1'b0),
                        .osc_sig_out(ps_wresp_rdy));
    generate
        for (genvar i = 0; i < `BATCH_SAMPLES; i++) begin: batch_splices
            data_splicer #(.DATA_WIDTH(`BATCH_WIDTH), .SPLICE_WIDTH(`SAMPLE_WIDTH))
            dac_out_splice(.data(dac_batch),
                           .i(int'(i)),
                           .spliced_data(dac_samples[i]));
        end
    endgenerate

    assign pwl_tkeep = 0; 
    assign checked_full_wave = (pwlTestState == VERIFY) && (valid_dac_batch) && (exp_i == (tl.sys.dac_intf.pwl_gen.wave_lines_stored-1)); 
    assign curr_expected_batch = expected_batches[exp_i];
    always_comb begin
        if (test_num == 0) 
            test_check = {tl.sys.rst,tl.sys.rst};
        else if (test_num == 1)
            test_check = (rdata_valid_out && ps_read_rdy && testState == TEST)? {rdata_packet == `MAX_DAC_BURST_SIZE,1'b1} : 0; 
        else if (test_num == 2) begin
            if (valid_dac_batch) begin
                for (int i = 0; i < `BATCH_WIDTH; i++) error_vec[i] = dac_samples[i] != curr_expected_batch[i]; 
            end else error_vec = 0; 
            test_check = (valid_dac_batch)? {dac_batch == curr_expected_batch,1'b1} : 0; 
        end else if (test_num == 3)
            test_check = (correct_edge != 0 && ~test_start)? {correct_edge == 1, 1'b1} : 0;
        else {test_check, error_vec} = 0; 
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
                {done, timer, correct_steps, test_start} <= 0;
                test_num <= STARTING_TEST; 

                {raddr_packet, waddr_packet, wdata_packet, read_data, mem_test_addr,mem_test_data} <= 0;
                {raddr_valid_packet, waddr_valid_packet, wdata_valid_packet} <= 0; 
                {pwl_tlast, pwl_tdata, pwl_tvalid} <= 0;
                {dma_i,exp_i,send_dma_buff,run_pwl,periods} <= 0;
                pwlTestState <= IDLE_PWL; 
            end
        end else begin
            case(pwlTestState)
                IDLE_PWL: begin 
                    if (send_dma_buff) begin
                        pwl_tvalid <= 1; 
                        pwl_tdata = dma_buff[0];
                        pwl_tlast <= 0; 
                        dma_i <= 1; 
                        pwlTestState <= SEND_BUFF; 
                    end
                    if (run_pwl) begin
                        {pwl_tlast, pwl_tdata, pwl_tvalid,dma_i} <= 0;
                        {exp_i, periods} <= 0;
                        pwlTestState <= VERIFY;  
                    end
                end  
                SEND_BUFF: begin
                    if (dma_i < BUFF_LEN) begin
                        if (pwl_tready) begin
                            pwl_tdata = dma_buff[dma_i];
                            if (dma_i == BUFF_LEN-1) pwl_tlast <= 1; 
                            dma_i <= dma_i + 1;
                        end 
                    end
                    else if (dma_i == BUFF_LEN && pwl_tready) begin
                        {pwl_tlast, pwl_tdata, pwl_tvalid} <= 0;
                        dma_i <= 0;
                        pwlTestState <= VERIFY;  
                    end
                end 
                VERIFY: begin
                    if (periods == PERIODS_TO_CHECK) begin
                        {exp_i, periods} <= 0;
                        pwlTestState <= IDLE_PWL;
                    end else if (checked_full_wave) begin
                        periods <= periods + 1;
                        exp_i <= 0; 
                    end else if (valid_dac_batch) exp_i <= exp_i + 1; 
                end 
            endcase

            case(testState)
                IDLE: begin 
                    if (start) testState <= TEST; 
                    if (done) done <= 0; 
                end 
                TEST: begin
                    // Write to reset
                    if (test_num == 0) begin
                        if (timer == 0) begin
                            waddr_packet <= `RST_ADDR;
                            wdata_packet <= 1; 
                            {waddr_valid_packet, wdata_valid_packet} <= 3;
                            timer <= 1;
                        end else begin
                            if (tl.sys.rst) begin
                                timer <= 0;
                                testState <= CHECK;
                            end
                        end
                    end
                    // Read from MAX_DAC_BS address
                    if (test_num == 1) begin
                        if (timer == 0) begin
                            raddr_packet <= `MAX_DAC_BURST_SIZE_ADDR;
                            raddr_valid_packet <= 1; 
                            timer <= 1;
                        end else begin
                            if (rdata_valid_out && ps_read_rdy) begin
                                timer <= 0;
                                testState <= CHECK;
                            end
                        end
                    end
                    //Send long pwl wave 
                    if (test_num == 2) begin
                        if (timer < 7) timer <= timer + 1;
                        else begin
                            if (periods == PERIODS_TO_CHECK) begin
                                testState <= CHECK;
                                timer <= 0; 
                            end
                        end

                        if (timer == 0) begin
                            wdata_packet <= 1; 
                            {waddr_valid_packet, wdata_valid_packet} <= 3;
                            testState <= WRESP; 
                        end 
                        if (timer == 5) send_dma_buff <= 1;                        
                    end
                    // Perform Memory test 
                    if (test_num == 3) begin
                        if (timer == 0) begin
                            mem_test_addr <= `MEM_TEST_BASE_ADDR;
                            mem_test_data <= 20;
                            {correct_steps,test_start} <= 1; 
                            timer <= 1;
                        end   
                        if (timer == 1) begin
                            waddr_packet <= mem_test_addr;
                            wdata_packet <= mem_test_data; 
                            {waddr_valid_packet, wdata_valid_packet} <= 3;
                            testState <= WRESP;
                            timer <= 2; 
                        end 
                        if (timer == 2) begin
                            mem_test_addr <= mem_test_addr + 4; 
                            raddr_packet <= mem_test_addr;
                            raddr_valid_packet <= 1;
                            testState <= READ_DATA; 
                            timer <= 3;
                        end      
                        if (timer == 3) begin
                            correct_steps <= (read_data == mem_test_data - 10)? correct_steps + 1 : correct_steps - 1;
                            raddr_packet <= mem_test_addr;
                            raddr_valid_packet <= 1;
                            testState <= READ_DATA; 
                            timer <= 4;
                        end    
                        if (timer == 4) begin
                            correct_steps <= (read_data == mem_test_data + 10)? correct_steps + 1 : correct_steps - 1;
                            mem_test_data <= mem_test_data + 10;
                            timer <= (mem_test_addr == `MEM_TEST_END_ADDR-4)? 5 : 1; 
                        end          
                        if (timer == 5) begin
                            timer <= 0;
                            testState <= CHECK;
                        end
                    end
                end
                READ_DATA: begin
                    if (rdata_valid_out && ps_read_rdy) begin
                        read_data <= rdata_packet; 
                        testState <= TEST;
                    end
                end 
                WRESP: begin
                    if (wresp_valid_out && ps_wresp_rdy) begin
                        if (wresp_out != `OKAY) begin
                            kill_tb <= 1; 
                            testState <= DONE; 
                        end else testState <= TEST; 
                    end
                end 
                CHECK: begin
                    if (test_num == 1 && SKIP_PWL_TEST) begin
                        test_num <= 3;
                        $display("\nSkipping pwl test\n");
                    end else test_num <= test_num + 1;
                    testState <= (test_num < TOTAL_TESTS-1)? TEST : DONE; 
                end 

                DONE: begin 
                    done <= {testsFailed == 0 && ~kill_tb,1'b1}; 
                    testState <= IDLE; 
                    test_num <= 0; 
                end 
            endcase
            if (waddr_valid_packet) waddr_valid_packet <= 0; 
            if (wdata_valid_packet) wdata_valid_packet <= 0; 
            if (raddr_valid_packet) raddr_valid_packet <= 0; 
            if (test_start) test_start <= 0; 

            if (test_num == 2) begin
                if (test_check[0]) begin
                    if (test_check[1]) begin 
                        testsPassed <= testsPassed + 1;
                        if (VERBOSE) $write("%c[1;32m",27); 
                        if (VERBOSE) $write("t%0d_%0d+ ",test_num,exp_i);
                        if (VERBOSE) $write("%c[0m",27); 
                    end 
                    else begin 
                        testsFailed <= testsFailed + 1; 
                        if (VERBOSE) $write("%c[1;31m",27); 
                        if (VERBOSE) $write("t%0d_%0d- ",test_num,exp_i);
                        if (VERBOSE) $write("%c[0m",27); 
                    end 
                    if (VERBOSE && checked_full_wave) $write("\nChecked period #%0d\n",periods+1);
                end 
            end else if (test_num == 3) begin
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
                    if (VERBOSE && checked_full_wave) $write("\nChecked period #%0d\n",periods+1);
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

    logic[1:0] testNum_edge, new_sample_edge;
    logic go; 
    enum logic {WATCH, PANIC} panicState; 
    logic[$clog2(TIMEOUT):0] timeout_cntr; 
    edetect #(.DATA_WIDTH(16))
    testNum_edetect (.clk(clk), .rst(rst),
                     .val(test_num+exp_i+correct_steps),
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
        if (VERBOSE) $display("\n############ Starting Top Test ############");
        #100;
        while (testState != DONE && timeout_cntr < TIMEOUT) #10;
        if (timeout_cntr < TIMEOUT) begin
            if (testsFailed != 0) begin 
                if (VERBOSE) $write("%c[1;31m",27); 
                if (VERBOSE) $display("\nTop Tests Failed :((\n");
                if (VERBOSE) $write("%c[0m",27);
            end else begin 
                if (VERBOSE) $write("%c[1;32m",27); 
                if (VERBOSE) $display("\nTop Tests Passed :))\n");
                if (VERBOSE) $write("%c[0m",27); 
            end
            #100;
        end else begin
            $write("%c[1;31m",27); 
            $display("\nTop Tests Timed out on test %d!\n", test_num);
            $write("%c[0m",27);
            #100; 
        end
    end 

endmodule 

`default_nettype wire
