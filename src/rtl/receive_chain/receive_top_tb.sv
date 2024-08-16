// receive_top_tb.sv - Reed Foster
// testbench for receive_top

`timescale 1ns/1ps
module receive_top_tb #(
  parameter int DISCRIMINATOR_MAX_DELAY, // 64 -> 128 ns @ 512 MHz
  parameter int BUFFER_READ_LATENCY, // 4 -> permit UltraRAM inference
  parameter int AXI_MM_WIDTH // 128
) (
  input logic adc_clk, adc_reset,
  Realtime_Parallel_If.Master adc_data_in,
  output logic [tx_pkg::CHANNELS-1:0] adc_digital_triggers,

  input logic ps_clk, ps_reset,
  Axis_If.Slave ps_readout_data,
  // Buffer status registers
  Axis_If.Slave ps_samples_write_depth,
  Axis_If.Slave ps_timestamps_write_depth,
  // Buffer configuration registers
  Axis_If.Master ps_capture_arm_start_stop,
  Axis_If.Master ps_capture_banking_mode,
  Axis_If.Master ps_capture_sw_reset,
  Axis_If.Master ps_readout_sw_reset,
  Axis_If.Master ps_readout_start,

  // Discriminator configuration registers
  Axis_If.Master ps_discriminator_thresholds,
  Axis_If.Master ps_discriminator_delays,
  Axis_If.Master ps_discriminator_trigger_select,
  Axis_If.Master ps_discriminator_bypass,
  // Channel mux configuration registers
  Axis_If.Master ps_channel_mux_config,
  // Trigger manager configuration registers
  Axis_If.Master ps_capture_digital_trigger_select
);

// generate ramp with triangle
Axis_If #(.DWIDTH(32*rx_pkg::CHANNELS)) ps_phase_inc ();
logic [(rx_pkg::CHANNELS*32)-1:0] phase_inc_data;
triangle #(
  .PHASE_BITS(32),
  .CHANNELS(rx_pkg::CHANNELS),
  .PARALLEL_SAMPLES(rx_pkg::PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(rx_pkg::SAMPLE_WIDTH)
) tri_gen (
  .ps_clk,
  .ps_reset,
  .ps_phase_inc,
  .dac_clk(adc_clk),
  .dac_reset(adc_reset),
  .dac_data_out(adc_data_in),
  .dac_trigger()
);

// sample buffer TB
// used for writing configuration regs and readout
Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_buff_sample_dummy ();
Realtime_Parallel_If #(.DWIDTH(buffer_pkg::TSTAMP_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_buff_tstamp_dummy ();
timetagging_sample_buffer_tb #(
  .AXI_MM_WIDTH(AXI_MM_WIDTH)
) buffer_tb_i (
  .adc_clk,
  .adc_reset,
  .adc_samples_in(adc_buff_sample_dummy),
  .adc_timestamps_in(adc_buff_tstamp_dummy),
  .adc_digital_trigger(1'b0),
  .adc_discriminator_reset(1'b0),
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

// discriminator TB
// just used for writing configuration regs
Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_data_dummy ();
Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_disc_sample_dummy ();
Realtime_Parallel_If #(.DWIDTH(buffer_pkg::TSTAMP_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_disc_tstamp_dummy ();
sample_discriminator_tb #(
  .MAX_DELAY_CYCLES(DISCRIMINATOR_MAX_DELAY)
) discriminator_tb_i (
  .adc_clk,
  .adc_reset,
  .adc_data_in(adc_data_dummy),
  .adc_samples_out(adc_disc_sample_dummy),
  .adc_timestamps_out(adc_disc_tstamp_dummy),
  .ps_clk,
  .ps_thresholds(ps_discriminator_thresholds),
  .ps_delays(ps_discriminator_delays),
  .ps_trigger_select(ps_discriminator_trigger_select),
  .ps_bypass(ps_discriminator_bypass),
  .trigger_sources('0)
);

// mux configuration
axis_driver #(
  .DWIDTH(rx_pkg::CHANNELS*$clog2(2*rx_pkg::CHANNELS))
) ps_channel_mux_cfg_tx_i (
  .clk(ps_clk),
  .intf(ps_channel_mux_config)
);

// triangle wave driver
axis_driver #(
  .DWIDTH(32*rx_pkg::CHANNELS)
) tri_phase_tx_i (
  .clk(ps_clk),
  .intf(ps_phase_inc)
);

// trigger manager configuration
axis_driver #(
  .DWIDTH(tx_pkg::CHANNELS+1)
) ps_trigger_mgr_cfg_tx_i (
  .clk(ps_clk),
  .intf(ps_capture_digital_trigger_select)
);

task automatic set_mux_config (
  inout sim_util_pkg::debug debug,
  logic [rx_pkg::CHANNELS*$clog2(2*rx_pkg::CHANNELS)-1:0] mux_config
);
  logic success;
  debug.display("setting mux config", sim_util_pkg::DEBUG);
  ps_channel_mux_cfg_tx_i.send_sample_with_timeout(10, mux_config, success);
  if (~success) begin
    debug.error("failed to set mux config");
  end
endtask

task automatic set_capture_trigger_cfg (
  inout sim_util_pkg::debug debug,
  logic [tx_pkg::CHANNELS:0] trigger_manager_config
);
  logic success;
  debug.display("setting trigger config", sim_util_pkg::DEBUG);
  ps_trigger_mgr_cfg_tx_i.send_sample_with_timeout(10, trigger_manager_config, success);
  if (~success) begin
    debug.error("failed to trigger config");
  end
endtask

task automatic set_tri_phase_inc (
  inout sim_util_pkg::debug debug,
  logic [32*rx_pkg::CHANNELS-1:0] phase_inc
);
  logic success;
  debug.display("setting up input data generation", sim_util_pkg::DEBUG);
  tri_phase_tx_i.send_sample_with_timeout(10, phase_inc, success);
  if (~success) begin
    debug.fatal("failed to setup input data");
  end
endtask

task automatic send_trigger (
  input logic [tx_pkg::CHANNELS-1:0] triggers
);
  @(posedge adc_clk);
  discriminator_tb_i.clear_queues();
  adc_digital_triggers <= triggers;
  @(posedge adc_clk);
  adc_digital_triggers <= '0;
endtask

task automatic init ();
  buffer_tb_i.init();
  discriminator_tb_i.init();
  ps_channel_mux_cfg_tx_i.init();
  tri_phase_tx_i.init();
  adc_digital_triggers <= '0;
endtask

task automatic setup_adc_input_gen (
  inout sim_util_pkg::debug debug
);
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    phase_inc_data[channel*32+:32] = {channel + 1, 18'b0};
  end
  set_tri_phase_inc(debug, phase_inc_data);
endtask

task automatic clear_queues ();
  buffer_tb_i.ps_samples_write_depth_rx_i.clear_queues();
  buffer_tb_i.ps_timestamps_write_depth_rx_i.clear_queues();
  buffer_tb_i.ps_readout_data_rx_i.clear_queues();
endtask

task automatic check_output (
  inout sim_util_pkg::debug debug
);
  debug.display("checking output", sim_util_pkg::DEBUG);
  rx_pkg::batch_t expected_q [rx_pkg::CHANNELS][$];
  logic [buffer_pkg::TSTAMP_WIDTH-1:0] timestamp_q [rx_pkg::CHANNELS][$];
  discriminator_tb_i.generate_expected(
    debug,
    low_thresholds,
    high_thresholds,
    start_delays,
    stop_delays,
    digital_delays,
    trigger_sources,
    bypassed_channel_mask,
    expected_q,
    timestamp_q
  );
  // get data from buffer
endtask

endmodule
