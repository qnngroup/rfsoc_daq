`default_nettype none

module edetect #(parameter DEFAULT = 0)
                (input wire clk, input wire rst,
                 input wire val,
                 output logic[1:0] comb_posedge_out,
                 output logic[1:0] posedge_out);
//out = 0: no change, 1: positive change, 2: negative change
logic old_val;

always_comb begin
    if (rst) comb_posedge_out = DEFAULT;
    else begin
        if (old_val != val) begin
            if (old_val) comb_posedge_out = 2;
            else comb_posedge_out = 1;
        end
        else comb_posedge_out = 0;
    end
end
always_ff @(posedge clk) begin
    if (rst) begin
        old_val <= DEFAULT;
        posedge_out <= 0;
    end else begin
        old_val <= val;
        if (old_val != val) begin
            if (old_val) posedge_out <= 2;
            else posedge_out <= 1;
        end 
        else posedge_out <= 0;
    end
end
endmodule //edge_detect

`default_nettype wire