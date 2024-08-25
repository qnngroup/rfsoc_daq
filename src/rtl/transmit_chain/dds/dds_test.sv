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
localparam QUANT_BITS = 8;

logic ps_reset;
logic ps_clk = 0;
localparam int PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

logic dac_reset;
logic dac_clk = 0;
localparam int DAC_CLK_RATE_HZ = 384_000_000;
always #(0.5s/DAC_CLK_RATE_HZ) dac_clk = ~dac_clk;

Axis_If #(.DWIDTH(tx_pkg::CHANNELS*PHASE_BITS)) ps_phase_inc();
Realtime_Parallel_If #(.DWIDTH(tx_pkg::DATA_WIDTH), .CHANNELS(tx_pkg::CHANNELS)) dac_data_out();

dds_tb #(
  .PHASE_BITS(PHASE_BITS),
  .QUANT_BITS(QUANT_BITS)
) tb_i (
  .ps_clk,
  .ps_phase_inc,
  .dac_clk,
  .dac_data_out
);

dds #(
  .PHASE_BITS(PHASE_BITS),
  .QUANT_BITS(QUANT_BITS)
) dut_i (
  .ps_clk,
  .ps_reset,
  .ps_phase_inc,
  .dac_clk,
  .dac_reset,
  .dac_data_out
);

// test data at a few different frequencies
int freqs [tx_pkg::CHANNELS] = {
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
  ps_reset <= 1'b1;
  dac_reset <= 1'b1;
  tb_i.init();
  repeat (50) @(posedge ps_clk);
  ps_reset <= 1'b0;
  @(posedge dac_clk);
  dac_reset <= 1'b0;
  repeat (5) @(posedge ps_clk);
  for (int i = 0; i < 10; i++) begin
    freqs.shuffle();
    tb_i.set_phases(debug, freqs);
    repeat (5) @(posedge ps_clk);
    tb_i.clear_queues();
    // need a lot of samples to make sure we get a full period of the lowest frequency
    repeat (20000) @(posedge dac_clk);
    tb_i.check_output(debug, 16'h0007);
  end
  debug.finish();
end

endmodule
