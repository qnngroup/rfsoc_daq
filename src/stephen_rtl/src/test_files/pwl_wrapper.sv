`timescale 1ns / 1ps
module pwl_wrapper #(DMA_DATA_WIDTH = 48, SAMPLE_WIDTH = 16, BATCH_WIDTH = 256, SPARSE_BRAM_DEPTH = 600, DENSE_BRAM_DEPTH = 600)
                    (input clk, rstn, 
                     output valid_batch_out,
                     output[SAMPLE_WIDTH-1:0][SAMPLE_WIDTH-1:0] batch_out);
    localparam BATCH_SAMPLES = BATCH_WIDTH/SAMPLE_WIDTH;
    localparam BUFF_LEN = 6;
  
    logic rst,halt,run,start;
    logic dac0_rdy;
    logic[BUFF_LEN-1:0][DMA_DATA_WIDTH-1:0] dma_buff;
    logic[$clog2(DMA_DATA_WIDTH)-1:0] buff_ptr;
    logic write_rdy, rdy_to_run;
    Axis_IF #(DMA_DATA_WIDTH) dma();
    enum logic[2:0] {IDLE,WRITE,WAIT,READ,SEND, RUNNING} testState;

    assign dac0_rdy = 1;
    assign rst = ~rstn;
    assign start = 1;
    assign dma_buff = {48'd22,48'd47244509194,48'd528280912097,48'd498216271884,48'd412316991508,48'd131169};

    always_ff @(posedge clk) begin
        if (rst) begin  
            {dma.data,dma.valid,dma.last,buff_ptr, run} <= 0;
            testState <= IDLE; 
        end
        else begin
            case(testState)
                IDLE: begin
                    if (start && buff_ptr == 0) testState <= SEND;
                    if (rdy_to_run) begin
                        run <= 1;
                        testState <= RUNNING;
                    end 
                end 
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
        
   pwl_generator #(.DMA_DATA_WIDTH(DMA_DATA_WIDTH), .SAMPLE_WIDTH(SAMPLE_WIDTH),
                    .BATCH_WIDTH(BATCH_WIDTH), .SPARSE_BRAM_DEPTH(SPARSE_BRAM_DEPTH), 
                    .DENSE_BRAM_DEPTH(DENSE_BRAM_DEPTH))
      pwl_generator(.clk(clk),.rst(rst),
                    .halt(halt),
                    .run(run), .rdy_to_run(rdy_to_run),
                    .dac0_rdy(dac0_rdy),
                    .batch_out(batch_out),
                    .valid_batch_out(valid_batch_out),
                    .dma(dma.stream_in));

endmodule 
