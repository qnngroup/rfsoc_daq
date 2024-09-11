`default_nettype none

module edetect #(parameter DEFAULT = 0, parameter DATA_WIDTH = 1)
                (input wire clk, rst,
                 input wire[DATA_WIDTH-1:0] val,
                 output logic[1:0] comb_edge_out,
                 output logic[1:0] edge_out);
//out = 0: no change, 1: positive change, 2: negative change
logic[DATA_WIDTH-1:0] old_val;

always_comb begin
    if (rst) comb_edge_out = DEFAULT;
    else begin
        if (DATA_WIDTH == 1) begin
            if (val == old_val) comb_edge_out = 0;
            else if (val > old_val) comb_edge_out = 1;
            else if (val < old_val) comb_edge_out = 2; 
        end else begin
            if (val == old_val) comb_edge_out = 0;
            else if ($signed(val) > $signed(old_val)) comb_edge_out = 1;
            else if ($signed(val) < $signed(old_val)) comb_edge_out = 2; 
        end
    end
end
always_ff @(posedge clk) begin
    if (rst) begin
        old_val <= DEFAULT;
        edge_out <= 0;
    end else begin
        old_val <= val;
        if (DATA_WIDTH == 1) begin
            if (val == old_val) edge_out <= 0;
            else if (val > old_val) edge_out <= 1;
            else if (val < old_val) edge_out <= 2; 
        end else begin
            if (val == old_val) edge_out <= 0;
            else if ($signed(val) > $signed(old_val)) edge_out <= 1;
            else if ($signed(val) < $signed(old_val)) edge_out <= 2; 
        end
    end
end
endmodule //edge_detect

`default_nettype wire