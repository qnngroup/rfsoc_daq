// sample_discriminator_tb.sv - Reed Foster
// utilities for verification of sample discriminator
// Tasks to drive configuration inputs of DUT
// Tasks to verify DUT response

`timescale 1ns/1ps
module sample_discriminator_tb #(
  parameter int MAX_DELAY_CYCLES = 64
) (
  input logic adc_clk,
  input logic adc_reset,
  Realtime_Parallel_If.Master adc_data_in,
  Realtime_Parallel_If.Slave adc_data_out,
  Realtime_Parallel_If.Slave adc_timestamps_out,

  input logic ps_clk,
  Axis_If.Master ps_thresholds,
  Axis_If.Master ps_delays,
  Axis_If.Master ps_trigger_select,
  Axis_If.Master ps_disable_discriminator
);

localparam int TIMER_BITS = $clog2(MAX_DELAY_CYCLES);

axis_driver #(
  .DWIDTH(2*rx_pkg::CHANNELS*rx_pkg::SAMPLE_WIDTH)
) ps_thresholds_tx_i (
  .clk(ps_clk),
  .intf(ps_thresholds)
);

axis_driver #(
  .DWIDTH(3*rx_pkg::CHANNELS*TIMER_BITS)
) ps_delays_tx_i (
  .clk(ps_clk),
  .intf(ps_delays)
);

axis_driver #(
  .DWIDTH(rx_pkg::CHANNELS*$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS))
) ps_trigger_select_tx_i (
  .clk(ps_clk),
  .intf(ps_trigger_select)
);

axis_driver #(
  .DWIDTH(rx_pkg::CHANNELS)
) ps_disable_discriminator_tx_i (
  .clk(ps_clk),
  .intf(ps_disable_discriminator)
);

logic adc_send_samples, adc_driver_enabled;
int adc_send_samples_decimation, adc_send_samples_counter;

always @(posedge adc_clk) begin
  if (adc_send_samples_counter == adc_send_samples_decimation - 1) begin
    adc_send_samples_counter <= 0;
    adc_driver_enabled <= adc_send_samples;
  end else begin
    adc_send_samples_counter <= adc_send_samples_counter + 1;
    adc_driver_enabled <= 1'b0;
  end
end

realtime_parallel_driver_constrained #(
  .DWIDTH(rx_pkg::DATA_WIDTH),
  .CHANNELS(rx_pkg::CHANNELS),
  .SAMPLE_WIDTH(rx_pkg::SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(rx_pkg::PARALLEL_SAMPLES)
) adc_data_in_tx_i (
  .clk(adc_clk),
  .reset(adc_reset),
  .valid_rand('0),
  .valid_en({rx_pkg::CHANNELS{adc_driver_enabled}}),
  .intf(adc_data_in)
);

realtime_parallel_receiver #(
  .DWIDTH(rx_pkg::DATA_WIDTH),
  .CHANNELS(rx_pkg::CHANNELS)
) adc_data_out_rx_i (
  .clk(adc_clk),
  .intf(adc_data_out)
);

realtime_parallel_receiver #(
  .DWIDTH(buffer_pkg::TSTAMP_WIDTH),
  .CHANNELS(rx_pkg::CHANNELS)
) adc_timestamps_out_rx_i (
  .clk(adc_clk),
  .intf(adc_timestamps_out)
);

task automatic init ();
  ps_thresholds_tx_i.init();
  ps_delays_tx_i.init();
  ps_trigger_select_tx_i.init();
  ps_disable_discriminator_tx_i.init();
  disable_send();
  adc_send_samples_decimation <= 1;
  adc_send_samples_counter <= 0;
endtask

task automatic enable_send ();
  adc_send_samples <= 1'b1;
endtask

task automatic disable_send ();
  adc_send_samples <= 1'b0;
endtask

task automatic set_decimation (
  input int decimation
);
  adc_send_samples_decimation <= decimation;
endtask

task automatic set_input_range (
  input rx_pkg::sample_t min,
  input rx_pkg::sample_t max
);
  adc_data_in_tx_i.set_data_range(min, max);
endtask

task automatic set_thresholds (
  inout sim_util_pkg::debug debug,
  input logic [rx_pkg::CHANNELS-1:0][rx_pkg::SAMPLE_WIDTH-1:0] low_thresholds,
  input logic [rx_pkg::CHANNELS-1:0][rx_pkg::SAMPLE_WIDTH-1:0] high_thresholds
);
  logic success;
  logic [rx_pkg::CHANNELS-1:0][2*rx_pkg::SAMPLE_WIDTH-1:0] threshold_word;
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    threshold_word[channel] = {high_thresholds[channel], low_thresholds[channel]};
  end
  ps_thresholds_tx_i.send_sample_with_timeout(10, threshold_word, success);
  if (~success) begin
    debug.error("failed to set thresholds");
  end
endtask

task automatic set_delays (
  inout sim_util_pkg::debug debug,
  input logic [rx_pkg::CHANNELS-1:0][TIMER_BITS-1:0] start_delays,
  input logic [rx_pkg::CHANNELS-1:0][TIMER_BITS-1:0] stop_delays,
  input logic [rx_pkg::CHANNELS-1:0][TIMER_BITS-1:0] digital_delays
);
  logic success;
  logic [rx_pkg::CHANNELS-1:0][3*TIMER_BITS-1:0] delay_word;
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    delay_word[channel] = {digital_delays[channel], stop_delays[channel], start_delays[channel]};
  end
  ps_delays_tx_i.send_sample_with_timeout(10, delay_word, success);
  if (~success) begin
    debug.error("failed to set delays");
  end
endtask

task automatic set_trigger_sources(
  inout sim_util_pkg::debug debug,
  input logic [rx_pkg::CHANNELS-1:0][$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS)-1:0] sources
);
  logic success;
  ps_trigger_select_tx_i.send_sample_with_timeout(10, sources, success);
  if (~success) begin
    debug.error("failed to set delays");
  end
endtask

task automatic set_discrimination_channels(
  inout sim_util_pkg::debug debug,
  input logic [rx_pkg::CHANNELS-1:0] disabled_mask
);
  logic success;
  ps_disable_discriminator_tx_i.send_sample_with_timeout(10, disabled_mask, success);
  if (~success) begin
    debug.error("failed to set disabled channels");
  end
endtask

endmodule
