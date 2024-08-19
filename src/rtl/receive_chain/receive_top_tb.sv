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

localparam int TIMER_BITS = $clog2(DISCRIMINATOR_MAX_DELAY);

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
    phase_inc_data[channel*32+:32] = {channel + 1, 22'b0};
  end
  set_tri_phase_inc(debug, phase_inc_data);
endtask

task automatic setup_channel_mux (
  inout sim_util_pkg::debug debug
);
  logic [rx_pkg::CHANNELS-1:0][$clog2(2*rx_pkg::CHANNELS)-1:0] mux_channel_select;
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    if (channel % 2 == 0) begin
      mux_channel_select[channel] = (channel >> 1);
    end else begin
      mux_channel_select[channel] = rx_pkg::CHANNELS + (channel >> 1);
    end
  end
  set_mux_config(debug, mux_channel_select);
endtask

task automatic setup_sample_discriminator (
  inout sim_util_pkg::debug debug
);
  logic [rx_pkg::CHANNELS-1:0][rx_pkg::SAMPLE_WIDTH-1:0] low_thresholds, high_thresholds;
  logic [rx_pkg::CHANNELS-1:0] bypassed_channel_mask;
  logic [rx_pkg::CHANNELS-1:0][$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS)-1:0] trigger_sources;
  logic [rx_pkg::CHANNELS-1:0][TIMER_BITS-1:0] start_delays, stop_delays, digital_delays;
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    case (channel)
      0: begin
        // always save samples (continuously trigger)
        low_thresholds[channel] = rx_pkg::MIN_SAMP;
        high_thresholds[channel] = rx_pkg::MIN_SAMP;
        // save triangle data, but using trigger from 1 (will only save upward slope + tails)
        trigger_sources[channel] = 1;
        // don't bypass
        bypassed_channel_mask[channel] = 1'b0;
        // channel 1 only sends trigger signal; need to match delays
        start_delays[channel] = 5;
        stop_delays[channel] = 5;
      end
      1: begin
        // only save if > 0 (since channel is ddt, this should give us only
        // rising edges; however add a few stop/start delay cycles to get some
        // tails)
        low_thresholds[channel] = 0;
        high_thresholds[channel] = 0;
        // save ddt data, but using trigger from channel 0 (will save everything)
        trigger_sources[channel] = 1;
        // don't bypass
        bypassed_channel_mask[channel] = 1'b0;
        // delays
        start_delays[channel] = 5;
        stop_delays[channel] = 5;
      end
      2: begin
        // save everything (should get a nice, un-chopped triangle wave at a different freq)
        low_thresholds[channel] = rx_pkg::MIN_SAMP;
        high_thresholds[channel] = rx_pkg::MIN_SAMP;
        // just save triangle wave
        trigger_sources[channel] = 2;
        // don't bypass
        bypassed_channel_mask[channel] = 1'b0;
        // delays are kind of a don't care here
        start_delays[channel] = 0;
        stop_delays[channel] = 0;
      end
      3: begin
        // don't care, since it's bypassed
        low_thresholds[channel] = 0;
        high_thresholds[channel] = 0;
        // don't care, since it's bypassed
        trigger_sources[channel] = 0;
        // 3 is bypassed
        bypassed_channel_mask[channel] = 1'b1;
        // don't care, since it's bypassed
        start_delays[channel] = 0;
        stop_delays[channel] = 0;
      end
      default: begin
        low_thresholds[channel] = rx_pkg::MAX_SAMP;
        high_thresholds[channel] = rx_pkg::MAX_SAMP;
        // sources
        trigger_sources[channel] = channel;
        // don't bypass
        bypassed_channel_mask[channel] = 1'b0;
        // don't care
        start_delays[channel] = 0;
        stop_delays[channel] = 0;
      end
    endcase
    digital_delays[channel] = 0;
  end
  discriminator_tb_i.set_thresholds(debug, low_thresholds, high_thresholds);
  discriminator_tb_i.set_trigger_sources(debug, trigger_sources);
  discriminator_tb_i.set_bypassed_channels(debug, bypassed_channel_mask);
  discriminator_tb_i.set_delays(debug, start_delays, stop_delays, digital_delays);
endtask

