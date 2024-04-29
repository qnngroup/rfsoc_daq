`default_nettype none
`timescale 1ns / 1ps

module splice_tb();
	logic clk,rst;
    logic[255:0] data;
    logic[3:0] i;
    logic[15:0] spliced_data;
    always begin
        #5;  
        clk = !clk;
    end
    data_splicer #(.DATA_WIDTH(256),
                   .SPLICE_WIDTH(16)) 
              uut (.clk(clk),
                   .rst(rst),
                   .data(data),
                   .i(i),
                   .spliced_data(spliced_data));
    always_ff @(posedge clk) begin
        if (rst) i <= 0;
        else begin
            i <= i + 1;
        end
    end
    initial begin
        $dumpfile("splice.vcd");
        $dumpvars(0,splice_tb); 
        clk = 1;
        rst = 0; 
        data =0;
        #50
        data = 256'hBEEFBF24BF59BF8EBFC3BFF8C02DC062C097C0CCC101C136C16BC1A0C1D5C20A; 
        rst=1;#10 rst=0;#10
        #500
        $finish;
    end 

endmodule 



`default_nettype wire
