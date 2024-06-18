`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module interpolater#(parameter SAMPLE_WIDTH = 16, parameter BATCH_SIZE = 16)
                    (input wire clk,
                     input wire[SAMPLE_WIDTH-1:0] x,
                     input wire[(2*SAMPLE_WIDTH)-1:0] slope, 
                     output logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] intrp_batch); 
        localparam INTERPOLATER_DELAY = 4; 

        logic[BATCH_SIZE-1:0][(2*SAMPLE_WIDTH)-1:0] slopet,xpslopet,piped_x;
        always_ff @(posedge clk) begin
            piped_x <= x<<SAMPLE_WIDTH; 
            for (int i = 0; i < BATCH_SIZE; i++) begin
                slopet[i] <= slope*i;
                xpslopet[i] <= ({piped_x} + slopet[i])+16'h8000;
                intrp_batch[i] <= xpslopet[i][SAMPLE_WIDTH+:SAMPLE_WIDTH]; 
            end
        end

endmodule 

`default_nettype wire
