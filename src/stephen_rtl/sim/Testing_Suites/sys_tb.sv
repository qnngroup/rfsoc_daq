`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module sys_tb #(parameter VERBOSE = 1)(input wire start, output logic[1:0] done);
    localparam TOTAL_TESTS = 13; 
    localparam STARTING_TEST = 0; 
    localparam TIMEOUT = 10_000; 
    localparam SKIP_TRIVIAL_TESTS = 1;
    logic clk, rst;

    enum logic[2:0] {IDLE, TEST, MEM_TEST_CHECK, WRESP, CHECK, DONE} testState; 
    logic[1:0] test_check; // test_check[0] = check, test_check[1] == 1 => test passed else test failed 
    logic[7:0] test_num; 
    logic[7:0] testsPassed, testsFailed, correct_steps; 
    logic[1:0] correct_edge;
    logic kill_tb; 
    logic panic = 0; 
    logic[15:0] timer, counter;
    logic[1:0] mt_timer; 

    logic[1:0] got_wresp;  //[1] == error bit (wr_if.data wasn't okay when recieved), [0] == sys saw a wr_if.data 
    logic[`BATCH_WIDTH-1:0] dac_batch;
    logic valid_dac_batch;
    logic dac0_rdy;
    logic pl_rstn;
    logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] dac_samples, first_batch, rs_init_batch, trig_init_batch;
    logic seen_first_batch; 
    logic[`BATCH_SAMPLES-1:0] test_check_vector; 
    logic[1:0] dac_check, valid_dac_edge, produce_rs_edge, produce_trig_edge, produce_pwl_edge; 
    logic[`CHAN_SAMPLES-1:0][`WD_DATA_WIDTH-1:0] exp_cmc_data; 
    logic[`SDC_SAMPLES-1:0][`WD_DATA_WIDTH-1:0] exp_sdc_data; 
    logic[`BUFF_SAMPLES-1:0][`WD_DATA_WIDTH-1:0] bufft_reg; 
    logic[`WD_DATA_WIDTH-1:0] rand_val; 

    Recieve_Transmit_IF #(`A_BUS_WIDTH, `A_DATA_WIDTH)   wa_if (); 
    Recieve_Transmit_IF #(`WD_BUS_WIDTH, `WD_DATA_WIDTH) wd_if (); 
    Recieve_Transmit_IF #(`A_BUS_WIDTH, `A_DATA_WIDTH)   ra_if (); 
    Recieve_Transmit_IF #(`WD_BUS_WIDTH, `WD_DATA_WIDTH) rd_if (); 
    Recieve_Transmit_IF #(2,2) wr_if (); 
    Recieve_Transmit_IF #(2,2) rr_if ();

    Axis_IF #(`DMA_DATA_WIDTH) pwl_dma_if(); 
    Axis_IF #(`BUFF_TIMESTAMP_WIDTH) bufft_if(); 
    Axis_IF #(`BUFF_CONFIG_WIDTH) buffc_if();
    Axis_IF #(`CHANNEL_MUX_WIDTH) cmc_if();
    Axis_IF #(`SDC_DATA_WIDTH) sdc_if();

    assign wa_if.dev_rdy = 1;
    assign wd_if.dev_rdy = 1;
    assign ra_if.dev_rdy = 1;
    assign rr_if.dev_rdy = 1;
    assign {rr_if.data_to_send, rr_if.data, rr_if.send, rr_if.trans_rdy} = 0;
    assign {pwl_dma_if.data, pwl_dma_if.last, pwl_dma_if.valid} = 0;

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
             .pwl_dma_if(pwl_dma_if),
             .bufft_if(bufft_if),
             .buffc_if(buffc_if),
             .cmc_if(cmc_if),
             .sdc_if(sdc_if)); 

    oscillate_sig #(.DELAY (10))
    dac_rdy_oscillator(.clk(clk), .rst(rst), .long_on(1'b1),
                       .osc_sig_out(dac0_rdy));
    oscillate_sig #(.DELAY (25))
    read_rdy_oscillator(.clk(clk), .rst(rst), .long_on(1'b1),
                        .osc_sig_out(rd_if.dev_rdy));
    oscillate_sig #(.DELAY (30))
    wresp_rdy_oscillator(.clk(clk), .rst(rst), .long_on(1'b1),
                        .osc_sig_out(wr_if.dev_rdy));
    LFSR #(.DATA_WIDTH (`WD_DATA_WIDTH))
    rand_num_gen(.clk(clk), .rst(rst),
                 .seed((`WD_DATA_WIDTH)'(-1)),
                 .run(testState != IDLE),
                 .sample_out(rand_val));

    always_comb begin
        for (int i = 0; i < `BATCH_SAMPLES; i++) begin 
            dac_samples[i] = dac_batch[`SAMPLE_WIDTH*i+:`SAMPLE_WIDTH];
            rs_init_batch[i] = 16'hBEEF + i;
            trig_init_batch[i] = i; 
        end 
        for (int i = 0; i < `CHAN_SAMPLES; i++) exp_cmc_data[i] = i+69;
        for (int i = 0; i < `SDC_SAMPLES; i++) exp_sdc_data[i] = i;
        bufft_if.last = bufft_if.valid;
    end

  
    edetect valid_dac_edetect(.clk(clk), .rst(rst),
                              .val(valid_dac_batch),
                              .comb_posedge_out(valid_dac_edge));
    edetect valid_rs_edetect(.clk(clk), .rst(rst),
                              .val(sys.dac_intf.produce_rand_samples),
                              .comb_posedge_out(produce_rs_edge));
    edetect valid_trig_edetect(.clk(clk), .rst(rst),
                              .val(sys.dac_intf.produce_trig_wave),
                              .comb_posedge_out(produce_trig_edge));
    edetect valid_pwl_edetect(.clk(clk), .rst(rst),
                              .val(sys.dac_intf.produce_pwl),
                              .comb_posedge_out(produce_pwl_edge));
    edetect #(.DATA_WIDTH(8))
    correct_ed(.clk(clk), .rst(rst),
               .val(correct_steps),
               .comb_posedge_out(correct_edge));                              

    always_comb begin
        if (test_num != 2) test_check_vector = 0; 

        if (test_num == 0) 
            test_check = {sys.rst, sys.rst}; 
        else if (test_num == 1)  
            test_check = dac_check;
        else if (test_num == 2) begin 
            if (valid_dac_batch && testState == TEST) begin
                for (int i = 1; i < `BATCH_SAMPLES; i++) test_check_vector[i] = dac_samples[i] == dac_samples[i-1]+1; 
                test_check_vector[0] = 1; 
                test_check = {&test_check_vector, 1'b1};
            end else {test_check,test_check_vector} = 0; 
        end 
        else if (test_num == 3)  
            test_check = (~valid_dac_batch && dac0_rdy && testState == TEST)? {1'b1, 1'b1} : 0;
        else if (test_num == 4)  
            test_check = (testState == CHECK)? {counter == 651,1'b1} : 0;
        else if (test_num == 5)  
            test_check = (rd_if.valid_data)? {rd_if.data == `MAX_DAC_BURST_SIZE, 1'b1} : 0;
        else if (test_num == 6)  
            test_check = (testState == CHECK)? {1'b1, 1'b1} : 0;
        else if (test_num == 7)  
            test_check = (testState == CHECK)? {1'b1, 1'b1} : 0;
        else if (test_num == 8)
            test_check = (correct_edge != 0)? {correct_edge == 1, 1'b1} : 0;
        else if (test_num == 9) 
            test_check = (correct_edge != 0)? {correct_edge == 1, 1'b1} : 0;
        else if (test_num == 10) 
            test_check = (testState == CHECK)? {bufft_reg == 32'hBEEF_BEAD, 1'b1} : 0; 
        else if (test_num == 11) 
            test_check = (rd_if.valid_data)? {rd_if.data  == `FIRMWARE_VERSION, 1'b1} : 0; 
        else if (test_num == 12) 
            test_check = (correct_edge != 0 && testState == MEM_TEST_CHECK)? {correct_edge == 1, 1'b1} : 0; 
        else test_check = 0; 
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
                {done, timer, counter, mt_timer,correct_steps} <= 0;
                test_num <= STARTING_TEST; 

                {wa_if.data_to_send, wd_if.data_to_send, ra_if.data_to_send} <= 0;
                {wa_if.send, wd_if.send, ra_if.send} <= 0;
                {dac_check,first_batch,seen_first_batch} <= 0;
                {buffc_if.ready, cmc_if.ready, sdc_if.ready} <= 0;
                {bufft_if.data, bufft_if.valid, bufft_reg} <= 0;
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
                            wd_if.data_to_send <= (`PS_SEED_BASE_ADDR + 4*timer == `PS_SEED_VALID_ADDR)? 1 : rs_init_batch[timer]; 
                            {wa_if.send, wd_if.send} <= 3;
                            timer <= timer + 1;
                            testState <= WRESP;
                        end else if (seen_first_batch || $signed(timer) == -1) begin
                            if ($signed(timer) == -1) begin
                                dac_check[0] <= 1;
                                seen_first_batch <= 0;  
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
                    // Send a burst of 651 batches from the dac, make sure as many batches come out. 
                    if (test_num == 4) begin  
                        if (timer == 0) begin
                            wa_if.data_to_send <= `DAC_BURST_SIZE_ADDR;
                            wd_if.data_to_send <= 651; 
                            {wa_if.send, wd_if.send} <= 3;
                            timer <= 1;
                            testState <= WRESP;
                        end
                        if (timer == 1) begin
                            wa_if.data_to_send <= `TRIG_WAVE_ADDR;
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            timer <= 2;
                            counter <= 0;
                            testState <= WRESP;
                        end
                        if (timer == 2 && valid_dac_batch) timer <= 3;
                        if (timer == 3) begin
                            if (~sys.dac_intf.produce_trig_wave) begin
                                timer <= 0;
                                testState <= CHECK;
                            end 
                        end
                    end
                    // Read the max burst size from the sys 
                    if (test_num == 5) begin
                        if (timer == 0) begin   
                            ra_if.data_to_send <= `MAX_DAC_BURST_SIZE_ADDR; 
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
                            wa_if.data_to_send <= `DAC_BURST_SIZE_ADDR;
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
                            {timer,correct_steps} <= 0;
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
                        if (timer == 0) begin
                            wa_if.data_to_send <= `PS_SEED_VALID_ADDR;
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            seen_first_batch <= 0;
                            timer <= 1;
                            testState <= WRESP; 
                        end
                        if (timer == 1) begin
                            if (seen_first_batch) begin
                                correct_steps <= (sys.dac_intf.produce_rand_samples && first_batch == rs_init_batch)? correct_steps + 1 : correct_steps - 1;
                                wa_if.data_to_send <= `TRIG_WAVE_ADDR;
                                wd_if.data_to_send <= 1; 
                                {wa_if.send, wd_if.send} <= 3;
                                timer <= 2;
                                seen_first_batch <= 0; 
                                testState <= WRESP;
                            end
                        end
                        if (timer == 2) begin
                            if (seen_first_batch) begin
                                correct_steps <= (sys.dac_intf.produce_trig_wave && first_batch == trig_init_batch)? correct_steps + 1 : correct_steps - 1;
                                wa_if.data_to_send <= `RUN_PWL_ADDR;
                                wd_if.data_to_send <= 1; 
                                {wa_if.send, wd_if.send} <= 3;
                                timer <= 3;
                                seen_first_batch <= 0;
                                testState <= WRESP;
                            end
                        end
                        if (timer == 3) begin
                            if (seen_first_batch) begin
                                correct_steps <= (sys.dac_intf.produce_pwl && (first_batch != rs_init_batch) && (first_batch != trig_init_batch))? correct_steps + 1 : correct_steps - 1;
                                wa_if.data_to_send <= `DAC_HLT_ADDR;
                                wd_if.data_to_send <= 1; 
                                {wa_if.send, wd_if.send} <= 3;
                                timer <= 4;
                                seen_first_batch <= 0;
                                testState <= WRESP;
                            end
                        end
                        if (timer == 4) begin
                            timer <= 0; 
                            testState <= CHECK; 
                        end
                    end   
                    // Write to all ADC addresses, and ensure the correct quantities are recorded. 
                    if (test_num == 9) begin
                        if (sdc_if.valid && sdc_if.ready)          correct_steps <= (sdc_if.data == exp_sdc_data)? correct_steps + 1 : correct_steps - 1; 
                        else if (cmc_if.valid && cmc_if.ready)     correct_steps <= (cmc_if.data == exp_cmc_data)? correct_steps + 1 : correct_steps - 1; 
                        else if (buffc_if.valid && buffc_if.ready) correct_steps <= (buffc_if.data == 4'hA)? correct_steps + 1 : correct_steps - 1; 

                        if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+59) begin
                            timer <= 0;
                            testState <= CHECK;
                        end else timer <= timer + 1; 

                        if (timer >= 0 && timer < `SDC_SAMPLES) begin
                            wa_if.data_to_send <= `SDC_BASE_ADDR+(timer<<2); 
                            wd_if.data_to_send <= timer; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end 
                        if (timer == `SDC_SAMPLES) begin
                            wa_if.data_to_send <= `SDC_VALID_ADDR; 
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer > `SDC_SAMPLES && timer <= `SDC_SAMPLES+`CHAN_SAMPLES) begin
                            wa_if.data_to_send <= `CHAN_MUX_BASE_ADDR+((timer-`SDC_SAMPLES-1)<<2); 
                            wd_if.data_to_send <= (timer-`SDC_SAMPLES-1)+69; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end
                        if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+1) begin
                            wa_if.data_to_send <= `CHAN_MUX_VALID_ADDR; 
                            wd_if.data_to_send <= 1; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end 
                        if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+3) begin
                            wa_if.data_to_send <= `BUFF_CONFIG_ADDR; 
                            wd_if.data_to_send <= 4'hA; 
                            {wa_if.send, wd_if.send} <= 3;
                            testState <= WRESP;
                        end 
                        if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+40) begin
                            correct_steps <= (buffc_if.valid && cmc_if.valid && sdc_if.valid)? correct_steps + 1 : correct_steps - 1;
                        end 
                        if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+50) buffc_if.ready <= 1;
                        if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+52) correct_steps <= (~buffc_if.valid)? correct_steps + 1 : correct_steps - 1;                                              
                        if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+53) cmc_if.ready <= 1;  
                        if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+55) correct_steps <= (~cmc_if.valid)? correct_steps + 1 : correct_steps - 1;                    
                        if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+56) sdc_if.ready <= 1;  
                        if (timer == `SDC_SAMPLES+`CHAN_SAMPLES+58) correct_steps <= (~sdc_if.valid)? correct_steps + 1 : correct_steps - 1;                    
                    end 
                    // Simulate an external module writing to the timestamp buffer
                    if (test_num == 10) begin
                        if (timer == 0) begin 
                            bufft_if.data <= 32'hBEEF_BEAD; 
                            bufft_if.valid <= 1; 
                            ra_if.data_to_send <= `BUFF_TIME_VALID_ADDR;
                            ra_if.send <= 1; 
                            timer <= 1; 
                        end 
                        if (rd_if.valid_data) begin
                            if (timer == 1 && rd_if.data == 1) begin 
                                ra_if.data_to_send <= `BUFF_TIME_BASE_ADDR;
                                ra_if.send <= 1; 
                                timer <= 2;
                            end else begin
                                ra_if.data_to_send <= `BUFF_TIME_VALID_ADDR;
                                ra_if.send <= 1; 
                            end
                            if (timer == 2) begin 
                                bufft_reg[0] <= rd_if.data; 
                                ra_if.data_to_send <= `BUFF_TIME_BASE_ADDR + 4;
                                ra_if.send <= 1; 
                                timer <= 3;
                            end 
                            if (timer == 3) begin 
                                bufft_reg[1] <= rd_if.data; 
                                timer <= 0; 
                                testState <= CHECK;
                            end 
                        end
                    end 
                    // Confirm the firmware number is correct 
                    if (test_num == 11) begin
                        if (timer == 0) begin
                            ra_if.data_to_send <= `VERSION_ADDR; 
                            ra_if.send <= 1; 
                        end
                        if (rd_if.valid_data) begin
                            testState <= CHECK;
                            timer <= 0;
                            {correct_steps,mt_timer} <= 0;
                        end else timer <= timer + 1; 
                    end 
                    // Run simple memory test
                    if (test_num == 12) begin
                        if (timer == 50) begin
                            timer <= 0;
                            testState <= CHECK;
                        end else timer <= timer + 1; 

                        if (timer < 50) begin
                            wa_if.data_to_send <= `MEM_TEST_BASE_ADDR+(timer<<2); 
                            wd_if.data_to_send <= rand_val;
                            {wa_if.send, wd_if.send} <= 3; 
                            testState <= MEM_TEST_CHECK;
                        end
                    end          
                end 
                MEM_TEST_CHECK: begin
                    if (mt_timer == 0) begin
                        if (wr_if.valid_data && wr_if.data == `OKAY) begin
                            ra_if.data_to_send <= wa_if.data_to_send; 
                            ra_if.send <= 1; 
                            mt_timer <= 1; 
                        end 
                    end
                    if (mt_timer == 1) begin
                        if (rd_if.valid_data) begin
                            correct_steps <= (rd_if.data  == wd_if.data_to_send - 10)? correct_steps + 1 : correct_steps - 1; 
                            ra_if.data_to_send <= wa_if.data_to_send+4; 
                            ra_if.send <= 1;
                            mt_timer <= 2; 
                        end 
                    end 
                    if (mt_timer == 2) begin
                        if (rd_if.valid_data) begin
                            correct_steps <= (rd_if.data  == wd_if.data_to_send + 10)? correct_steps + 1 : correct_steps - 1; 
                            mt_timer <= 0;
                            testState <= TEST; 
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
                    end else test_num <= test_num + 1;
                    testState <= (test_num < TOTAL_TESTS-1)? TEST : DONE; 
                end 

                DONE: begin 
                    done <= {testsFailed == 0 && ~kill_tb,1'b1}; 
                    testState <= IDLE; 
                    test_num <= 0; 
                end 
            endcase

            if (test_num == 1 && valid_dac_edge == 1 && ~seen_first_batch) begin
                dac_check[1] <= (dac_batch == rs_init_batch); 
                seen_first_batch <= 1; 
            end 
            if (test_num == 8 && ~seen_first_batch) begin
                if (timer == 1 && valid_dac_edge == 1) begin
                    first_batch <= dac_samples; 
                    seen_first_batch <= 1; 
                end
                if (timer == 2 && produce_trig_edge == 1) begin
                    first_batch <= dac_samples; 
                    seen_first_batch <= 1; 
                end
                if (timer == 3 && produce_pwl_edge == 1) begin
                    first_batch <= dac_samples; 
                    seen_first_batch <= 1; 
                end
            end
            if (sdc_if.ready) sdc_if.ready <= 0; 
            if (cmc_if.ready) cmc_if.ready <= 0; 
            if (buffc_if.ready) buffc_if.ready <= 0; 
            if (bufft_if.valid) bufft_if.valid <= 0; 
            if (wa_if.send) wa_if.send <= 0; 
            if (wd_if.send) wd_if.send <= 0; 
            if (ra_if.send) ra_if.send <= 0; 
            if (testState != WRESP && wr_if.valid_data) got_wresp <= {wr_if.data != `OKAY,1'b1}; 
            if (dac_check[0]) dac_check <= 0; 
            if (valid_dac_batch) counter <= counter + 1;

            if (test_num == 9 || test_num == 12 || test_num == 8) begin
                if (test_check[0]) begin
                    if (test_check[1]) begin 
                        testsPassed <= testsPassed + 1;
                        if (VERBOSE) $write("%c[1;32m",27); 
                        if (VERBOSE) $write("t%0d_%0d+ ",test_num,correct_steps);
                        if (VERBOSE) $write("%c[0m",27); 
                    end else begin 
                        testsFailed <= testsFailed + 1; 
                        if (VERBOSE) $write("%c[1;31m",27); 
                        if (VERBOSE) $write("t%0d_%0d- ",test_num,correct_steps);
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
                end 
            end 
        end
    end

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