task automatic clear_queues ();
  buffer_tb_i.ps_samples_write_depth_rx_i.clear_queues();
  buffer_tb_i.ps_timestamps_write_depth_rx_i.clear_queues();
  buffer_tb_i.ps_readout_data_rx_i.clear_queues();
endtask

task automatic check_output (
  inout sim_util_pkg::debug debug,
  input int active_channels
);
  // get received data
  buffer_pkg::tstamp_t readout_timestamps_q [rx_pkg::CHANNELS][$];
  rx_pkg::batch_t readout_samples_q [rx_pkg::CHANNELS][$];
  rx_pkg::sample_t sample_q [$];
  int event_time;
  int durations_q [$];
  rx_pkg::sample_t slopes_q [$];
  rx_pkg::sample_t slope;
  logic [3:0][31:0] expected_falling_durations = {256, 256, 88, 88};
  logic [3:0][31:0] expected_rising_durations = {256, 256, 512, 512};
  sim_util_pkg::queue #(.T(rx_pkg::sample_t), .T2(rx_pkg::batch_t)) sample_q_util = new();
  // get output
  buffer_tb_i.parse_readout_data(debug, active_channels, readout_timestamps_q, readout_samples_q);

  debug.display("checking output", sim_util_pkg::DEBUG);
  // expected
  // 0: rising ramp with 5-cycle-long tails
  // 1: square wave
  // 2: triangle wave
  // 3: square wave
  // 4-7: empty
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    // convert to queue of individual samples instead of words
    sample_q_util.samples_from_batches(
      readout_samples_q[channel],
      sample_q,
      rx_pkg::SAMPLE_WIDTH,
      rx_pkg::PARALLEL_SAMPLES
    );
    debug.display($sformatf("channel %0d data: %0p", channel, sample_q), sim_util_pkg::DEBUG);
    event_time = -1;
    durations_q.delete();
    slopes_q.delete();
    case (channel)
      0,2: begin
        slope = -1;
        for (int i = sample_q.size() - 1; i >= 1; i--) begin
          if ((sample_q[i-1] - sample_q[i])*slope < 0) begin
            slope = sample_q[i-1] - sample_q[i];
            durations_q.push_front(event_time - i);
            slopes_q.push_front(slope);
            event_time = i;
          end
        end
      end
      1,3: begin
        slope = -1;
        for (int i = sample_q.size() - 1; i >= 0; i--) begin
          if (((sample_q[i] > 0) && (slope < 0)) || ((sample_q[i] < 0) && (slope > 0))) begin
            slope = (sample_q[i] > 0) ? 1 : -1;
            durations_q.push_front(event_time - i);
            slopes_q.push_front(slope);
            event_time = i;
          end
        end
      end
      default: begin
        if (readout_timestamps_q[channel].size() > 0) begin
          debug.error($sformatf(
            "expected 0 timestamps for channel %0d, but got %0d",
            channel,
            readout_timestamps_q[channel].size())
          );
        end
        if (readout_samples_q[channel].size() > 0) begin
          debug.error($sformatf(
            "expected 0 samples for channel %0d, but got %0d",
            channel,
            readout_samples_q[channel].size())
          );
        end
      end
    endcase
    if (channel < 4) begin
      debug.display($sformatf("durations_q = %0p", durations_q), sim_util_pkg::DEBUG);
      debug.display($sformatf("slopes_q = %0p", slopes_q), sim_util_pkg::DEBUG);
      // first two will be garbage
      repeat (2) begin
        durations_q.pop_back();
        slopes_q.pop_back();
      end
      for (int i = durations_q.size() - 1; i >= 0; i--) begin
        if (slopes_q[i] > 0) begin
          if (durations_q[i] !== expected_falling_durations[channel]) begin
            debug.error($sformatf(
              "channel %0d: falling edge had wrong duration, expected %0d samples got %0d",
              channel,
              expected_falling_durations[channel],
              durations_q[i])
            );
          end
        end else begin
          if (durations_q[i] !== expected_rising_durations[channel]) begin
            debug.error($sformatf(
              "channel %0d: rising edge had wrong duration, expected %0d samples got %0d",
              channel,
              expected_rising_durations[channel],
              durations_q[i])
            );
          end
        end
      end
    end
  end
  
endtask

endmodule
