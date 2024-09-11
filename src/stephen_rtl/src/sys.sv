`timescale 1ns / 1ps
`default_nettype none

import axi_params_pkg::DATAW;
import mem_layout_pkg::*;
import daq_params_pkg::*;
`define memID_to_dacID(i, base, reg_width) ((i-(base))/(reg_width))
`define memID_to_dacRegID(i,base,reg_width) ((i-(base))%(reg_width))

module sys(input wire ps_clk,ps_rst,dac_clk,dac_rst,
           //DAC Inputs/Outputs
           input wire[DAC_NUM-1:0] dac_rdys,
           output logic[DAC_NUM-1:0][(BATCH_SIZE)-1:0][(SAMPLE_WIDTH)-1:0] dac_batches, 
           output logic[DAC_NUM-1:0] valid_dac_batches, 
           output logic pl_rstn, 
           //PS Inputs/Outputs 
           Recieve_Transmit_IF wa_if,
           Recieve_Transmit_IF wd_if,
           Recieve_Transmit_IF ra_if,
           Recieve_Transmit_IF rd_if,
           Recieve_Transmit_IF wr_if,
           Recieve_Transmit_IF rr_if,
           Axis_IF pwl_dmas_if, //PWL DMA axi-stream
           Axis_IF bufft_if,    //Buffer Timestamp axi-stream
           Axis_IF buffc_if,    //Buffer Config axi-stream
           Axis_IF cmc_if,      //Channel Mux Config axi-stream
           Axis_IF sdc_if);     //Sample Discriminator Config axi-stream

    localparam BS_WIDTH = $clog2(MAX_DAC_BURST_SIZE); 

    logic [MEM_SIZE-1:0] fresh_bits,rtl_read_reqs,rtl_write_reqs, rtl_rdy;
    logic[MEM_SIZE-1:0][DATAW-1:0] rtl_wd_in, rtl_rd_out;
    logic rst_cmd = 1;
    logic rst, bufft_valid_clear;
    logic[DAC_NUM-1:0][BS_WIDTH-1:0] dac_burst_sizes; 
    logic[DAC_NUM-1:0] hlt_cmds;
    logic[DAC_NUM-1:0][$clog2(SAMPLE_WIDTH):0] scale_factors; 
    logic[DAC_NUM-1:0] save_pwl_wave_periods;
    logic[DAC_NUM-1:0][PWL_PERIOD_SIZE-1:0][DATAW-1:0] pwl_wave_periods;

    enum logic[1:0] {IDLE_R, RESP_WAIT, RESET} rstState;     
    enum logic[1:0] {IDLE_B, BUFFT_POLL_WAIT, BUFFT_CLR_FB} bufftState;
    typedef enum logic {IDLE_DB, CHANGE_BURST_SIZE} dacBurstStateT;
    typedef enum logic {IDLE_S, CHANGE_SCALE} scaleParamStateT;
    typedef enum logic {IDLE_H, HALT_DAC} hltStateT;
    dacBurstStateT[DAC_NUM-1:0] dacBurstStates; 
    scaleParamStateT[DAC_NUM-1:0] scaleParamStates; 
    hltStateT[DAC_NUM-1:0] hltStates; 

    
    assign rst = ps_rst || rst_cmd;
    assign pl_rstn = ~rst_cmd; 

    // Maps which parts of the system are responssible for writing to which parts of the memory map (Defines ready, read, write, and write_data signals)
    always_comb begin
        for (int i=0; i< MAPPED_ID_CEILING; i++) begin
            case(i)
                RST_ID:            rtl_rdy[i] = rstState == IDLE_R; 
                BUFF_CONFIG_ID:    rtl_rdy[i] = adc_intf.state_rdy; 
                default: begin
                    if      (i inside {[PS_SEED_BASE_IDS[0] : PS_SEED_VALID_IDS[DAC_NUM-1]]})    rtl_rdy[i] = dac_intf.state_rdys[`memID_to_dacID(i,PS_SEED_BASE_IDS[0],BATCH_SIZE+1)];
                    else if (i inside {[DAC_HLT_IDS[0] : DAC_HLT_IDS[DAC_NUM-1]]})               rtl_rdy[i] = hltStates[`memID_to_dacID(i,DAC_HLT_IDS[0],1)] == IDLE_H; 
                    else if (i inside {[DAC_BURST_SIZE_IDS[0] : DAC_BURST_SIZE_IDS[DAC_NUM-1]]}) rtl_rdy[i] = dacBurstStates[`memID_to_dacID(i,DAC_BURST_SIZE_IDS[0],1)] == IDLE_DB; 
                    else if (i inside {[DAC_SCALE_IDS[0] : DAC_SCALE_IDS[DAC_NUM-1]]})           rtl_rdy[i] = scaleParamStates[`memID_to_dacID(i,DAC_SCALE_IDS[0],1)] == IDLE_S; 
                    else if (i inside {[TRIG_WAVE_IDS[0] : TRIG_WAVE_IDS[DAC_NUM-1]]})           rtl_rdy[i] = dac_intf.state_rdys[`memID_to_dacID(i,TRIG_WAVE_IDS[0],1)];
                    else if (i inside {[RUN_PWL_IDS[0] : RUN_PWL_IDS[DAC_NUM-1]]})               rtl_rdy[i] = dac_intf.state_rdys[`memID_to_dacID(i,RUN_PWL_IDS[0],1)];
                    else if (i inside {[CHAN_MUX_BASE_ID : SDC_VALID_ID]})                       rtl_rdy[i] = adc_intf.state_rdy; 
                    else rtl_rdy[i] = 1; 
                end 
            endcase 

            if ((is_RTLPOLL(i)) || (is_READONLY(i))) {rtl_read_reqs[i], rtl_write_reqs[i], rtl_wd_in[i]} = 0; //If rtl polls, no writing or reading. If it's readonly, just use the package definition
            else if (i inside {[BUFF_TIME_BASE_ID : BUFF_TIME_VALID_ID]}) begin
               if (i == BUFF_TIME_VALID_ID) rtl_read_reqs[i] = (bufftState == BUFFT_CLR_FB); 
               else rtl_read_reqs[i] = 0; 
                if (bufft_valid_clear) begin
                    if (i == BUFF_TIME_VALID_ID) {rtl_wd_in[i], rtl_write_reqs[i]} = 1; 
                    else {rtl_write_reqs[i], rtl_wd_in[i]} = 0;
                end else begin
                    rtl_write_reqs[i] = adc_intf.buff_timestamp_writereq; 
                    if (i == BUFF_TIME_VALID_ID) rtl_wd_in[i] = 1; 
                    else rtl_wd_in[i] = adc_intf.buff_timestamp_reg[(i-BUFF_TIME_BASE_ID)]; 
                end 
            end else if (i inside {[PWL_PERIOD_IDS[0] : PWL_PERIOD_VALID_IDS[DAC_NUM-1]]}) begin
                rtl_write_reqs[i] = save_pwl_wave_periods[`memID_to_dacID(i,PWL_PERIOD_IDS[0],PWL_PERIOD_SIZE+1)]; 
                rtl_wd_in[i] = pwl_wave_periods[`memID_to_dacID(i,PWL_PERIOD_IDS[0],PWL_PERIOD_SIZE+1)][`memID_to_dacRegID(i,PWL_PERIOD_IDS[0],PWL_PERIOD_SIZE)]; 
                rtl_read_reqs[i] = 0;
            end
            else {rtl_read_reqs[i], rtl_write_reqs[i], rtl_wd_in[i]} = 0;
        end
        rtl_rdy[MAPPED_ID_CEILING+:(MEM_SIZE-MAPPED_ID_CEILING)] = -1;
        rtl_read_reqs[MAPPED_ID_CEILING+:(MEM_SIZE-MAPPED_ID_CEILING)] = 0;
        rtl_write_reqs[MAPPED_ID_CEILING+:(MEM_SIZE-MAPPED_ID_CEILING)] = 0;
        rtl_wd_in[MAPPED_ID_CEILING+:(MEM_SIZE-MAPPED_ID_CEILING)] = 0;
    end

   // Overall system state machine ((parallelized) for halts and other DAC parameter changes)
   generate
        for (genvar dac_i = 0; dac_i < DAC_NUM; dac_i++) begin: DACS

            always_ff @(posedge ps_clk) begin
                if (rst) begin
                    hlt_cmds[dac_i] <= 0;
                    {dac_burst_sizes[dac_i],scale_factors[dac_i]} <= '0; 
                    dacBurstStates[dac_i] <= IDLE_DB; 
                    scaleParamStates[dac_i] <= IDLE_S; 
                    hltStates[dac_i] <= IDLE_H; 
                end 
                else begin                       
                    case(hltStates[dac_i])
                        IDLE_H: begin
                            if (fresh_bits[DAC_HLT_IDS[dac_i]]) begin 
                                hlt_cmds[dac_i] <= 1;
                                hltStates[dac_i] <= HALT_DAC; 
                            end 
                        end 
                        HALT_DAC: begin
                            hlt_cmds[dac_i] <= 0; 
                            hltStates[dac_i] <= IDLE_H; 
                        end 
                    endcase 
         
                    case(scaleParamStates[dac_i])
                        IDLE_S: begin
                            if (fresh_bits[DAC_SCALE_IDS[dac_i]]) scaleParamStates[dac_i] <= CHANGE_SCALE;
                        end 
         
                        CHANGE_SCALE: begin
                            scale_factors[dac_i] <= rtl_rd_out[DAC_SCALE_IDS[dac_i]];
                            scaleParamStates[dac_i] <= IDLE_S; 
                        end 
                    endcase 
         
                    case(dacBurstStates[dac_i])
                        IDLE_DB: begin 
                            if (fresh_bits[DAC_BURST_SIZE_IDS[dac_i]]) dacBurstStates[dac_i] <= CHANGE_BURST_SIZE; 
                        end 
                        CHANGE_BURST_SIZE: begin
                            dac_burst_sizes[dac_i] <= rtl_rd_out[DAC_BURST_SIZE_IDS[dac_i]]; 
                            dacBurstStates[dac_i] <= IDLE_DB; 
                        end 
                    endcase          
                end
            end
        end 
    endgenerate

    // Overall system state machine (unparallelized: resets, external reg handling)
    always_ff @(posedge ps_clk) begin
        if (rst) begin
            if (ps_rst) rst_cmd <= 1;
            else rst_cmd <= 0; 
            bufft_valid_clear <= 0; 
            rstState <= IDLE_R;
            bufftState <= IDLE_B; 
        end 
        else begin 
            case (rstState) 
                IDLE_R: begin
                    if (fresh_bits[RST_ID]) rstState <= RESP_WAIT; 
                end 
                RESP_WAIT: begin
                    if (wr_if.got_pack) rstState <= RESET; 
                end 
                RESET: begin
                    rst_cmd <= 1; 
                    rstState <= IDLE_R;
                end 
            endcase 

            case(bufftState)
                IDLE_B: begin
                    if (fresh_bits[BUFF_TIME_VALID_ID]) begin  // External module just wrote to the bufft register, wait for the processor to pull it if ever. 
                        bufftState <= BUFFT_POLL_WAIT; 
                    end
                end 
                BUFFT_POLL_WAIT: begin
                    if (~fresh_bits[BUFF_TIME_VALID_ID]) begin // processor is about to pull bufft reg, clear the valid addr
                        if (bufft_valid_clear) bufftState <= BUFFT_CLR_FB; 
                        else bufft_valid_clear <= 1; 
                    end 
                end 
                BUFFT_CLR_FB: begin //freshbit will be cleared here
                    bufftState <= IDLE_B; 
                end
            endcase 
            if (bufft_valid_clear) bufft_valid_clear <= 0; 
        end
    end

    axi_slave 
    slave(.clk(ps_clk), .rst(rst),
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


    DAC_Interface #(.DATAW(DATAW), .SAMPLEW(SAMPLE_WIDTH), .BS_WIDTH(BS_WIDTH), .BATCH_WIDTH(BATCH_WIDTH), .BATCH_SIZE(BATCH_SIZE))
    dac_intf(.ps_clk(ps_clk),.ps_rst(rst),
             .dac_clk(dac_clk),.dac_rst(dac_rst),
             .fresh_bits(fresh_bits), .read_resps(rtl_rd_out),
             .scale_factor_ins(scale_factors), .dac_bs_ins(dac_burst_sizes),
             .halts(hlt_cmds), .dac_rdys(dac_rdys), //in
             .dac_batches(dac_batches), //out 
             .valid_dac_batches(valid_dac_batches),
             .save_pwl_wave_periods(save_pwl_wave_periods), .pwl_wave_periods(pwl_wave_periods),
             .pwl_dmas_if(pwl_dmas_if));

    ADC_Interface #(.DATAW(DATAW), .SDC_SIZE(SDC_SIZE), .BUFF_CONFIG_WIDTH(BUFF_CONFIG_WIDTH), .CHAN_SIZE(CHAN_SIZE), .BUFF_SIZE(BUFF_SIZE)) 
    adc_intf(.clk(ps_clk), .rst(rst),
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