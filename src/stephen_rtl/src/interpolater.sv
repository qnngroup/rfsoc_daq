`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module interpolater#(parameter SAMPLE_WIDTH = 16, parameter BATCH_SIZE = 16)
                    (input wire clk,
                     input wire[SAMPLE_WIDTH-1:0] x,slope, 
                     output logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] intrp_batch);

        logic[BATCH_SIZE-1:0][2*SAMPLE_WIDTH-1:0] xpslopet,slopet;
        logic[SAMPLE_WIDTH-1:0] piped_x; 
        always_ff @(posedge clk) begin
            piped_x <= x; 
            for (int i = 0; i < BATCH_SIZE; i++) begin
                slopet[i] <= slope*i;
                xpslopet[i] <= piped_x + slopet[i];
                intrp_batch[i] <= xpslopet[i]; 
            end
        end

endmodule 

`default_nettype wire
