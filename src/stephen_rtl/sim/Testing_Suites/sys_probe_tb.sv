`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module sys_probe_tb();
    localparam BUFF_LEN = 14;
    
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
    logic[BUFF_LEN-1:0][`DMA_DATA_WIDTH-1:0] dma_buff, dma_buff2;
    logic[13:0][6:0] delays = {7'd1, 7'd44, 7'd121, 7'd109, 7'd86, 7'd100, 7'd112, 7'd28, 7'd73, 7'd20, 7'd76, 7'd141, 7'd42, 7'd64}; 
    logic[$clog2(BUFF_LEN)-1:0] dma_i; 
    logic send_dma_data,set_seeds,run_pwl,halt_dac,run_trig;
    logic first_sent, which_period; 
    logic[`WD_DATA_WIDTH-1:0] pwl_period0, pwl_period1; 
    enum logic[1:0] {IDLE_D, SEND_DMA_DATA,HOLD_CMD,DMA_WAIT} dmaState;
    enum logic[1:0] {IDLE_T, SET_SEEDS,WRESP,ERROR} dacTestState;
    enum logic {SEND_ADDR, GET_DATA} readState;

    assign dma_buff = {48'd1025, 48'd69818987317185, 48'd70368743129104, 48'd70364449210384, 48'd70364449211553, 48'd35180078433057, 48'd35180077123233, 48'd35180077121540, 48'd50242511372316, 48'd134423870374049, 48'd140737472299020, 48'd140733193388052, 48'd140733193389985, 48'd33489025}; 
    assign dma_buff2 = {48'd993, 48'd16, 48'd519690059792, 48'd5673650815137, 48'd6446744928280, 48'd6442450944008, 48'd6442450944193, 48'd257698366017, 48'd327704, 48'd38654574600, 48'd3337189458689, 48'd3440268673048, 48'd3298535407624, 48'd524481};
    assign {ps_wresp_rdy,ps_read_rdy,dac0_rdy,pwl_tkeep} = -1;
    assign ps_rstn = ~ps_rst;
    assign dac_rstn = ~dac_rst;
    assign pwl_last = dma_i == BUFF_LEN && pwl_valid;

    // ps_interface ps_interface(.ps_clk(ps_clk),.ps_rstn(ps_rstn), .pl_rstn(pl_rstn),
    //                           .dac_clk(dac_clk),.dac_rstn(dac_rstn),
    //                           .dac_tdata(dac_batch),.dac_tvalid(valid_dac_batch),.dac_tready(dac0_rdy),.rtl_dac_valid(rtl_dac_valid),
    //                           .ps_axi_araddr(raddr_packet),.ps_axi_arprot(ps_axi_arprot),.ps_axi_arvalid(raddr_valid_packet),.ps_axi_arready(ps_aread_rdy),
    //                           .ps_axi_rdata(rdata_packet),.ps_axi_rresp(rresp_out),.ps_axi_rvalid(rdata_valid_out),.ps_axi_rready(ps_read_rdy),
    //                           .ps_axi_awaddr(waddr_packet),.ps_axi_awprot(ps_axi_awprot),.ps_axi_awvalid(waddr_valid_packet),.ps_axi_awready(ps_awrite_rdy),
    //                           .ps_axi_wdata(wdata_packet),.ps_axi_wstrb(ps_axi_wstrb),.ps_axi_wvalid(wdata_valid_packet),.ps_axi_wready(ps_write_rdy),
    //                           .ps_axi_bresp(wresp_out),.ps_axi_bvalid(wresp_valid_out),.ps_axi_bready(ps_wresp_rdy),
    //                           .pwl_tdata(pwl_data),.pwl_tkeep(pwl_tkeep),.pwl_tlast(pwl_last),.pwl_tvalid(pwl_valid),.pwl_tready(pwl_ready));

    logic[`SAMPLE_WIDTH-1:0] x;
    logic[(2*`SAMPLE_WIDTH)-1:0] slope; 
    logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] intrp_batch;
    interpolater #(.SAMPLE_WIDTH(`SAMPLE_WIDTH), .BATCH_SIZE(`BATCH_SAMPLES))
    dut_i(.clk(dac_clk),
          .x(x), .slope(slope),
          .intrp_batch(intrp_batch));


    

    always_ff @(posedge ps_clk) begin
        if (ps_rst) begin
            {waddr_packet, wdata_packet} <= 0;
            {waddr_valid_packet, wdata_valid_packet} <= 0;
            which_period <= 0; 
            dacTestState <= IDLE_T;
            readState <= SEND_ADDR;
        end else begin
            case(readState)
                SEND_ADDR: begin 
                    raddr_packet <= (which_period)? `PWL_PERIOD0_ADDR : `PWL_PERIOD1_ADDR;
                    raddr_valid_packet <= 1; 
                    which_period <= ~which_period; 
                    readState <= GET_DATA;
                end 
                GET_DATA: begin
                    raddr_valid_packet <= 0; 
                    if (rdata_valid_out) begin
                        if (which_period) pwl_period0 <= rdata_packet; 
                        else pwl_period1 <= rdata_packet; 
                        readState <= SEND_ADDR;
                    end
                end 
            endcase 
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
            first_sent <= 0; 
            dmaState <= IDLE_D;
        end else begin
            case(dmaState)
                IDLE_D: begin 
                    if (send_dma_data) dmaState <= SEND_DMA_DATA;                        
                end 
                SEND_DMA_DATA: begin
                    if (dma_i == BUFF_LEN) begin 
                        first_sent <= 1; 
                        dmaState <= (send_dma_data)? DMA_WAIT : IDLE_D;
                        dma_i <= 0; 
                        {pwl_data,pwl_valid} <= 0;
                    end else begin
                        pwl_valid <= 1;
                        pwl_data <= (first_sent)? dma_buff2[dma_i] : dma_buff[dma_i];
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
        fork 
            begin `flash_signal(dac_rst,dac_clk); end 
            begin `flash_signal(ps_rst,ps_clk); end 
        join 
        // #1000;
        // `flash_sig(send_dma_data);
        // #100;
        // `flash_sig(set_seeds);
        // while (~rtl_dac_valid) #10;
        // #500;
        // `flash_sig(halt_dac);
        // while (rtl_dac_valid) #10;
        // #500;
        // `flash_sig(set_seeds);
        // while (~rtl_dac_valid) #10;
        // #100
        // `flash_sig(run_pwl);
        // #5000
        // `flash_sig(halt_dac);
        // #5000;
        // `flash_sig(run_trig);
        // #5000;
        // `flash_sig(set_seeds);
        // `flash_sig(send_dma_data);
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

