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
                 //PWL DMA Inputs/Outputs
                 Axis_IF pwl_dma_if); 

    logic [`MEM_SIZE-1:0] fresh_bits,rtl_read_reqs;
    logic [`MEM_SIZE-1:0][`WD_DATA_WIDTH-1:0] rtl_read_resps;
    logic[`MEM_SIZE-1:0] rtl_write_reqs;
    logic[`MEM_SIZE-1:0][`WD_DATA_WIDTH-1:0] rtl_wd_in, rtl_rd_out;
    logic[$clog2(`MAX_ILA_BURST_SIZE):0] ila_burst_size; 
    logic rst_read, hlt_read, ila_burst_read, max_ila_bs_read, scale_read;
    logic rst_cmd = 1;
    logic rst,hlt_cmd;
    logic[`BATCH_WIDTH-1:0] dac_batch_unfiltered;
    logic[$clog2(`SAMPLE_WIDTH):0] scale_factor; 
    logic [`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] dac_samples, dac_samples_scaled; 
    logic[$clog2(`MAX_ILA_BURST_SIZE)+1:0] hlt_counter; 
    enum logic[1:0] {IDLE_R, RESP_WAIT, RESET} rstState; 
    enum logic[1:0] {IDLE_I, READ_WAIT_I, CHANGE_BURST_SIZE} ilaParamState;
    enum logic[1:0] {IDLE_S, READ_WAIT_S, CHANGE_SCALE} scaleParamState;

    assign rst = sys_rst || rst_cmd;
    assign pl_rstn = ~rst; 
    assign dac_batch = dac_samples_scaled;  
    // Combinationally scale the dac output 
    generate
        for (genvar i = 0; i < `BATCH_SAMPLES; i++) begin: batch_splices
            data_splicer #(.DATA_WIDTH(`BATCH_WIDTH), .SPLICE_WIDTH(`SAMPLE_WIDTH))
            dac_out_splice(.data(dac_batch_unfiltered),
                           .i(int'(i)),
                           .spliced_data(dac_samples[i]));
        end
    endgenerate

    always_comb begin
        for (int i = 0; i < `BATCH_SAMPLES; i++) begin
            dac_samples_scaled[i] = dac_samples[i] >> scale_factor;
        end 
    end

    // Maps which parts of the system are responssible for writing to which parts of the memory map
    always_comb begin
        for (int i=0; i<`MEM_SIZE; i++) begin
            if (i == `RST_ID) begin 
                rtl_read_reqs[i] = rst_read;
                {rtl_write_reqs[i], rtl_wd_in[i]} = 0;
            end 
            else if (i == `DAC_HLT_ID) begin 
                rtl_read_reqs[i] = hlt_read;
                {rtl_write_reqs[i], rtl_wd_in[i]} = 0;
            end 
            else if (i == `ILA_BURST_SIZE_ID) begin 
                rtl_read_reqs[i] = ila_burst_read;
                {rtl_write_reqs[i], rtl_wd_in[i]} = 0;
            end 
            else if (i == `MAX_BURST_SIZE_ID) begin
                rtl_read_reqs[i] = max_ila_bs_read; 
                {rtl_write_reqs[i], rtl_wd_in[i]} = 0;
            end
            else if (i == `SCALE_DAC_OUT_ID) begin 
                rtl_read_reqs[i] = scale_read;
                {rtl_write_reqs[i], rtl_wd_in[i]} = 0;
            end 
            else if (i >= `PS_SEED_BASE_ID && i <= `TRIG_WAVE_ID || i == `PWL_PREP_ID) begin
                rtl_read_reqs[i] = dac_intf.read_reqs[i];
                {rtl_write_reqs[i], rtl_wd_in[i]} = 0;
            end 
            else if (i == `DAC_ILA_TRIG_ID) begin
                rtl_read_reqs[i] = read_ila_trig; 
                {rtl_write_reqs[i], rtl_wd_in[i]} = 0; 
            end 
            else if (i == `DAC_ILA_RESP_ID) begin
                rtl_read_reqs[i] = 0; 
                {rtl_write_reqs[i], rtl_wd_in[i]} = {ila_resp_wr, ila_resp_wd}; 
            end 
            else if (i == `DAC_ILA_RESP_VALID_ID) begin
                rtl_read_reqs[i] = 0; 
                {rtl_write_reqs[i], rtl_wd_in[i]} = {ila_resp_valid_wr, ila_resp_valid_wd}; 
            end 
            else {rtl_read_reqs[i], rtl_write_reqs[i], rtl_wd_in[i]} = 0;
        end
    end

    // Overall system state machine (for resets, halts, parameter changes)
    always_ff @(posedge clk) begin
        if (rst) begin
            {rst_cmd,rst_read,ila_burst_read,max_ila_bs_read,scale_read} <= 0;
            {ila_burst_size,scale_factor} <= 0; 
            rstState <= IDLE_R;
            ilaParamState <= IDLE_I; 
            scaleParamState <= IDLE_S; 
            {hlt_cmd,hlt_read,hlt_counter} <= 0;
        end 
        else begin
            if (valid_dac_batch && ila_burst_size != 0) begin
                if ( (hlt_counter+1) < ila_burst_size) hlt_counter <= hlt_counter + 1; 
                else hlt_counter <= 0; 
            end 
 
            if (fresh_bits[`DAC_HLT_ID] || ( valid_dac_batch && ila_burst_size != 0 && hlt_counter == (ila_burst_size-1) )) begin
                if (fresh_bits[`DAC_HLT_ID]) hlt_read <= 1;
                hlt_cmd <= 1;
            end else begin
                if (hlt_cmd) hlt_cmd <= 0;
                if (hlt_read) hlt_read <= 0; 
            end

            case(scaleParamState)
                IDLE_S: begin
                    if (fresh_bits[`SCALE_DAC_OUT_ID]) begin
                        scale_read <= 1; 
                        scaleParamState <= READ_WAIT_S;
                    end
                end 

                READ_WAIT_S: begin
                    scale_read <= 0;
                    scaleParamState <= CHANGE_SCALE; 
                end 

                CHANGE_SCALE: begin
                    scale_factor <= (rtl_read_resps[`SCALE_DAC_OUT_ID] <= 15)? rtl_read_resps[`SCALE_DAC_OUT_ID] : 15;
                    scaleParamState <= IDLE_S; 
                end 
            endcase 

            case(ilaParamState)
                IDLE_I: begin 
                    if (fresh_bits[`ILA_BURST_SIZE_ID]) begin 
                        ila_burst_read <= 1; 
                        ilaParamState <= READ_WAIT_I; 
                    end 
                end 
                READ_WAIT_I: begin 
                    ila_burst_read <= 0;
                    ilaParamState <= CHANGE_BURST_SIZE; 
                end 

                CHANGE_BURST_SIZE: begin
                    ila_burst_size <= rtl_read_resps[`ILA_BURST_SIZE_ID]; 
                    ilaParamState <= IDLE_I; 
                end 
            endcase 

            case (rstState) 
                IDLE_R: begin
                    if (fresh_bits[`RST_ID]) begin
                        rstState <= RESP_WAIT; 
                        rst_read <= 1;
                    end
                end 

                RESP_WAIT: begin 
                    if (wr_if.got_pack) rstState <= RESET; 
                    if (rst_read) rst_read <= 0;
                end 

                RESET: begin
                    rst_cmd <= 1; 
                    rstState <= IDLE_R;
                end 
            endcase 
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
          .rtl_wd_in(rtl_wd_in),               //in
          .rtl_rd_out(rtl_read_resps),         //out 
          .fresh_bits(fresh_bits));


    DAC_Interface dac_intf(.clk(clk),.rst(rst),
                          .fresh_bits(fresh_bits),
                          .read_resps(rtl_read_resps),
                          .dac0_rdy(dac0_rdy), 
                          .halt(hlt_cmd),                   //in
                          .dac_batch(dac_batch_unfiltered), //out 
                          .valid_dac_batch(valid_dac_batch),
                          .valid_dac_edge(valid_dac_edge),
                          .pwl_dma_if(pwl_dma_if));

    
    logic dac_sample_pulled;
    logic[`SAMPLE_WIDTH-1:0] dac_ila_sample;
    logic[`WD_DATA_WIDTH-1:0] ila_resp_valid_wd, ila_resp_wd; 
    logic ila_resp_valid_wr, ila_resp_wr, read_ila_trig; 
    logic valid_dac_ila_sample;  
    logic[1:0] valid_dac_edge; 
    enum logic[1:0] {SEND_SAMPLE, WRITE_WAIT, WAIT_FOR_POLL} dacIlaState; 

    // To manage sending of dac ila samples 
    always_ff @(posedge clk) begin
        if (rst) begin
            {dac_sample_pulled, read_ila_trig, ila_resp_valid_wr,ila_resp_valid_wd, ila_resp_wr,ila_resp_wd} <= 0;
            dacIlaState <= SEND_SAMPLE; 
        end else begin
            case(dacIlaState) 
                SEND_SAMPLE: begin
                    if (valid_dac_ila_sample) begin                                // a sample is ready to be sent
                        {ila_resp_wr, ila_resp_valid_wr} <= 3;
                        ila_resp_wd <= dac_ila_sample; 
                        ila_resp_valid_wd <= 1; 
                        dacIlaState <= WRITE_WAIT; 
                    end
                end 
                WRITE_WAIT: dacIlaState <= WAIT_FOR_POLL;
                WAIT_FOR_POLL: begin 
                    if (~fresh_bits[`DAC_ILA_RESP_VALID_ID]) begin                  // processor is about to poll
                        ila_resp_valid_wr <= 1;
                        ila_resp_valid_wd <= 0; 
                        dac_sample_pulled <= 1; 
                    end
                    if (~fresh_bits[`DAC_ILA_RESP_ID]) dacIlaState <= SEND_SAMPLE;  // processor just polled; get ready to send next sample 
                end 
            endcase 

            if (fresh_bits[`DAC_ILA_TRIG_ID]) read_ila_trig <= 1;                   // ila response barrage to be expected soon
            if (read_ila_trig) read_ila_trig <= 0; 
            if (ila_resp_wr) ila_resp_wr <= 0;
            if (ila_resp_valid_wr) ila_resp_valid_wr <= 0;
            if (dac_sample_pulled) dac_sample_pulled <= 0; 
        end
    end
    ila #(.LINE_WIDTH(`BATCH_WIDTH), .SAMPLE_WIDTH (`SAMPLE_WIDTH), .MAX_ILA_BURST_SIZE (`MAX_ILA_BURST_SIZE)) 
        dac_ila(.clk(clk), .rst(rst),
            .ila_line_in(dac_batch),
            .set_trigger(fresh_bits[`DAC_ILA_TRIG_ID]),
            .trigger_event(valid_dac_edge == 1),
            .save_condition({1'b1, valid_dac_batch}),
            .ila_burst_size_in(ila_burst_size),
            .sample_pulled(dac_sample_pulled),          //in
            .sample_to_send(dac_ila_sample),            //out 
            .valid_sample_out(valid_dac_ila_sample));    

endmodule 

`default_nettype wire

/*
TODO:
1. Idk what MAX_BURST_SIZE_ID corresponds to, figure it out or remove it (DONE)
2. Idk why the dac_ila has a full vector of write requests when it only needs two: one for placing a sample and one for letting the PS know a sample was placed. Fix that (DONE)
3. 
*/