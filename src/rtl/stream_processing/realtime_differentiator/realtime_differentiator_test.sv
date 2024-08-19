// realtime_differentiator_test.sv - Reed Foster
// tests that the output of the axis differentiator module is correct by
// comparing with a behavioral model (implemented with real subtraction in
// systemverilog)

`timescale 1ns / 1ps
module realtime_differentiator_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT); // printing, error tracking

localparam int SAMPLE_WIDTH = 16;
localparam int PARALLEL_SAMPLES = 2;
localparam int CHANNELS = 4;

logic reset;
logic clk = 0;
localparam int CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

Realtime_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) data_out ();
Realtime_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) data_in ();

realtime_differentiator #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) dut_i (
  .clk,
  .reset,
  .data_in,
  .data_out
);

realtime_differentiator_tb #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) tb_i (
  .clk,
  .reset,
  .data_in,
  .data_out
);

initial begin
  debug.display("### TESTING REALTIME DIFFERENTIATOR ###", sim_util_pkg::DEFAULT);
  repeat (10) begin
    tb_i.init();
    reset <= 1'b1;
    repeat (100) @(posedge clk);
    reset <= 1'b0;
    repeat (10) @(posedge clk);
    tb_i.send_data();
    repeat (10) @(posedge clk);
    debug.display("checking data", sim_util_pkg::VERBOSE);
    tb_i.check_output(debug);
    tb_i.clear_queues();
  end
  debug.finish();
end

endmodule
