`timescale 1ns / 1ps
`default_nettype none

module bram_test_top(input wire clk,rst,
                     input wire nxt,
                     output logic rdy, 
                     output logic[31:0] bram_out);
    localparam BRAM_DEPTH = 50; 
    logic[31:0] line_in;
    logic[$clog2(BRAM_DEPTH)-1:0] addr; 
    logic we;
    logic[31:0] bram_out2;
    logic test;
    enum logic {SAVE_LINES, READ_LINES} bramState;

    BRAM #(
    .DATA_WIDTH(32),                       
    .BRAM_DEPTH(BRAM_DEPTH)
    ) test_bram (
    .addra(addr),  
    .dina(line_in),    
    .clka(clk),    
    .wea(we),      
    .ena(1'b1),      
    .rsta(rst),    
    .regcea(1'b1),
    .douta(bram_out)  
  );

    // BRAM #(.DATA_WIDTH(32), .BRAM_DEPTH(BRAM_DEPTH), .BRAM_DELAY(3))
    // test_bram(.clk(clk),
    //           .addr(addr),
    //           .line_in(line_in),
    //           .we(we),.en(1'b1),
    //           .regen(1'b1),
    //           .line_out(bram_out2));

    // TEST_BRAM 
    // TESTB (.clka(clk),       
    //        .addra(addr), .dina(line_in),       
    //        .wea(we), .ena(1'b1), 
    //        .regcea(1'b1),        
    //        .douta(bram_out));

    assign test = bram_out == bram_out2;
    always_ff @(posedge clk) begin
        if (rst) begin 
            {addr,rdy,we} <= 1;
            line_in <= 100; 
            bramState <= SAVE_LINES;
        end else begin
            case(bramState)
                SAVE_LINES: begin
                    if (addr == BRAM_DEPTH-1) begin
                        addr <= 0;
                        we <= 0;
                        rdy <= 1;  
                        bramState <= READ_LINES; 
                    end else begin
                        addr <= addr + 1; 
                        line_in <= line_in + 1;
                    end 
                end 
                READ_LINES: begin
                    if (nxt) addr <= (addr == BRAM_DEPTH-1)? 0 : addr + 1; 
                end 
            endcase 
        end
    end                       
                       
endmodule 

`default_nettype wire