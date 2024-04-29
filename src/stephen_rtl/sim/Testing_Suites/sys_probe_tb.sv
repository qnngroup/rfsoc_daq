`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module sys_probe_tb();
    localparam BUFF_LEN = 6;
    logic ps_clk,ps_rst;
    logic dac_clk,dac_rst;
    logic[`A_BUS_WIDTH-1:0] raddr_packet, waddr_packet;
    logic[`WD_BUS_WIDTH-1:0] rdata_packet, wdata_packet;
    logic[`DMA_DATA_WIDTH-1:0] pwl_data;
    logic[3:0] pwl_tkeep;
    logic pwl_last, pwl_rdy, pwl_valid, pwl_ready; 
    logic raddr_valid_packet, waddr_valid_packet, wdata_valid_packet, rdata_valid_out, wresp_valid_out, rresp_valid_out;
    logic ps_wresp_rdy,ps_read_rdy; 
    logic[1:0] wresp_out, rresp_out; 
    logic[(`BATCH_WIDTH)-1:0] dac_batch;
    logic valid_dac_batch, dac0_rdy;
    logic pl_rstn;
    logic[12:0] testReg; 
    logic[BUFF_LEN-1:0][`DMA_DATA_WIDTH-1:0] dma_buff;
    logic[$clog2(BUFF_LEN)-1:0] dma_i; 
    logic send_dma_data,set_seeds,run_pwl,halt_dac,run_trig; 
    enum logic {IDLE_D, SEND_DMA_DATA} dmaState;
    enum logic[1:0] {IDLE_T, SET_SEEDS,WRESP,ERROR} dacTestState;

    assign dma_buff = {48'd22,48'd47244509194,48'd528280912097,48'd498216271884,48'd412316991508,48'd131169};
    assign {ps_wresp_rdy,ps_read_rdy,dac0_rdy,pwl_tkeep} = -1;

    top_level tl(.ps_clk(ps_clk),.ps_rst(ps_rst),
                 .dac_clk(dac_clk),.dac_rst(dac_rst),
                 .pl_rstn(pl_rstn),
                 .dac0_rdy(dac0_rdy),
                 .dac_batch(dac_batch),.valid_dac_batch(valid_dac_batch),
                 .raddr_packet(raddr_packet),.raddr_valid_packet(raddr_valid_packet),
                 .waddr_packet(waddr_packet),.waddr_valid_packet(waddr_valid_packet),
                 .wdata_packet(wdata_packet),.wdata_valid_packet(wdata_valid_packet),
                 .rdata_packet(rdata_packet),.rdata_valid_out(rdata_valid_out),
                 .ps_wresp_rdy(ps_wresp_rdy),.wresp_out(wresp_out),
                 .ps_read_rdy(ps_read_rdy),.rresp_out(rresp_out),
                 .wresp_valid_out(wresp_valid_out),
                 .rresp_valid_out(rresp_valid_out),
                 .pwl_tdata(pwl_data),.pwl_tvalid(pwl_valid),
                 .pwl_tlast(pwl_last),.pwl_tready(pwl_ready),
                 .pwl_tkeep(pwl_tkeep));

    

    always_ff @(posedge ps_clk) begin
        if (ps_rst) begin
            {waddr_packet, wdata_packet} <= 0;
            {waddr_valid_packet, wdata_valid_packet} <= 0;
            dacTestState <= IDLE_T;
        end else begin
            case(dacTestState)
                IDLE_T: begin
                    if (set_seeds) begin
                        waddr_packet <= `PS_SEED_BASE_ADDR;
                        wdata_packet <= 16'hBEEF;
                        {waddr_valid_packet, wdata_valid_packet} <= 3;
                        dacTestState <= WRESP;
                    end 
                    if (run_pwl) begin
                        waddr_packet <= `RUN_PWL_ADDR;
                        wdata_packet <= 1;
                        {waddr_valid_packet, wdata_valid_packet} <= 3;
                        dacTestState <= WRESP;
                    end
                    if (run_trig) begin
                        waddr_packet <= `TRIG_WAVE_ADDR;
                        wdata_packet <= 1;
                        {waddr_valid_packet, wdata_valid_packet} <= 3;
                        dacTestState <= WRESP;
                    end
                    if (halt_dac) begin
                        waddr_packet <= `DAC_HLT_ADDR;
                        wdata_packet <= 1;
                        {waddr_valid_packet, wdata_valid_packet} <= 3;
                        dacTestState <= WRESP;
                    end
                end 
                SET_SEEDS: begin
                    waddr_packet <= waddr_packet + 4;
                    wdata_packet <= wdata_packet + 1;
                    {waddr_valid_packet, wdata_valid_packet} <= 3;
                    dacTestState <= WRESP;
                end 
                WRESP: begin
                    {waddr_valid_packet, wdata_valid_packet} <= 0;
                    if (wresp_valid_out && ps_wresp_rdy) begin
                        if (wresp_out != `OKAY) dacTestState <= ERROR;
                        else begin 
                            if (waddr_packet >= `PS_SEED_BASE_ADDR && waddr_packet <= `PS_SEED_VALID_ADDR) dacTestState <= (waddr_packet == `PS_SEED_VALID_ADDR)? IDLE_T : SET_SEEDS; 
                            else dacTestState <= IDLE_T;
                        end 
                    end
                end 
            endcase
        end
    end

    always_ff @(posedge dac_clk) begin
        if (dac_rst) begin
            {pwl_data,pwl_valid,pwl_last,dma_i} <= 0; 
            dmaState <= IDLE_D;
        end else begin
            case(dmaState)
                IDLE_D: begin 
                    if (send_dma_data) begin
                        pwl_valid <= 1;
                        pwl_data <= dma_buff[dma_i];
                        dmaState <= SEND_DMA_DATA;
                    end
                end 
                SEND_DMA_DATA: begin
                    if (pwl_ready) begin
                        dma_i <= dma_i + 1; 
                        pwl_data <= dma_buff[dma_i+1];
                        if (dma_i == BUFF_LEN-2) pwl_last <= 1; 
                        if (dma_i == BUFF_LEN-1) begin 
                            dmaState <= IDLE_D;
                            dma_i <= 0; 
                            {pwl_data,pwl_valid,pwl_last} <= 0;
                        end 
                    end 
                end 
            endcase 
        end
    end

     always begin
        #3.333333;  
        ps_clk = !ps_clk;
    end
    always begin
        #1.3020833;  
        dac_clk = !dac_clk;
    end

    initial begin
        $dumpfile("sys_probe_tb.vcd");
        $dumpvars(0,sys_probe_tb); 
        ps_clk = 0;
        dac_clk = 0;
        ps_rst = 0;
        dac_rst = 0; 
        send_dma_data = 0;
        {set_seeds,run_pwl,halt_dac,run_trig} = 0; 
        #10;
        `flash_sig(dac_rst);
        `flash_sig(ps_rst);
        #1000;
        `flash_sig(send_dma_data);
        #100;
        `flash_sig(set_seeds);
        while (~valid_dac_batch) #10;
        #500;
        `flash_sig(halt_dac);
        while (valid_dac_batch) #10;
        #500;
        `flash_sig(set_seeds);
        while (~valid_dac_batch) #10;
        #5000
        `flash_sig(run_pwl);
        #100;
        while (~tl.sys.dac_intf.state_rdy) #10;
        #5000
        `flash_sig(halt_dac);
        #5000;
        `flash_sig(run_trig);
        #5000;
        `flash_sig(set_seeds);
        #5000;
        `flash_sig(run_pwl);
        #5000;
        `flash_sig(run_trig);
        #5000;
        `flash_sig(halt_dac);
        #5000;
        $finish;
    end 

endmodule 

`default_nettype wire

