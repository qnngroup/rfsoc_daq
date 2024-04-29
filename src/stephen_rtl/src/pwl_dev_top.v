`timescale 1ns / 1ps
module pwl_dev_top(input clk, rstn, 
                   output valid_batch_out,
                   output[15:0][15:0] batch_out);

    pwl_wrapper pwrapper(.clk(clk), .rstn(rstn),
                         .valid_batch_out(valid_batch_out),
                         .batch_out(batch_out));
endmodule 
