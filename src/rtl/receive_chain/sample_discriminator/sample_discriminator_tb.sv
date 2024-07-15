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
  
  output logic [tx_pkg::CHANNELS-1:0] adc_digital_trigger_in,

  input logic ps_clk,
  Axis_If.Master ps_thresholds,
  Axis_If.Master ps_delays,
  Axis_If.Master ps_trigger_select,
  Axis_If.Master ps_bypass,

  input logic [rx_pkg::CHANNELS-1:0][$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS)-1:0] trigger_sources
);

localparam int TIMER_BITS = $clog2(MAX_DELAY_CYCLES);

sim_util_pkg::queue #(.T(rx_pkg::sample_t), .T2(rx_pkg::batch_t)) sample_q_util = new;
sim_util_pkg::queue #(.T(rx_pkg::batch_t)) batch_q_util = new;
sim_util_pkg::queue #(.T(logic [buffer_pkg::TSTAMP_WIDTH-1:0])) tstamp_q_util = new;

// keep track of location of samples for which a trigger occurred
int trigger_sample_count_q [rx_pkg::CHANNELS][$];
// keep track of relative delay between trigger and data_in_valid
int trigger_delay_q [rx_pkg::CHANNELS][$];

// timer
localparam int LATENCY_TRIGGER_PIPELINE = 4;
int timer;
int trigger_time_q [rx_pkg::CHANNELS][$];

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
) ps_bypass_tx_i (
  .clk(ps_clk),
  .intf(ps_bypass)
);

logic adc_send_samples, adc_driver_enabled;
int adc_send_samples_decimation, adc_send_samples_counter;

// decimate samples and save trigger times for digitally-supplied triggers
always @(posedge adc_clk) begin
  // save trigger times
  if (adc_reset) begin
    timer <= LATENCY_TRIGGER_PIPELINE;
  end else begin
    timer <= timer + 1;
  end
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    if (trigger_sources[channel] >= rx_pkg::CHANNELS) begin
      if (adc_digital_trigger_in[trigger_sources[channel] - rx_pkg::CHANNELS] === 1'b1) begin
        trigger_sample_count_q[channel].push_front(adc_data_in_tx_i.data_q[channel].size());
        trigger_delay_q[channel].push_front((adc_send_samples_counter + adc_send_samples_decimation - 1) % adc_send_samples_decimation);
        trigger_time_q[channel].push_front(timer);
      end
    end
  end
  // decimation
  if (adc_reset) begin
    adc_send_samples_counter <= 0;
  end else begin
    if (adc_send_samples_counter == adc_send_samples_decimation - 1) begin
      adc_send_samples_counter <= 0;
      adc_driver_enabled <= adc_send_samples;
    end else begin
      adc_send_samples_counter <= adc_send_samples_counter + 1;
      adc_driver_enabled <= 1'b0;
    end
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
  ps_bypass_tx_i.init();
  disable_send();
  adc_digital_trigger_in <= '0;
  adc_send_samples_decimation <= 1;
  adc_send_samples_counter <= 0;
endtask

task automatic clear_trigger_q ();
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    while (trigger_sample_count_q[channel].size() > 0) trigger_sample_count_q[channel].pop_back();
    while (trigger_delay_q[channel].size() > 0) trigger_delay_q[channel].pop_back();
    while (trigger_time_q[channel].size() > 0) trigger_time_q[channel].pop_back();
  end
endtask

task automatic clear_queues ();
  adc_data_in_tx_i.clear_queues();
  adc_data_out_rx_i.clear_queues();
  adc_timestamps_out_rx_i.clear_queues();
  clear_trigger_q();
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

task automatic set_trigger_sources (
  inout sim_util_pkg::debug debug,
  input logic [rx_pkg::CHANNELS-1:0][$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS)-1:0] sources
);
  logic success;
  ps_trigger_select_tx_i.send_sample_with_timeout(10, sources, success);
  if (~success) begin
    debug.error("failed to set delays");
  end
endtask

task automatic set_bypassed_channels (
  inout sim_util_pkg::debug debug,
  input logic [rx_pkg::CHANNELS-1:0] bypassed_mask
);
  logic success;
  ps_bypass_tx_i.send_sample_with_timeout(10, bypassed_mask, success);
  if (~success) begin
    debug.error("failed to set disabled channels");
  end
endtask

task automatic send_digital_trigger (
  input logic [tx_pkg::CHANNELS-1:0] triggers
);
  adc_digital_trigger_in <= triggers;
  // get trigger times
  @(posedge adc_clk);
  adc_digital_trigger_in <= '0;
endtask


