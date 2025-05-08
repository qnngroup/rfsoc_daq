`default_nettype none
`timescale 1ns / 1ps

module ex_test();
    localparam int PS_CLK_RATE_MHZ = 384;
    localparam int DAC_CLK_RATE_MHZ = 150;

    logic ps_clk, dac_clk;
    logic ps_rst, dac_rst; 

    pulse_CDC
    rst_CDC(.src_clk(ps_clk), .dst_clk(dac_clk),
            .signal_in(ps_rst), .signal_out(dac_rst));

    always #(0.5s/(PS_CLK_RATE_MHZ*1_000_000)) ps_clk = ~ps_clk;
    always #(0.5s/(DAC_CLK_RATE_MHZ*1_000_000)) dac_clk = ~dac_clk;

    initial begin
        $dumpfile("ex_test.vcd");
        $dumpvars(0,ex_test); 
        {ps_clk, dac_clk} = 0;
        ps_rst = 0;
        #100;
        for (int i = 0; i < 10; i++) begin
            ps_rst = 1;
            repeat ($urandom_range(0, 300)) @(posedge ps_clk);
            ps_rst = 0;
            #500;
        end 
        #5000;
        $finish;
    end 

endmodule 



`default_nettype wire
