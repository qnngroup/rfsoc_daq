// triangle_test.sv - Reed Foster
// Test triangle wave generator

`timescale 1ns/1ps

module triangle_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT);

logic dac_reset;
logic dac_clk = 0;
localparam int DAC_CLK_RATE_HZ = 384_000_000;
always #(0.5s/DAC_CLK_RATE_HZ) dac_clk = ~dac_clk;

logic ps_reset;
logic ps_clk = 0;
localparam int PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

parameter int PHASE_BITS = 32;
parameter int CHANNELS = 8;
parameter int PARALLEL_SAMPLES = 4;
parameter int SAMPLE_WIDTH = 16;

Axis_If #(.DWIDTH(PHASE_BITS*CHANNELS)) ps_phase_inc ();
Realtime_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_data_out ();
logic [CHANNELS-1:0] dac_trigger;

triangle #(
  .PHASE_BITS(PHASE_BITS),
  .CHANNELS(CHANNELS),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH)
) dut_i (
  .ps_clk,
  .ps_reset,
  .ps_phase_inc,
  .dac_clk,
  .dac_reset,
  .dac_data_out,
  .dac_trigger
);

triangle_tb #(
  .PHASE_BITS(PHASE_BITS),
  .CHANNELS(CHANNELS),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH)
) tb_i (
  .ps_clk,
  .ps_phase_inc,
  .dac_clk,
  .dac_trigger,
  .dac_data_out
);

logic [CHANNELS-1:0][PHASE_BITS-1:0] phase_increment;

initial begin
  debug.display("### TESTING TRIANGLE WAVE GENERATOR ###", sim_util_pkg::DEFAULT);
  ps_reset <= 1'b1;
  dac_reset <= 1'b1;
  tb_i.init();
  repeat (100) @(posedge ps_clk);
  ps_reset <= 1'b0;
  @(posedge dac_clk);
  dac_reset <= 1'b0;
  @(posedge ps_clk);
  // send some data
  repeat (10) begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      phase_increment[channel] = $urandom() >> 8;
    end
    tb_i.set_phases(debug, phase_increment);
    repeat (20) @(posedge dac_clk);
    tb_i.clear_queues();
    // capture some data
    repeat (1000) @(posedge dac_clk);
    tb_i.check_results(debug, phase_increment);
  end
  debug.finish();
end

endmodule
