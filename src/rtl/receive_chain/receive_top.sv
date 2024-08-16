// receive_top.sv - Reed Foster
// toplevel for receive signal chain, takes in data from physical ADC channels
// and provides a DMA interface for readout of data saved in sample buffers

`timescale 1ns/1ps
module receive_top #(
  parameter int DISCRIMINATOR_MAX_DELAY, // 64 -> 128 ns @ 512 MHz
  parameter int BUFFER_READ_LATENCY, // 4 -> permit UltraRAM inference
  parameter int AXI_MM_WIDTH // 128
) (
  /////////////////////////////////
  // ADC clock, reset (512 MHz)
  /////////////////////////////////
  input logic adc_clk, adc_reset,
  // Data
  Realtime_Parallel_If.Slave adc_data_in,
  // Realtime inputs
  input logic [tx_pkg::CHANNELS-1:0] adc_digital_triggers,

  /////////////////////////////////
  // PS clock, reset (100 MHz)
  /////////////////////////////////
  input logic ps_clk, ps_reset,
  // DMA data
  Axis_If.Master ps_readout_data,
  // Buffer status registers
  Axis_If.Master ps_samples_write_depth,
  Axis_If.Master ps_timestamps_write_depth,
  // Buffer configuration registers
  Axis_If.Slave ps_capture_arm_start_stop,
  Axis_If.Slave ps_capture_banking_mode,
  Axis_If.Slave ps_capture_sw_reset,
  Axis_If.Slave ps_readout_sw_reset,
  Axis_If.Slave ps_readout_start,

  // Discriminator configuration registers
  Axis_If.Slave ps_discriminator_thresholds,
  Axis_If.Slave ps_discriminator_delays,
  Axis_If.Slave ps_discriminator_trigger_select,
  Axis_If.Slave ps_discriminator_bypass,
  // Channel mux configuration registers
  Axis_If.Slave ps_channel_mux_config,
  // Trigger manager configuration registers
  Axis_If.Slave ps_capture_digital_trigger_select
);

// CDC ps_capture_digital_trigger_select
Axis_If #(.DWIDTH(1+tx_pkg::CHANNELS)) adc_capture_digital_trigger_select_sync ();
axis_config_reg_cdc #(
  .DWIDTH(1+tx_pkg::CHANNELS)
) cdc_digital_trigger_select_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_capture_digital_trigger_select),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_capture_digital_trigger_select_sync)
);
logic adc_capture_trigger;
trigger_manager #(
  .CHANNELS(tx_pkg::CHANNELS)
) trigger_manager_i (
  .clk(adc_clk),
  .reset(adc_reset),
  .triggers_in(adc_digital_triggers),
  .trigger_config(adc_capture_digital_trigger_select_sync),
  .trigger_out(adc_capture_trigger)
);

//////////////////////////////////////////////////////////////////////////
// RFADC clock domain (512MHz)
//////////////////////////////////////////////////////////////////////////

// multiplexer takes in physical ADC channels + differentiator outputs and
// produces logical channels
Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_ddt ();
Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(2*rx_pkg::CHANNELS)) adc_mux_input ();
Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_mux_output ();
// connect physical ADC channels and differentiator to mux input
always_ff @(posedge adc_clk) begin
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    adc_mux_input.data[channel] <= adc_data_in.data[channel];
    adc_mux_input.valid[channel] <= adc_data_in.valid[channel];
    adc_mux_input.data[channel+rx_pkg::CHANNELS] <= adc_ddt.data[channel];
    adc_mux_input.valid[channel+rx_pkg::CHANNELS] <= adc_ddt.valid[channel];
  end
end
// mux
axis_channel_mux #(
  .INPUT_CHANNELS(2*rx_pkg::CHANNELS),
  .OUTPUT_CHANNELS(rx_pkg::CHANNELS)
) channel_mux_i (
  .data_clk(adc_clk),
  .data_reset(adc_reset),
  .data_in(adc_mux_input),
  .data_out(adc_mux_output),
  .config_clk(ps_clk),
  .config_reset(ps_reset),
  .config_in(ps_channel_mux_config)
);

// differentiator
realtime_differentiator #(
  .SAMPLE_WIDTH(rx_pkg::SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(rx_pkg::PARALLEL_SAMPLES),
  .CHANNELS(rx_pkg::CHANNELS)
) differentiator_i (
  .clk(adc_clk),
  .reset(adc_reset),
  .data_in(adc_data_in),
  .data_out(adc_ddt)
);

// discriminator
Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_discriminator_samples ();
Realtime_Parallel_If #(.DWIDTH(buffer_pkg::TSTAMP_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_discriminator_timestamps ();
logic adc_discriminator_reset;
sample_discriminator #(
  .MAX_DELAY_CYCLES(DISCRIMINATOR_MAX_DELAY)
) discriminator_i (
  .adc_clk,
  .adc_reset,
  .adc_data_in(adc_mux_output),
  .adc_samples_out(adc_discriminator_samples),
  .adc_timestamps_out(adc_discriminator_timestamps),
  .adc_reset_state(adc_discriminator_reset),
  .adc_digital_trigger_in(adc_digital_triggers),
  .ps_clk,
  .ps_reset,
  .ps_thresholds(ps_discriminator_thresholds),
  .ps_delays(ps_discriminator_delays),
  .ps_trigger_select(ps_discriminator_trigger_select),
  .ps_bypass(ps_discriminator_bypass)
);

// timetagging buffer
timetagging_sample_buffer #(
  .BUFFER_READ_LATENCY(BUFFER_READ_LATENCY),
  .AXI_MM_WIDTH(AXI_MM_WIDTH)
) buffer_i (
  .adc_clk,
  .adc_reset,
  .adc_samples_in(adc_discriminator_samples),
  .adc_timestamps_in(adc_discriminator_timestamps),
  .adc_digital_trigger(adc_capture_trigger),
  .adc_discriminator_reset(adc_discriminator_reset),
  .ps_clk,
  .ps_reset,
  .ps_readout_data,
  .ps_samples_write_depth,
  .ps_timestamps_write_depth,
  .ps_capture_arm_start_stop,
  .ps_capture_banking_mode,
  .ps_capture_sw_reset,
  .ps_readout_sw_reset,
  .ps_readout_start
);

endmodule
