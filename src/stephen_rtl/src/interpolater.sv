`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module interpolater#(parameter SAMPLE_WIDTH = 16, parameter BATCH_SIZE = 16)
                    (input wire clk,
                     input wire[SAMPLE_WIDTH-1:0] x,
                     input wire[(2*SAMPLE_WIDTH)-1:0] slope, 
                     output logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] intrp_batch);

        logic[BATCH_SIZE-1:0][2*SAMPLE_WIDTH-1:0] xpslopet;
        logic[BATCH_SIZE-1:0][(4*SAMPLE_WIDTH)-1:0] slopet;
        logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] whole_line;
        logic[SAMPLE_WIDTH-1:0] piped_x; 
        always_comb begin
            for (int i = 0; i < BATCH_SIZE; i++) whole_line[i] = slopet[i][SAMPLE_WIDTH+:SAMPLE_WIDTH];
        end
        always_ff @(posedge clk) begin
            piped_x <= x; 
            for (int i = 0; i < BATCH_SIZE; i++) begin
                slopet[i] <= slope*i;
                xpslopet[i] <= piped_x + slopet[i][SAMPLE_WIDTH+:SAMPLE_WIDTH];
                intrp_batch[i] <= xpslopet[i]; 
            end
        end

endmodule 

`default_nettype wire
