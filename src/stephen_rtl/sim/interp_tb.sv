`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module interp_tb();
    logic clk;
    logic[`SAMPLE_WIDTH-1:0] x,slope;
    logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] intrp_batch;

    pwl_generator #(.DMA_DATA_WIDTH(`DMA_DATA_WIDTH), .SAMPLE_WIDTH(`SAMPLE_WIDTH), .BATCH_WIDTH(`BATCH_WIDTH))
    pwl_gen(.clk(clk), .rst(rst || pwl_data_incoming), 
            .halt(halt || shutdown_pwl), 
            .run(run_pwl),
            .dac0_rdy(dac0_rdy),
            .batch_out(pwl_batch_out), .valid_batch_out(valid_pwl_batch),
            .dma(pwl_dma_if.stream_in));
    
    always begin
        #1.3020833;  
        clk = !clk;
    end

    initial begin
        $dumpfile("interp_tb.vcd");
        $dumpvars(0,interp_tb); 
        clk = 1;
        slope = 2;
        x = 0;
        #5000;
        slope = 50;
        #20;
        slope = -2;
        #20;
        slope = 10;
        #20;
        slope = 1000;
        #20;
        slope = 1;
        #20;
        $finish;
    end 

endmodule 



`default_nettype wire
