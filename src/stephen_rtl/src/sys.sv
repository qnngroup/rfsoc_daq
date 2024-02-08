`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module sys(input wire clk,sys_rst,
                 //DAC Inputs/Outputs
                 input wire dac0_rdy,
                 output logic[`BATCH_WIDTH-1:0] dac_batch, 
                 output logic valid_dac_batch, 
                 output logic pl_rstn, 
                 //PS Inputs/Outputs 
                 Recieve_Transmit_IF wa_if,
                 Recieve_Transmit_IF wd_if,
                 Recieve_Transmit_IF ra_if,
                 Recieve_Transmit_IF rd_if,
                 Recieve_Transmit_IF wr_if,
                 Recieve_Transmit_IF rr_if,
                 Axis_IF pwl_dma_if, //PWL DMA axi-stream
                 Axis_IF bufft_if,   //Buffer Timestamp axi-stream
                 Axis_IF buffc_if,   //Buffer Config axi-stream
                 Axis_IF cmc_if,     //Channel Mux Config axi-stream
                 Axis_IF sdc_if);    //Sample Discriminator Config axi-stream

    logic [`MEM_SIZE-1:0] fresh_bits,rtl_read_reqs,rtl_write_reqs, rtl_rdy;
    logic[`MEM_SIZE-1:0][`WD_DATA_WIDTH-1:0] rtl_wd_in, rtl_rd_out;
    logic[$clog2(`MAX_DAC_BURST_SIZE):0] dac_burst_size; 
    logic rst_cmd = 1;
    logic rst,hlt_cmd, bufft_valid_clear;
    logic[`BATCH_WIDTH-1:0] dac_batch_unfiltered;
    logic[$clog2(`SAMPLE_WIDTH):0] scale_factor; 
    logic [`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] dac_samples_scaled; 
    logic[$clog2(`MAX_DAC_BURST_SIZE)+1:0] hlt_counter; 

    enum logic[1:0] {IDLE_R, RESP_WAIT, RESET} rstState; 
    enum logic {IDLE_DB, CHANGE_BURST_SIZE} dacBurstState;
    enum logic {IDLE_S, CHANGE_SCALE} scaleParamState;
    enum logic {IDLE_H, HALT_DAC} hltState;
    enum logic {IDLE_B, BUFFT_POLL_WAIT} bufftState;
    assign rst = sys_rst || rst_cmd;
    assign pl_rstn = ~rst; 
    assign dac_batch = dac_samples_scaled;  
    always_comb begin
        for (int i = 0; i < `BATCH_SAMPLES; i++) begin
            dac_samples_scaled[i] = dac_batch_unfiltered[`SAMPLE_WIDTH*i+:`SAMPLE_WIDTH] >> scale_factor;
        end 
    end

    // Maps which parts of the system are responssible for writing to which parts of the memory map
    always_comb begin
        for (int i=0; i<`MAPPED_ID_CEILING; i++) begin
            case(i)
                `RST_ID:            rtl_rdy[i] = rstState == IDLE_R; 
                `DAC_HLT_ID:        rtl_rdy[i] = hltState == IDLE_H; 
                `DAC_BURST_SIZE_ID: rtl_rdy[i] = dacBurstState == IDLE_DB; 
                `SCALE_DAC_OUT_ID:  rtl_rdy[i] = scaleParamState == IDLE_S; 
                `TRIG_WAVE_ID:      rtl_rdy[i] = dac_intf.state_rdy;
                `PWL_PREP_ID:       rtl_rdy[i] = dac_intf.state_rdy;
                `RUN_PWL_ID:        rtl_rdy[i] = dac_intf.state_rdy;
                `BUFF_CONFIG_ID:    rtl_rdy[i] = adc_intf.state_rdy; 
                default: begin
                    if (i inside {[`PS_SEED_BASE_ID:`PS_SEED_VALID_ID]}) rtl_rdy[i] = dac_intf.state_rdy;
                    else if (i inside {[`CHAN_MUX_BASE_ID:`SDC_VALID_ID]}) rtl_rdy[i] = adc_intf.state_rdy; 
                    else rtl_rdy[i] = 1; 
                end 
            endcase 
            if ((`is_RTLPOLL(i)) || (`is_READONLY(i))) {rtl_read_reqs[i], rtl_write_reqs[i], rtl_wd_in[i]} = 0; //If rtl polls, no writing or reading. If it's readonly, just use the package definition
            else if (i >= `BUFF_TIME_BASE_ID && i <= `BUFF_TIME_VALID_ID) begin
                rtl_read_reqs[i] = 0; 
                if (bufft_valid_clear) begin
                    if (i == `BUFF_TIME_VALID_ID) {rtl_write_reqs[i], rtl_wd_in[i]} = {1'b1, 1'b0}; 
                    else {rtl_write_reqs[i], rtl_wd_in[i]} = 0;
                end else begin
                    rtl_write_reqs[i] = adc_intf.buff_timestamp_writereq; 
                    if (i == `BUFF_TIME_VALID_ID) rtl_wd_in[i] = 1; 
                    else rtl_wd_in[i] = adc_intf.buff_timestamp_reg[(i-`BUFF_TIME_BASE_ID)]; 
                end 
            end
            else {rtl_read_reqs[i], rtl_write_reqs[i], rtl_wd_in[i]} = 0;
        end
        rtl_rdy[`MAPPED_ID_CEILING+:(`MEM_SIZE-`MAPPED_ID_CEILING)] = -1;
        rtl_read_reqs[`MAPPED_ID_CEILING+:(`MEM_SIZE-`MAPPED_ID_CEILING)] = 0;
        rtl_write_reqs[`MAPPED_ID_CEILING+:(`MEM_SIZE-`MAPPED_ID_CEILING)] = 0;
        rtl_wd_in[`MAPPED_ID_CEILING+:(`MEM_SIZE-`MAPPED_ID_CEILING)] = 0;
    end

    // Overall system state machine (for resets, halts, parameter changes)
    always_ff @(posedge clk) begin
        if (rst) begin
            {rst_cmd,hlt_cmd,hlt_counter} <= 0;
            {dac_burst_size,scale_factor,bufft_valid_clear} <= 0; 
            rstState <= IDLE_R;
            dacBurstState <= IDLE_DB; 
            scaleParamState <= IDLE_S; 
            hltState <= IDLE_H; 
            bufftState <= IDLE_B; 
        end 
        else begin
            if (valid_dac_batch && dac_burst_size != 0) begin
                if ( (hlt_counter+1) < dac_burst_size) hlt_counter <= hlt_counter + 1; 
                else hlt_counter <= 0; 
            end 

            case (rstState) 
                IDLE_R: begin
                    if (fresh_bits[`RST_ID]) rstState <= RESP_WAIT; 
                end 
                RESP_WAIT: begin 
                    if (wr_if.got_pack) rstState <= RESET; 
                end 
                RESET: begin
                    rst_cmd <= 1; 
                    rstState <= IDLE_R;
                end 
            endcase 

            case(hltState)
                IDLE_H: begin
                    if (fresh_bits[`DAC_HLT_ID] || ( valid_dac_batch && dac_burst_size != 0 && hlt_counter == (dac_burst_size-1) )) begin 
                        hlt_cmd <= 1;
                        hltState <= HALT_DAC; 
                    end 
                end 
                HALT_DAC: begin
                    hlt_cmd <= 0; 
                    hltState <= IDLE_H; 
                end 
            endcase 

            case(scaleParamState)
                IDLE_S: begin
                    if (fresh_bits[`SCALE_DAC_OUT_ID]) scaleParamState <= CHANGE_SCALE;
                end 

                CHANGE_SCALE: begin
                    scale_factor <= rtl_rd_out[`SCALE_DAC_OUT_ID];
                    scaleParamState <= IDLE_S; 
                end 
            endcase 

            case(dacBurstState)
                IDLE_DB: begin 
                    if (fresh_bits[`DAC_BURST_SIZE_ID]) dacBurstState <= CHANGE_BURST_SIZE; 
                end 
                CHANGE_BURST_SIZE: begin
                    dac_burst_size <= rtl_rd_out[`DAC_BURST_SIZE_ID]; 
                    dacBurstState <= IDLE_DB; 
                end 
            endcase 

            case(bufftState)
                IDLE_B: begin
                    if (fresh_bits[`BUFF_TIME_VALID_ID]) begin  // External module just wrote to the bufft register, wait for the processor to pull it if ever. 
                        bufftState <= BUFFT_POLL_WAIT; 
                    end
                end 
                BUFFT_POLL_WAIT: begin
                    if (~fresh_bits[`BUFF_TIME_VALID_ID]) begin // processor is about to pull bufft reg, clear the valid addr
                        bufft_valid_clear <= 1; 
                        bufftState <= IDLE_B; 
                    end 
                end 
            endcase 

            if (bufft_valid_clear) bufft_valid_clear <= 0; 
        end
    end

    axi_slave #(.A_BUS_WIDTH(`A_BUS_WIDTH), .A_DATA_WIDTH(`A_DATA_WIDTH), .WD_BUS_WIDTH(`WD_BUS_WIDTH), .WD_DATA_WIDTH(`WD_DATA_WIDTH))
    slave(.clk(clk), .rst(rst),
          .waddr_if(wa_if),
          .wdata_if(wd_if),
          .raddr_if(ra_if),
          .rdata_if(rd_if),
          .wresp_if(wr_if),
          .rresp_if(rr_if),
          .rtl_write_reqs(rtl_write_reqs), .rtl_read_reqs(rtl_read_reqs),
          .clr_rd_out(1'b0),
          .rtl_rdy(rtl_rdy), 
          .rtl_wd_in(rtl_wd_in),               //in
          .rtl_rd_out(rtl_rd_out),             //out 
          .fresh_bits(fresh_bits));


    DAC_Interface dac_intf(.clk(clk),.rst(rst),
                          .fresh_bits(fresh_bits),
                          .read_resps(rtl_rd_out),
                          .dac0_rdy(dac0_rdy), 
                          .halt(hlt_cmd),                   //in
                          .dac_batch(dac_batch_unfiltered), //out 
                          .valid_dac_batch(valid_dac_batch),
                          .pwl_dma_if(pwl_dma_if));

    ADC_Interface adc_intf(.clk(clk), .rst(rst),
                           .fresh_bits(fresh_bits),
                           .read_resps(rtl_rd_out),
                           .bufft(bufft_if.stream_in),
                           .buffc(buffc_if.stream_out),
                           .cmc(cmc_if.stream_out),
                           .sdc(sdc_if.stream_out));
endmodule 

`default_nettype wire

/*
TODO:
1. Idk what MAX_BURST_SIZE_ID corresponds to, figure it out or remove it (DONE)
2. Idk why the dac_ila has a full vector of write requests when it only needs two: one for placing a sample and one for letting the PS know a sample was placed. Fix that (DONE)
3. 
*/