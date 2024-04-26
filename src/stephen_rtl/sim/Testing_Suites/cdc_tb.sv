`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module cdc_tb();

//     Axis_IF #(.DWIDTH(8)) f2s_src ();
//     Axis_IF #(.DWIDTH(8)) f2s_dest ();

//     data_CDC #(
//       .DATA_WIDTH(8)
//     ) dut_f2s_i (
//       .src_clk(clk2),
//       .src_reset(rst2),
//       .dest_clk(clk1),
//       .dest_reset(rst1),
//       .src(f2s_src),
//       .dest(f2s_dest)
//     );
// logic b;
// always @(posedge clk2) begin
//     if (rst2) begin 
//         f2s_src.data <= 15;
//         b <= 1; 
//     end 
//     else begin
//         if (b) begin
//             f2s_src.valid <= 1;
//             f2s_src.last <= 1;
//             if (f2s_src.ok) begin
//                 f2s_src.valid <= 0;
//                 f2s_src.last <= 0;
//                 b  <= 0;
//             end
//         end 
//     end
// end

    localparam DATA_WIDTH = 32;
    logic clk1, clk2, rst1, rst2; 
    logic[DATA_WIDTH-1:0] data_in1,data_out1,data_in2,data_out2;
    logic[8:0] timer; 
    logic valid_in1, valid_out1, valid_in2,valid_out2; 
    logic rdy1,done1,rdy2,done2;
    enum logic {SEND_SLOW,SLOW_WAIT} slowState;
    enum logic {SEND_FAST,FAST_WAIT} fastState;

    data_handshake #(.DATA_WIDTH(DATA_WIDTH))
                 DUT1(.clk_src(clk1), .clk_dst(clk2), .rst_src(rst1), .rst_dst(rst2),
                      .data_in(data_in1),.valid_in(valid_in1),
                      .data_out(data_out1), .valid_out(valid_out1),
                      .rdy(rdy1), .done(done1));

    data_handshake #(.DATA_WIDTH(DATA_WIDTH))
                 DUT2(.clk_src(clk2), .clk_dst(clk1), .rst_src(rst2), .rst_dst(rst1),
                      .data_in(data_in2),.valid_in(valid_in2),
                      .data_out(data_out2), .valid_out(valid_out2),
                      .rdy(rdy2), .done(done2));


    always_ff @(posedge clk1) begin
        if (rst1) begin
            {valid_in1,timer} <= 0;
            data_in1 <= 420;
            slowState <= SEND_SLOW;
        end 
        else begin
            case(slowState)
                SEND_SLOW: begin 
                    if (rdy1) begin
                        data_in1 <= data_in1 + 10; 
                        valid_in1 <= 1; 
                        slowState <= SLOW_WAIT;
                    end 
                end 
                SLOW_WAIT: begin
                    valid_in1 <= 0;
                    if (done1) slowState <= SEND_SLOW;
                end 
            endcase 
        end
    end

    always_ff @(posedge clk2) begin
        if (rst2) begin
            valid_in2 <= 0;
            data_in2 <= 1100;
            fastState <= SEND_FAST;
        end 
        else begin
            case(fastState)
                SEND_FAST: begin 
                    if (rdy2) begin
                        data_in2 <= data_in2 - 10; 
                        valid_in2 <= 1; 
                        fastState <= FAST_WAIT;
                    end 
                end 
                FAST_WAIT: begin
                        valid_in2 <= 0;
                    if (done2) fastState <= SEND_FAST;
                        
                end 
            endcase 
        end
    end

    always begin
        #3.333333;  
        clk1 = !clk1;
    end
    always begin
        #1.3020833;  
        clk2 = !clk2;
    end

    initial begin
        $dumpfile("cdc_tb.vcd");
        $dumpvars(0,cdc_tb); 
        clk1 = 1;
        clk2 = 1; 
        rst1 = 0;
        rst2 = 0;
        #10;
        `flash_sig(rst2);
        #10;
        `flash_sig(rst1);
        #10000;
        $finish;
    end 

endmodule 

`default_nettype wire
