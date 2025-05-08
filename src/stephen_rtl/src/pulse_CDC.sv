`default_nettype none
`timescale 1ns / 1ps

module pulse_CDC(input wire src_clk, dst_clk, 
                     input wire signal_in,
                     output logic signal_out);
    logic first_edge = 1; 
    logic init_pulse = 0; 
    logic signal_in_filtered;

    always_comb begin
        if (first_edge) signal_in_filtered = 0;
        else if (init_pulse) signal_in_filtered = 1;
        else signal_in_filtered = signal_in;
    end
    always_ff @(posedge src_clk) begin
        if (first_edge) begin            
            if (signal_in == 1) init_pulse <= 1; 
            if (signal_in == 0 || signal_in == 1) first_edge <= 0; //Just making sure signal_in is defined because xpm breaks otherwise
        end else begin
            if (init_pulse) init_pulse <= 0;             
        end
    end
    xpm_cdc_pulse #(
        .DEST_SYNC_FF(5),
        .RST_USED(0),
        .INIT_SYNC_FF(0)
    ) reset_pulse_cdc (
        .src_clk(src_clk),
        .src_pulse(signal_in_filtered),
        .dest_clk(dst_clk),
        .dest_pulse(signal_out));

endmodule

`default_nettype wire
