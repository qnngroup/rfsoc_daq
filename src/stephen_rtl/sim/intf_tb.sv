`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module intf_tb();
    logic clk,rst;

    Recieve_Transmit_IF #(`WD_BUS_WIDTH, `WD_DATA_WIDTH) wd_if (); 

    axi_receive #(.BUS_WIDTH(`WD_BUS_WIDTH), .DATA_WIDTH(`WD_DATA_WIDTH))
    data_recieve(.clk(clk), .rst(rst), 
                 .is_addr(1'b0), .bus(wd_if.receive_bus));
    axi_transmit #(.BUS_WIDTH(`WD_BUS_WIDTH), .DATA_WIDTH(`WD_DATA_WIDTH))
    wd_transmit(.clk(clk), .rst(rst), .bus(wd_if.transmit_bus));

    assign wd_if.dev_rdy = 1; 
    always begin
        #5;  
        clk = !clk;
    end

    initial begin
        $dumpfile("intf_tb.vcd");
        $dumpvars(0,intf_tb); 
        clk = 1;
        rst = 0;
        #100;
        `flash_sig(rst); 
        #100;
        wd_if.data_to_send = 16'hBEEF; 
        `flash_sig(wd_if.send); 
        #5000
        $finish;
    end 

endmodule 



`default_nettype wire
