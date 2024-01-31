module oscillate_sig #(parameter DELAY = 20)(input logic clk, rst, long_on, output logic osc_sig_out);
    logic osc_sig; 
    logic[$clog2(DELAY)-1:0] timer; 

    assign osc_sig_out = (long_on)? osc_sig : ~osc_sig; 
    always_ff @(posedge clk) begin
        if (rst) {timer, osc_sig} <= 1;
        else begin
            if (osc_sig) begin
                if (timer == DELAY) begin 
                    timer <= 0;
                    osc_sig <= 0; 
                end 
                else timer <= timer + 1;
            end else osc_sig <= 1; 
        end
    end
endmodule 