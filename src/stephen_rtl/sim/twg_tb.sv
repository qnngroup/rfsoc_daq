`default_nettype none
`timescale 1ns / 1ps

module twg_tb();

    logic[1:0][15:0] sample_pipe;
    logic[63:0][15:0] results; 
    logic signed[1:0][15:0] slope_pipe;
    logic[15:0] val; 

    always_comb begin
        for (int i = 0; i < 132; i++) begin
            if (i < 64) begin
                if (($signed(sample_pipe[1] + slope_pipe[1]*i)) == 44) begin
                    results[i] = 1000;
                end else results[i] = -1; 
                
            end
        end
    end 

    always_ff @(posedge clk) begin
        if (rst) begin 
            {sample_pipe,slope_pipe} <= 0;
            sample_pipe[0] <= 111;
            val <= 50; 
        end else begin
            sample_pipe[1] <= val; 
            slope_pipe[1] <= -3;
            // val <= val + 1; 
        end
    end
    // localparam SAMPLE_WIDTH = 16;
    // localparam BATCH_WIDTH = 48; 
    // localparam NSAMPLES = BATCH_WIDTH/SAMPLE_WIDTH; 

    logic clk,rst,run, period;
    // logic[BATCH_WIDTH-1:0] batch_out; 
    // logic[NSAMPLES-1:0][SAMPLE_WIDTH-1:0] samples;
    // int i;  

    // trig_wave_gen #(.SAMPLE_WIDTH (SAMPLE_WIDTH), .BATCH_WIDTH (BATCH_WIDTH))
    // twg(.clk(clk),
    //     .rst(rst),
    //     .run(run),
    //     .batch_out(batch_out));

    always begin
        #5;  
        clk = !clk;
    end

    // generate
    //     for (genvar i = 0; i < NSAMPLES; i++) begin: batch_splices
    //         data_splicer #(.DATA_WIDTH(BATCH_WIDTH), .SPLICE_WIDTH(SAMPLE_WIDTH))
    //         batch_splicer(.data(batch_out),
    //                       .i(int'(i)),
    //                       .spliced_data(samples[i]));
    //     end
    // endgenerate

    // enum logic {SEARCHING, FOUND} testState; 
    // logic go_again; 

    // always_ff @(posedge clk) begin
    //     if (rst) begin
    //         testState <= SEARCHING; 
    //         period <= 0; 
    //     end else begin
    //         case (testState) 
    //             SEARCHING: begin
    //                 for (int i = 0; i < NSAMPLES; i++) begin
    //                     if (samples[i] == 0) begin
    //                         period <= 1; 
    //                         testState <= FOUND; 
    //                     end 
    //                 end
    //             end 

    //             FOUND: begin 
    //                 if (period) period <= 0; 
    //                 if (go_again) testState <= SEARCHING;
    //             end 
    //         endcase 
    //     end
    // end

    initial begin
        $dumpfile("twg_tb.vcd");
        $dumpvars(0,twg_tb); 
        clk = 1;
        rst = 0;
        run = 0; 
        #10; rst = 1; #10; rst = 0; #100; 
        // #100;
        // run = 1;
        // #950000;
        // run = 0;
        #1000;
        $finish;
    end 

endmodule 

`default_nettype wire
