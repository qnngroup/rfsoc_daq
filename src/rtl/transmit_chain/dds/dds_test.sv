// dds_test.sv - Reed Foster
// Check that DDS module is generating the correct sinusoidal data in steady
// state by comparing the output with a golden model based on systemverilog
// $cos() on real numbers. That is, the golden model keeps its own phase
// variable in increments it between each sample in the output stream,
// verifying that the output stream values are the correct cos(phase) quantity
// ***NOTE***
// Does not verify correct behavior of phase-transients, but this should be
// straightforward to implement by tracking the latency from changing the
// phase_inc configuration to the observable output frequency change

`timescale 1ns / 1ps
module dds_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT); // printing, error tracking

localparam PHASE_BITS = 24;
localparam SAMPLE_WIDTH = 16;
localparam QUANT_BITS = 8;
localparam PARALLEL_SAMPLES = 4;
localparam CHANNELS = 8;

localparam LUT_ADDR_BITS = PHASE_BITS - QUANT_BITS;
localparam LUT_DEPTH = 2**LUT_ADDR_BITS;

typedef logic signed [SAMPLE_WIDTH-1:0] sample_t;
typedef logic [PHASE_BITS-1:0] phase_t;
typedef logic [CHANNELS-1:0][PHASE_BITS-1:0] multi_phase_t;

sim_util_pkg::math #(sample_t) math; // abs, max functions on sample_t

logic reset;
logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

Axis_If #(.DWIDTH(CHANNELS*PHASE_BITS)) phase_inc_in();
Realtime_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) data_out();

dds_tb #(
  .PHASE_BITS(PHASE_BITS),
  .QUANT_BITS(QUANT_BITS),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) tb_i (
  .clk,
  .phase_inc_in,
  .data_out
);

dds #(
  .PHASE_BITS(PHASE_BITS),
  .QUANT_BITS(QUANT_BITS),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) dut_i (
  .clk,
  .reset,
  .data_out,
  .phase_inc_in
);

// test data at a few different frequencies
int freqs [CHANNELS] = {
  12_130_000,
  517_036_000,
  1_729_725_000,
  2_759_000,
  123_980,
  1_429_146_012,
  9_856_492,
  923_686_610
};

initial begin
  debug.display("### TESTING DDS SIGNAL GENERATOR ###", sim_util_pkg::DEFAULT);
  reset <= 1'b1;
  repeat (50) @(posedge clk);
  reset <= 1'b0;
  repeat (20) @(posedge clk);
  for (int i = 0; i < 10; i++) begin
    freqs.shuffle();
    tb_i.set_phases(debug, freqs);
    repeat (5) @(posedge clk);
    tb_i.clear_queues();
    repeat (1000) @(posedge clk);
    tb_i.check_output(debug, 16'h0007);
  end
  debug.finish();
end

endmodule
