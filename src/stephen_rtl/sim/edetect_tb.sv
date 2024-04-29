`default_nettype none
`timescale 1ns / 1ps

module edetect_tb();

    logic clk,rst;
    logic[31:0] val;
    logic[7:0] timer;
    logic[1:0] posedge_out,comb_posedge_out;
    edetect #(.DATA_WIDTH(32))
    DUT(.clk(clk), .rst(rst),
        .val(val),
        .comb_posedge_out(comb_posedge_out),
        .posedge_out(posedge_out));
    always begin
        #5;  
        clk = !clk;
    end

    always_ff @(posedge clk) begin
        if (rst) {val,timer} <= 0;
        else begin
            if (timer == 150) timer <= 0;
            else timer <= timer + 1;

            if (timer < 50) val <= val + 1;
            if (timer > 100 && timer < 150) val <= val - 1;
        end
    end
    initial begin
        $dumpfile("edetect_tb.vcd");
        $dumpvars(0,edetect_tb); 
        clk = 1;
        rst = 0;
        #10; rst = 1; #10; rst = 0; #100; 
        #1000;
        $finish;
    end 

endmodule 

`default_nettype wire
