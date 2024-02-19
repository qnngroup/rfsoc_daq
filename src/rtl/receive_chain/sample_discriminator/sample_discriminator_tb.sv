// sample_discriminator_tb.sv - Reed Foster
// utilities for verification of sample discriminator
// Tasks to drive configuration inputs of DUT
// Tasks to verify DUT response

`timescale 1ns/1ps
module sample_discriminator_tb #(
  parameter int MAX_DELAY_CYCLES = 64
) (
  ref clk,
  Axis_If thresholds,
  Axis_If delays,
  Axis_If trigger_select,
  Axis_If disable_discriminator
);

localparam int TIMER_BITS = $clog2(MAX_DELAY_CYCLES);

task automatic set_thresholds (
  inout sim_util_pkg::debug debug,
  input [rx_pkg::CHANNELS-1:0][rx_pkg::SAMPLE_WIDTH-1:0] low_thresholds,
  input [rx_pkg::CHANNELS-1:0][rx_pkg::SAMPLE_WIDTH-1:0] high_thresholds
);
  logic success;
  logic [rx_pkg::CHANNELS-1:0][2*rx_pkg::SAMPLE_WIDTH-1:0] threshold_word;
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    threshold_word[channel] = {high_thresholds[channel], low_thresholds[channel]};
  end
  thresholds.send_sample_with_timeout(clk, threshold_word, 10, success);
  if (~success) begin
    debug.error("failed to set thresholds");
  end
endtask

task automatic set_delays (
  inout sim_util_pkg::debug debug,
  input [rx_pkg::CHANNELS-1:0][TIMER_BITS-1:0] start_delays,
  input [rx_pkg::CHANNELS-1:0][TIMER_BITS-1:0] stop_delays,
  input [rx_pkg::CHANNELS-1:0][TIMER_BITS-1:0] digital_delays
);
  logic success;
  logic [rx_pkg::CHANNELS-1:0][3*TIMER_BITS-1:0] delay_word;
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    delay_word[channel] = {digital_delays[channel], stop_delays[channel], start_delays[channel]};
  end
  delays.send_sample_with_timeout(clk, delay_word, 10, success);
  if (~success) begin
    debug.error("failed to set delays");
  end
endtask

task automatic set_trigger_sources(
  inout sim_util_pkg::debug debug,
  input [rx_pkg::CHANNELS-1:0][$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS)-1:0] sources
);
  logic success;
  trigger_select.send_sample_with_timeout(clk, sources, 10, success);
  if (~success) begin
    debug.error("failed to set delays");
  end
endtask

task automatic set_discrimination_channels(
  inout sim_util_pkg::debug debug,
  input [rx_pkg::CHANNELS-1:0] disabled_mask
);
  logic success;
  disable_discriminator.send_sample_with_timeout(clk, disabled_mask, 10, success);
  if (~success) begin
    debug.error("failed to set disabled channels");
  end
endtask

endmodule
