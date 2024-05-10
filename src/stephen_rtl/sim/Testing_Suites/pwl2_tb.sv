`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module pwl2_tb();
    localparam SAMPLE_WIDTH = 16;
    localparam BATCH_WIDTH = 256; 
    localparam DMA_DATA_WIDTH = 48;
    localparam DENSE_BRAM_DEPTH = 600;
    localparam SPARSE_BRAM_DEPTH = 600;
    localparam BUFF_LEN = 6;
    localparam LINES_TO_STORE = 3;
    localparam BATCH_SIZE = BATCH_WIDTH/SAMPLE_WIDTH;

    // logic clk,rst,rstn; 
    // logic [SAMPLE_WIDTH-1:0][SAMPLE_WIDTH-1:0] batch_out;
    // logic valid_batch_out;

    // assign rstn = ~rst;

    // pwl_wrapper DUT(.clk(clk), .rstn(rstn),
    //                 .valid_batch_out(valid_batch_out),
    //                 .batch_out(batch_out));




    logic clk, rst, halt, run, start;
    logic dac0_rdy;
    Axis_IF #(DMA_DATA_WIDTH) dma();
    logic[BUFF_LEN-1:0][DMA_DATA_WIDTH-1:0] dma_buff;
    logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] batch_out;
    logic[$clog2(DMA_DATA_WIDTH)-1:0] buff_ptr;
    logic valid_batch_out;
    logic write_rdy, rdy_to_run;
    enum logic[2:0] {IDLE,WRITE,WAIT,READ,SEND, RUNNING} testState;

    assign dac0_rdy = 1;
    assign dma_buff = {48'd22,48'd47244509194,48'd528280912097,48'd498216271884,48'd412316991508,48'd131169};

    pwl_generator #(.DMA_DATA_WIDTH(DMA_DATA_WIDTH), .SAMPLE_WIDTH(SAMPLE_WIDTH),
                    .BATCH_SIZE(BATCH_SIZE), .SPARSE_BRAM_DEPTH(SPARSE_BRAM_DEPTH), 
                    .DENSE_BRAM_DEPTH(DENSE_BRAM_DEPTH))
                DUT(.clk(clk),.rst(rst),
                    .halt(halt),
                    .run(run), .rdy_to_run(rdy_to_run),
                    .dac0_rdy(dac0_rdy),
                    .batch_out(batch_out),
                    .valid_batch_out(valid_batch_out),
                    .dma(dma.stream_in));

    logic[$clog2(SPARSE_BRAM_DEPTH)-1:0] sbram_addr; 
    logic[DMA_DATA_WIDTH-1:0] sparse_line_in,sparse_batch_out,init_val;
    logic valid_sparse_batch;
    logic sbram_en, sbram_we;
    logic generator_mode, rst_gen_mode, next;
    logic[9:0] timer; 

    sparse_bram_interface #(.DATA_WIDTH(DMA_DATA_WIDTH), .BRAM_DEPTH(SPARSE_BRAM_DEPTH))
    SWAVE_BRAM_INT (.clk(clk), .rst(rst),      
                    .addr(sbram_addr),     
                    .line_in(sparse_line_in),       
                    .we(sbram_we), .en(sbram_en), 
                    .next(next),
                    .generator_mode(generator_mode), .rst_gen_mode(rst_gen_mode),
                    .line_out(sparse_batch_out),
                    .valid_line_out(valid_sparse_batch),
                    .write_rdy(write_rdy));


    always_ff @(posedge clk) begin
        if (rst) begin  
            // sbram_addr <= 0;
            // init_val <= 100;
            // sparse_line_in <= 100;
            // {sbram_we,sbram_en} <= 0;
            // {timer,next,generator_mode,rst_gen_mode} <= 0;
            {dma.data,dma.valid,dma.last,buff_ptr, run} <= 0;
            testState <= IDLE; 
        end
        else begin
            case(testState)
                IDLE: begin
                    // if (start) begin
                    //     testState <= WRITE; 
                    //     {sbram_we,sbram_en} <= 3;
                    // end 
                    if (start && buff_ptr == 0) testState <= SEND;
                    if (rdy_to_run) begin
                        run <= 1;
                        testState <= RUNNING;
                    end 

                end 

                // WRITE: begin
                //     if (write_rdy) begin
                //         if (sbram_addr == LINES_TO_STORE-1) begin
                //             {sbram_we,sbram_en} <= 0;
                //             if (timer == 20) begin
                //                 sbram_addr <= 0;
                //                 generator_mode <= 1; 
                //                 timer <= 0;
                //                 testState <= WAIT;
                //             end else timer <= timer + 1;
                //         end else begin
                //             sbram_addr <= sbram_addr + 1;
                //             sparse_line_in <= sparse_line_in + 1; 
                //         end
                //     end 
                // end 

                // WAIT: begin
                //     if (valid_sparse_batch) testState <= READ;
                // end 

                // READ: begin
                //     if (timer == 410) begin
                //         // timer <= 0; 
                //         generator_mode <= 0;
                //         // sparse_line_in <= init_val+100;
                //         // init_val <= init_val + 100; 
                //         // sbram_addr <= 0;
                //         // {sbram_we,sbram_en} <= 3;
                //         // testState <= WRITE; 
                //     end else timer <= timer + 1; 

                //     if (timer == 5) next <= 1;
                //     if (timer == 6) next <= 0;

                //     if (timer == 12) next <= 1;
                //     if (timer == 13) next <= 0;

                //     if (timer == 20) next <= 1;
                //     if (timer == 40) next <= 0;

                //     if (timer == 45) next <= 1;
                //     if (timer == 100) next <= 0;

                //     if (timer == 120) rst_gen_mode <= 1;
                //     if (timer == 130) rst_gen_mode <= 0;

                //     if (timer == 150) next = 1;
                //     if (timer == 400) next = 0;
                // end 

                SEND: begin
                    if (dma.ready) begin
                        dma.data <= (buff_ptr < BUFF_LEN)? dma_buff[buff_ptr] : 0;
                        dma.valid <= 1;
                        buff_ptr <= buff_ptr + 1; 
                        if (buff_ptr == BUFF_LEN-1) dma.last <= 1;
                        if (buff_ptr == BUFF_LEN) begin
                            dma.valid <= 0; 
                            dma.last <= 0;
                            testState <= IDLE;
                        end 
                    end
                end 

                RUNNING: begin
                    run <= 0;
                    if (halt) testState <= IDLE;
                end 
            endcase
        end
    end

    always begin
        #5;  
        clk = !clk;
    end

    initial begin
        $dumpfile("pwl2_tb.vcd");
        $dumpvars(0,pwl2_tb); 
        // clk = 1;
        // rst = 0;
        // #100;
        // `flash_sig(rst);
        // #10000;
        clk = 1;
        start = 0;
        rst = 0;
        halt = 0;
        #40;
        `flash_sig(rst); 
        #10;
        start = 1;
        #10000;
        halt = 1;
        #10; halt = 0;
        #10000;
        $finish;
    end 

endmodule 

`default_nettype wire
