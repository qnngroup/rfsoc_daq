`timescale 1ns / 1ps
`default_nettype none

module data_splicer #(parameter DATA_WIDTH = 32, parameter SPLICE_WIDTH = 4)                
                (input wire [DATA_WIDTH-1:0] data,
                input int i,
                output logic[SPLICE_WIDTH-1:0] spliced_data);  
  localparam SPLICES = DATA_WIDTH/SPLICE_WIDTH;  
  logic[DATA_WIDTH-1:0] send_mask;           
    assign send_mask = ( {DATA_WIDTH{1'b0}} + {SPLICE_WIDTH{$signed(1'b1)}} ) << i*SPLICE_WIDTH ;
  assign spliced_data = (data & send_mask) >> i*SPLICE_WIDTH;  
endmodule 

`default_nettype wire