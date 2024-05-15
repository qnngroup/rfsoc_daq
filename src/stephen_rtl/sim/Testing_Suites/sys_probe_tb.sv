`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module sys_probe_tb();
    localparam BUFF_LEN = 7;
    
    logic ps_clk,ps_rst,ps_rstn;
    logic dac_clk,dac_rst,dac_rstn;
    logic[`A_BUS_WIDTH-1:0] raddr_packet, waddr_packet;
    logic[`WD_BUS_WIDTH-1:0] rdata_packet, wdata_packet;
    logic[2:0] ps_axi_arprot,ps_axi_awprot;
    logic[3:0] ps_axi_wstrb;
    logic[63:0] pwl_data;
    logic[7:0] pwl_tkeep;
    logic[15:0] dma_timer, timer_limit;
    logic pwl_last, pwl_valid, pwl_ready; 
    logic raddr_valid_packet, waddr_valid_packet, wdata_valid_packet, rdata_valid_out, wresp_valid_out;
    logic ps_wresp_rdy,ps_read_rdy, ps_write_rdy,ps_awrite_rdy,ps_aread_rdy; 
    logic[1:0] wresp_out, rresp_out; 
    logic[`BATCH_WIDTH-1:0] dac_batch;
    logic valid_dac_batch, rtl_dac_valid, dac0_rdy;
    logic pl_rstn;
    logic[12:0] testReg; 
    logic[BUFF_LEN-1:0][`DMA_DATA_WIDTH-1:0] dma_buff;
    // logic[6:0][3:0] delays = {2'd11, 2'd12, 2'd12, 2'd1, 2'd1, 2'd1, 2'd12};
    logic[6:0][1:0] delays = {2'd1, 2'd2, 2'd2, 2'd1, 2'd1, 2'd1, 2'd2};
    logic[$clog2(BUFF_LEN)-1:0] dma_i; 
    logic send_dma_data,set_seeds,run_pwl,halt_dac,run_trig; 
    enum logic[1:0] {IDLE_D, SEND_DMA_DATA,HOLD_CMD,DMA_WAIT} dmaState;
    enum logic[1:0] {IDLE_T, SET_SEEDS,WRESP,ERROR} dacTestState;

    assign dma_buff = {48'd609, 48'd16, 48'd38654640144, 48'd382252023969, 48'd433791631384, 48'd412316925960, 48'd65729}; 
    assign {ps_wresp_rdy,ps_read_rdy,dac0_rdy,pwl_tkeep} = -1;
    assign ps_rstn = ~ps_rst;
    assign dac_rstn = ~dac_rst;
    assign pwl_last = dma_i == BUFF_LEN && pwl_valid;

    ps_interface ps_interface(.ps_clk(ps_clk),.ps_rstn(ps_rstn), .pl_rstn(pl_rstn),
                              .dac_clk(dac_clk),.dac_rstn(dac_rstn),
                              .dac_tdata(dac_batch),.dac_tvalid(valid_dac_batch),.dac_tready(dac0_rdy),.rtl_dac_valid(rtl_dac_valid),
                              .ps_axi_araddr(raddr_packet),.ps_axi_arprot(ps_axi_arprot),.ps_axi_arvalid(raddr_valid_packet),.ps_axi_arready(ps_aread_rdy),
                              .ps_axi_rdata(rdata_packet),.ps_axi_rresp(rresp_out),.ps_axi_rvalid(rdata_valid_out),.ps_axi_rready(ps_read_rdy),
                              .ps_axi_awaddr(waddr_packet),.ps_axi_awprot(ps_axi_awprot),.ps_axi_awvalid(waddr_valid_packet),.ps_axi_awready(ps_awrite_rdy),
                              .ps_axi_wdata(wdata_packet),.ps_axi_wstrb(ps_axi_wstrb),.ps_axi_wvalid(wdata_valid_packet),.ps_axi_wready(ps_write_rdy),
                              .ps_axi_bresp(wresp_out),.ps_axi_bvalid(wresp_valid_out),.ps_axi_bready(ps_wresp_rdy),
                              .pwl_tdata(pwl_data),.pwl_tkeep(pwl_tkeep),.pwl_tlast(pwl_last),.pwl_tvalid(pwl_valid),.pwl_tready(pwl_ready));

    

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
            {pwl_data,pwl_valid,dma_i,dma_timer} <= 0; 
            dmaState <= IDLE_D;
        end else begin
            case(dmaState)
                IDLE_D: begin 
                    if (send_dma_data) dmaState <= SEND_DMA_DATA;                        
                end 
                SEND_DMA_DATA: begin
                    if (dma_i == BUFF_LEN) begin 
                        dmaState <= (send_dma_data)? DMA_WAIT : IDLE_D;
                        dma_i <= 0; 
                        {pwl_data,pwl_valid} <= 0;
                    end else begin
                        pwl_valid <= 1;
                        pwl_data <= dma_buff[dma_i];
                        timer_limit <= delays[dma_i];
                        dma_i <= dma_i + 1; 
                        dmaState <= HOLD_CMD;
                    end 
                end 
                HOLD_CMD: begin
                    if (dma_timer >= timer_limit && ~pwl_valid) begin
                        dma_timer <= 0;
                        dmaState <= SEND_DMA_DATA;
                    end else dma_timer <= dma_timer+1; 
                    if (pwl_ready) pwl_valid <= 0;
                end 
                DMA_WAIT: begin
                    if (~send_dma_data) dmaState <= IDLE_D; 
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
        // `flash_sig(set_seeds);
        // while (~rtl_dac_valid) #10;
        // #500;
        // `flash_sig(halt_dac);
        // while (rtl_dac_valid) #10;
        // #500;
        // `flash_sig(set_seeds);
        // while (~rtl_dac_valid) #10;
        // #100
        `flash_sig(run_pwl);
        #5000
        // `flash_sig(halt_dac);
        // #5000;
        // `flash_sig(run_trig);
        // #5000;
        // `flash_sig(set_seeds);
        // #5000;
        // `flash_sig(run_pwl);
        // #5000;
        // `flash_sig(run_trig);
        // #5000;
        // `flash_sig(halt_dac);
        #5000;
        $finish;
    end 

endmodule 

`default_nettype wire