function automatic bit any_above_threshold (
  input rx_pkg::batch_t batch,
  input rx_pkg::sample_t threshold
);
  for (int sample = 0; sample < rx_pkg::PARALLEL_SAMPLES; sample++) begin
    if (rx_pkg::sample_t'(batch[sample*rx_pkg::SAMPLE_WIDTH+:rx_pkg::SAMPLE_WIDTH]) > rx_pkg::sample_t'(threshold)) begin
      return 1'b1;
    end
  end
  return 1'b0;
endfunction

task automatic check_results (
  inout sim_util_pkg::debug debug,
  input logic [rx_pkg::CHANNELS-1:0][rx_pkg::SAMPLE_WIDTH-1:0] low_thresholds, high_thresholds,
  input logic [rx_pkg::CHANNELS-1:0][TIMER_BITS-1:0] start_delays, stop_delays, digital_delays,
  input logic [rx_pkg::CHANNELS-1:0][$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS)-1:0] trigger_sources,
  input logic [rx_pkg::CHANNELS-1:0] bypassed_channel_mask
);
  rx_pkg::batch_t trigger_q [$];
  rx_pkg::batch_t expected_q [$];
  logic [buffer_pkg::TSTAMP_WIDTH-1:0] timestamp_q [$];
  int expected_locations [$];
  int start_index;
  int q_end;
  logic missing_sample;
  int main_sample;
  int stop_delay, start_delay;
  logic is_high;
  logic [buffer_pkg::SAMPLE_INDEX_WIDTH-1:0] index;
  logic [buffer_pkg::TSTAMP_WIDTH-1:0] time_init;
  logic [$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS)-1:0] source;
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    source = trigger_sources[channel];
    debug.display($sformatf(
      "checking received output for channel %0d",
      channel),
      sim_util_pkg::DEBUG
    );
    debug.display($sformatf("trigger source = %0d", source), sim_util_pkg::DEBUG);
    time_init = adc_timestamps_out_rx_i.data_q[channel][$] >> buffer_pkg::SAMPLE_INDEX_WIDTH;
    if (bypassed_channel_mask[channel] === 1'b1) begin
      // check we got everything
      // timestamp_q should be empty; don't do anything
      // fill expected_q with data that was sent
      start_index = adc_data_in_tx_i.data_q[channel].size() - 1;
      for (int i = 0; i < LATENCY_TRIGGER_PIPELINE; i++) begin
        adc_data_out_rx_i.data_q[channel].pop_back();
      end
      while (adc_data_in_tx_i.data_q[channel][start_index] !== adc_data_out_rx_i.data_q[channel][$]) begin
        if (start_index == 0) begin
          break;
        end
        start_index--;
      end
      for (int i = start_index; i >= 0; i--) begin
        expected_q.push_front(adc_data_in_tx_i.data_q[channel][i]);
      end
    end else begin
      if (source >= rx_pkg::CHANNELS) begin
        q_end = adc_data_in_tx_i.data_q[channel].size() - 1;
        // get expected_locations from trigger_sample_count_q
        // from trigger_delay_q
        for (int i = trigger_sample_count_q[channel].size() - 1; i >= 0; i--) begin
          main_sample = trigger_sample_count_q[channel][i] + digital_delays[channel]/adc_send_samples_decimation;
          debug.display($sformatf("main_sample = %0d, trigger_sample_count_q[%0d][%0d] = %0d, digital_delays[%0d] = %0d", main_sample, channel, i, trigger_sample_count_q[channel][i], channel, digital_delays[channel]), sim_util_pkg::DEBUG);
          missing_sample = trigger_delay_q[channel][i] != 0;
          stop_delay = stop_delays[channel];
          start_delay = start_delays[channel];
          if (missing_sample) begin
            stop_delay -= adc_send_samples_decimation;
          end
          debug.display($sformatf("trigger_delay_q[%0d][%0d] = %0d", channel, i, trigger_delay_q[channel][i]), sim_util_pkg::DEBUG);
          debug.display($sformatf("stop_delay = %0d", stop_delay), sim_util_pkg::DEBUG);
          // if stop_delays was set to zero and we're missing a sample, it'll be
          // the main sample
          if (stop_delay >= 0) begin
            expected_locations.push_front(q_end - main_sample);
          end else if (start_delay == 0) begin
            expected_locations.push_front(q_end - main_sample);
            //start_delay += adc_send_samples_decimation;
          end
          // delay is not in samples, it's in clock periods at maximum sample rate
          // pre-trigger samples
          if (start_delay > 0) begin
            for (int j = 1;
                  (j*adc_send_samples_decimation <= start_delay)
                  && (j <= main_sample); j++) begin
              expected_locations.push_front(q_end - main_sample + j);
            end
          end
          // post-trigger samples (might be missing one if trigger wasn't
          // aligned with a input_valid signal)
          if (stop_delay > 0) begin
            for (int j = 1;
                  (j*adc_send_samples_decimation <= stop_delay)
                  && (j <= q_end - main_sample); j++) begin
              expected_locations.push_front(q_end - main_sample - j);
            end
          end
        end
      end else begin
        trigger_q = adc_data_in_tx_i.data_q[source];
        // get expected_locations by checking source queue
        is_high = 1'b0;
        // start after start_delays[channel] because the data at the beginning has already
        // passed through the sample discriminator while adc_reset_state was held high
        for (int i = trigger_q.size() - 1 - (start_delays[source]/adc_send_samples_decimation); i >= 0; i--) begin
          if (any_above_threshold(trigger_q[i], high_thresholds[source])) begin
            is_high = 1'b1;
          end
          if (~any_above_threshold(trigger_q[i], low_thresholds[source])) begin
            is_high = 1'b0;
          end
          if (is_high) begin
            expected_locations.push_front(i);
            // delay is not in samples, it's in clock periods at maximum sample rate
            for (int j = 1;
                  (j*adc_send_samples_decimation <= start_delays[channel])
                  && (i + j < adc_data_in_tx_i.data_q[channel].size()); j++) begin
              expected_locations.push_front(i+j);
            end
            for (int j = 1; (j*adc_send_samples_decimation <= stop_delays[channel]) && (i - j >= 0); j++) begin
              expected_locations.push_front(i-j);
            end
          end
        end
      end
      debug.display($sformatf(
        "expected_locations = %0p",
        expected_locations),
        sim_util_pkg::DEBUG
      );
      expected_locations = expected_locations.unique();
      expected_locations.sort();
      debug.display($sformatf(
        "expected_locations.size() = %0d",
        expected_locations.size()),
        sim_util_pkg::DEBUG
      );
      debug.display($sformatf(
        "expected_locations = %0p",
        expected_locations),
        sim_util_pkg::DEBUG
      );
      // get timestamp_q
      for (int i = expected_locations.size() - 1; i >= 0; i--) begin
        index = expected_locations.size() - 1 - i;
        if ((expected_locations[i+1] - 1 > expected_locations[i]) || (i == expected_locations.size() - 1)) begin
          if (source >= rx_pkg::CHANNELS) begin
            timestamp_q.push_front({trigger_time_q[channel].pop_back() + digital_delays[channel], index});
          end else begin
            timestamp_q.push_front({
              time_init + (expected_locations[$]-expected_locations[i])*adc_send_samples_decimation,
              index
            });
          end
        end
      end
      debug.display($sformatf("expected_timestamps = %0p", timestamp_q), sim_util_pkg::DEBUG);
      // generate expected_q data
      while (expected_locations.size() > 0) begin
        debug.display($sformatf("expected location = %d, pushing value = %x", expected_locations[$], adc_data_in_tx_i.data_q[channel][expected_locations[$]]), sim_util_pkg::DEBUG);
        expected_q.push_front(adc_data_in_tx_i.data_q[channel][expected_locations.pop_back()]);
      end
    end
    // check expected_q matches received
    debug.display("checking data", sim_util_pkg::DEBUG);
    batch_q_util.compare(debug, adc_data_out_rx_i.data_q[channel], expected_q);
    while (expected_q.size() > 0) expected_q.pop_back();
    // check timestamp_q
    debug.display("checking timestamp_q", sim_util_pkg::DEBUG);
    tstamp_q_util.compare(debug, adc_timestamps_out_rx_i.data_q[channel], timestamp_q);
    while (timestamp_q.size() > 0) timestamp_q.pop_back();
  end
endtask

task automatic print_data (
  inout sim_util_pkg::debug debug,
  input rx_pkg::batch_t data_q [$]
);
  rx_pkg::sample_t sample_q [$];
  rx_pkg::sample_t temp_q [$];
  sample_q_util.samples_from_batches(data_q, sample_q, rx_pkg::SAMPLE_WIDTH, rx_pkg::PARALLEL_SAMPLES);
  while (sample_q.size() > 0) begin
    repeat (rx_pkg::PARALLEL_SAMPLES) temp_q.push_front(sample_q.pop_back());
    debug.display($sformatf(
      "%0p",
      temp_q),
      sim_util_pkg::DEBUG
    );
    repeat (rx_pkg::PARALLEL_SAMPLES) temp_q.pop_back();
  end
endtask


endmodule
