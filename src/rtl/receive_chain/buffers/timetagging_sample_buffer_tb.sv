// timetagging_sample_buffer_tb.sv - Reed Foster
// Tasks and driver submodules to verify segmented buffer


`timescale 1ns/1ps
module timetagging_sample_buffer_tb #(
  parameter int AXI_MM_WIDTH
) (
  // ADC clock, reset (512 MHz)
  input logic adc_clk, adc_reset,
  // Data
  Realtime_Parallel_If.Master adc_samples_in,
  Realtime_Parallel_If.Master adc_timestamps_in,
  // Realtime inputs
  input logic adc_digital_trigger,
  // Realtime outputs
  input logic adc_discriminator_reset, // send signal to sample discriminator to reset hysteresis/index tracking

  // Status/configuration (PS) clock, reset (100 MHz)
  input logic ps_clk, ps_reset,
  // Buffer output data (both timestamp and data buffers are merged)
  Axis_If.Slave ps_readout_data,
  // Status registers
  Axis_If.Slave ps_samples_write_depth,
  Axis_If.Slave ps_timestamps_write_depth,

  // Buffer configuration (merged)
  Axis_If.Master ps_capture_arm_start_stop, // {arm, start, stop}
  Axis_If.Master ps_capture_banking_mode,
  // Buffer reset
  Axis_If.Master ps_capture_sw_reset, // ps clock domain; reset capture logic
  Axis_If.Master ps_readout_sw_reset, // ps clock domain; reset readout logic
  Axis_If.Master ps_readout_start // enable DMA over ps_readout_data interface
);

// axis drivers for DUT configuration registers
axis_driver #(
  .DWIDTH(3)
) ps_capture_arm_start_stop_tx_i (
  .clk(ps_clk),
  .intf(ps_capture_arm_start_stop)
);

axis_driver #(
  .DWIDTH(buffer_pkg::BANKING_MODE_WIDTH)
) ps_capture_banking_mode_tx_i (
  .clk(ps_clk),
  .intf(ps_capture_banking_mode)
);

axis_driver #(
  .DWIDTH(1)
) ps_capture_sw_reset_tx_i (
  .clk(ps_clk),
  .intf(ps_capture_sw_reset)
);

axis_driver #(
  .DWIDTH(1)
) ps_readout_sw_reset_tx_i (
  .clk(ps_clk),
  .intf(ps_readout_sw_reset)
);

axis_driver #(
  .DWIDTH(1)
) ps_readout_start_tx_i (
  .clk(ps_clk),
  .intf(ps_readout_start)
);

// axis receiver for data
axis_receiver #(
  .DWIDTH(AXI_MM_WIDTH)
) ps_readout_data_rx_i (
  .clk(ps_clk),
  .ready_rand(1'b1),
  .ready_en(1'b1),
  .intf(ps_readout_data)
);

// axis receivers for DUT status registers
axis_receiver #(
  .DWIDTH(rx_pkg::CHANNELS*($clog2(buffer_pkg::SAMPLE_BUFFER_DEPTH)+1))
) ps_samples_write_depth_rx_i (
  .clk(ps_clk),
  .ready_rand(1'b1),
  .ready_en(1'b1),
  .intf(ps_samples_write_depth)
);

axis_receiver #(
  .DWIDTH(rx_pkg::CHANNELS*($clog2(buffer_pkg::TSTAMP_BUFFER_DEPTH)+1))
) ps_timestamps_write_depth_rx_i (
  .clk(ps_clk),
  .ready_rand(1'b1),
  .ready_en(1'b1),
  .intf(ps_timestamps_write_depth)
);

logic adc_disable_samples;
logic adc_disable_timestamps;

// drivers for samples and timestamps
realtime_parallel_driver #(
  .DWIDTH(rx_pkg::DATA_WIDTH),
  .CHANNELS(rx_pkg::CHANNELS)
) adc_samples_in_tx_i (
  .clk(adc_clk),
  .reset(adc_reset),
  .valid_rand('1),
  .valid_en({rx_pkg::CHANNELS{~adc_reset & ~adc_disable_samples}}),
  .intf(adc_samples_in)
);

realtime_parallel_driver #(
  .DWIDTH(buffer_pkg::TSTAMP_WIDTH),
  .CHANNELS(rx_pkg::CHANNELS)
) adc_timestamps_in_tx_i (
  .clk(adc_clk),
  .reset(adc_reset),
  .valid_rand('1),
  .valid_en({rx_pkg::CHANNELS{~adc_reset & ~adc_disable_timestamps}}),
  .intf(adc_timestamps_in)
);

/////////////////////////////////////////////////////////////////
// tasks for interacting with the DUT/test
/////////////////////////////////////////////////////////////////

task automatic init();
  ps_capture_arm_start_stop_tx_i.init();
  ps_capture_banking_mode_tx_i.init();
  ps_capture_sw_reset_tx_i.init();
  ps_readout_sw_reset_tx_i.init();
  ps_readout_start_tx_i.init();
  adc_disable_samples <= 1'b0;
  adc_disable_timestamps <= 1'b0;
endtask

task automatic clear_sent_data();
  adc_samples_in_tx_i.clear_queues();
  adc_timestamps_in_tx_i.clear_queues();
endtask

task automatic clear_write_depth();
  ps_samples_write_depth_rx_i.clear_queues();
  ps_timestamps_write_depth_rx_i.clear_queues();
endtask

task automatic clear_received_data();
  ps_readout_data_rx_i.clear_queues();
endtask

task automatic adc_samples_enabled(input logic enable_disable);
  adc_disable_samples <= ~enable_disable;
endtask

task automatic adc_timestamps_enabled(input logic enable_disable);
  adc_disable_timestamps <= ~enable_disable;
endtask

task automatic capture_arm_start_stop(
  inout sim_util_pkg::debug debug,
  input logic arm,
  input logic start,
  input logic stop
);
  logic success;
  debug.display($sformatf("sending arm(%0d)/start(%0d)/stop(%0d) to capture", arm, start, stop), sim_util_pkg::DEBUG);
  ps_capture_arm_start_stop_tx_i.send_sample_with_timeout(20, {arm, start, stop}, success);
  if (~success) begin
    debug.error("failed to write to arm/start/stop register");
  end
endtask

task automatic set_banking_mode(
  inout sim_util_pkg::debug debug,
  input logic [buffer_pkg::BANKING_MODE_WIDTH-1:0] banking_mode
);
  logic success;
  debug.display($sformatf("writing banking_mode = %0d", banking_mode), sim_util_pkg::DEBUG);
  ps_capture_banking_mode_tx_i.send_sample_with_timeout(10, banking_mode, success);
  if (~success) begin
    debug.error("failed to set banking mode");
  end
endtask

task automatic reset_capture(
  inout sim_util_pkg::debug debug
);
  logic success;
  debug.display("resetting capture", sim_util_pkg::DEBUG);
  ps_capture_sw_reset_tx_i.send_sample_with_timeout(10, 1'b1, success);
  if (~success) begin
    debug.error("failed to reset capture");
  end
endtask

task automatic reset_readout(
  inout sim_util_pkg::debug debug
);
  logic success;
  debug.display("resetting readout", sim_util_pkg::DEBUG);
  ps_readout_sw_reset_tx_i.send_sample_with_timeout(10, 1'b1, success);
  if (~success) begin
    debug.error("failed to reset readout");
  end
endtask

task automatic start_readout(
  inout sim_util_pkg::debug debug
);
  logic success;
  debug.display("starting readout", sim_util_pkg::DEBUG);
  ps_readout_start_tx_i.send_sample_with_timeout(10, 1'b1, success);
  if (~success) begin
    debug.fatal("failed to start readout");
  end
endtask

// checking output
task automatic check_write_depth_num_packets (
  inout sim_util_pkg::debug debug
);
  debug.display("checking number of write_depth transfers", sim_util_pkg::DEBUG);
  // check write_depth queue is empty
  if (ps_samples_write_depth_rx_i.data_q.size() !== 1) begin
    debug.error($sformatf(
      "samples_write_depth.size() = %0d, expected 1 transactions",
      ps_samples_write_depth_rx_i.data_q.size())
    );
  end
  if (ps_timestamps_write_depth_rx_i.data_q.size() !== 1) begin
    debug.error($sformatf(
      "timestamps_write_depth.size() = %0d, expected 1 transactions",
      ps_timestamps_write_depth_rx_i.data_q.size())
    );
  end
endtask

// check that the correct number of samples match between the output and
// input
task automatic check_output (
  inout sim_util_pkg::debug debug,
  input int active_channels
);
  logic matched;
  buffer_pkg::tstamp_t readout_timestamps_q [rx_pkg::CHANNELS][$];
  rx_pkg::batch_t readout_samples_q [rx_pkg::CHANNELS][$];
  sim_util_pkg::queue #(.T(buffer_pkg::tstamp_t)) tstamp_q_util = new();
  sim_util_pkg::queue #(.T(rx_pkg::batch_t)) sample_q_util = new();
  // get output
  parse_readout_data(debug, active_channels, readout_timestamps_q, readout_samples_q);

  for (int channel = 0; channel < active_channels; channel++) begin
    // remove extra samples from TX queues until we get something
    // that matches the DMA data since we aren't sure exactly when
    // the DUT started saving data
    debug.display("pre-strip:", sim_util_pkg::DEBUG);
    debug.display($sformatf(
      "adc_timestamps_in_tx_i.data_q[%0d].size() = %0d | readout_timestamps_q[%0d].size() = %0d",
      channel, adc_timestamps_in_tx_i.data_q[channel].size(),
      channel, readout_timestamps_q[channel].size()),
      sim_util_pkg::DEBUG
    );
    debug.display($sformatf(
      "adc_timestamps_in_tx_i.data_q[%0d][$] = %x | readout_timestamps_q[%0d][$] = %x",
      channel, adc_timestamps_in_tx_i.data_q[channel][$],
      channel, readout_timestamps_q[channel][$]),
      sim_util_pkg::DEBUG
    );
    debug.display($sformatf(
      "adc_samples_in_tx_i.data_q[%0d].size() = %0d | readout_samples_q[%0d].size() = %0d",
      channel, adc_samples_in_tx_i.data_q[channel].size(),
      channel, readout_samples_q[channel].size()),
      sim_util_pkg::DEBUG
    );
    debug.display($sformatf(
      "adc_samples_in_tx_i.data_q[%0d][$] = %x | readout_samples_q[%0d][$] = %x",
      channel, adc_samples_in_tx_i.data_q[channel][$],
      channel, readout_samples_q[channel][$]),
      sim_util_pkg::DEBUG
    );
    tstamp_q_util.strip_to_matching(adc_timestamps_in_tx_i.data_q[channel], readout_timestamps_q[channel]);
    sample_q_util.strip_to_matching(adc_samples_in_tx_i.data_q[channel], readout_samples_q[channel]);
    debug.display("post-strip:", sim_util_pkg::DEBUG);
    debug.display($sformatf(
      "adc_timestamps_in_tx_i.data_q[%0d].size() = %0d | readout_timestamps_q[%0d].size() = %0d",
      channel, adc_timestamps_in_tx_i.data_q[channel].size(),
      channel, readout_timestamps_q[channel].size()),
      sim_util_pkg::DEBUG
    );
    debug.display($sformatf(
      "adc_timestamps_in_tx_i.data_q[%0d][$] = %x | readout_timestamps_q[%0d][$] = %x",
      channel, adc_timestamps_in_tx_i.data_q[channel][$],
      channel, readout_timestamps_q[channel][$]),
      sim_util_pkg::DEBUG
    );
    debug.display($sformatf(
      "adc_samples_in_tx_i.data_q[%0d].size() = %0d | readout_samples_q[%0d].size() = %0d",
      channel, adc_samples_in_tx_i.data_q[channel].size(),
      channel, readout_samples_q[channel].size()),
      sim_util_pkg::DEBUG
    );
    debug.display($sformatf(
      "adc_samples_in_tx_i.data_q[%0d][$] = %x | readout_samples_q[%0d][$] = %x",
      channel, adc_samples_in_tx_i.data_q[channel][$],
      channel, readout_samples_q[channel][$]),
      sim_util_pkg::DEBUG
    );
    tstamp_q_util.compare(debug, readout_timestamps_q[channel], adc_timestamps_in_tx_i.data_q[channel]);
    sample_q_util.compare(debug, readout_samples_q[channel], adc_samples_in_tx_i.data_q[channel]);
  end
endtask

localparam int TSTAMP_CHANNEL_SIZE = (buffer_pkg::TSTAMP_BUFFER_DEPTH*buffer_pkg::TSTAMP_WIDTH)/AXI_MM_WIDTH;
localparam int SAMPLE_CHANNEL_SIZE = (buffer_pkg::SAMPLE_BUFFER_DEPTH*rx_pkg::DATA_WIDTH)/AXI_MM_WIDTH;
localparam int READOUT_MIDPOINT = rx_pkg::CHANNELS*TSTAMP_CHANNEL_SIZE;
typedef logic [AXI_MM_WIDTH-1:0] aximm_word_t;
task automatic parse_readout_data (
  inout sim_util_pkg::debug debug,
  input int active_channels,
  output buffer_pkg::tstamp_t readout_timestamps_q [rx_pkg::CHANNELS][$],
  output rx_pkg::batch_t readout_samples_q [rx_pkg::CHANNELS][$]
);
  sim_util_pkg::queue #(.T(buffer_pkg::tstamp_t), .T2(aximm_word_t)) tstamp_q_util = new();
  sim_util_pkg::queue #(.T(rx_pkg::batch_t), .T2(aximm_word_t)) sample_q_util = new();
  logic [AXI_MM_WIDTH-1:0] wide_readout_samples_q [rx_pkg::CHANNELS][$];
  logic [AXI_MM_WIDTH-1:0] wide_readout_timestamps_q [rx_pkg::CHANNELS][$];
  logic [rx_pkg::CHANNELS-1:0][$clog2(buffer_pkg::TSTAMP_BUFFER_DEPTH):0] timestamps_write_depths_temp;
  logic [rx_pkg::CHANNELS-1:0][$clog2(buffer_pkg::SAMPLE_BUFFER_DEPTH):0] samples_write_depths_temp;
  int destination_channel;
  int arrival_time;
  int total_timestamps;
  int total_samples;
  // split readout data per channel into queues with element width AXI_MM_WIDTH
  for (int i = ps_readout_data_rx_i.data_q.size() - 1; i >= 0; i--) begin
    arrival_time = ps_readout_data_rx_i.data_q.size() - 1 - i;
    if (arrival_time < READOUT_MIDPOINT) begin
      destination_channel = (arrival_time / TSTAMP_CHANNEL_SIZE) % active_channels;
      debug.display($sformatf(
        "saving timestamp %x to channel %0d",
        ps_readout_data_rx_i.data_q[i],
        destination_channel),
        sim_util_pkg::DEBUG
      );
      wide_readout_timestamps_q[destination_channel].push_front(ps_readout_data_rx_i.data_q[i]);
    end else begin
      destination_channel = ((arrival_time - READOUT_MIDPOINT) / SAMPLE_CHANNEL_SIZE) % active_channels;
      debug.display($sformatf(
        "saving sample %x to channel %0d",
        ps_readout_data_rx_i.data_q[i],
        destination_channel),
        sim_util_pkg::DEBUG
      );
      wide_readout_samples_q[destination_channel].push_front(ps_readout_data_rx_i.data_q[i]);
    end
  end
  // convert AXI_MM_WIDTH-wide elements to respective type widths and trim invalid data
  timestamps_write_depths_temp = ps_timestamps_write_depth_rx_i.data_q[0];
  samples_write_depths_temp = ps_samples_write_depth_rx_i.data_q[0];
  debug.display($sformatf(
    "timestamps write_depths = %x, samples write_depths = %x",
    timestamps_write_depths_temp,
    samples_write_depths_temp),
    sim_util_pkg::DEBUG
  );
  for (int channel = 0; channel < active_channels; channel++) begin
    tstamp_q_util.samples_from_batches(
      wide_readout_timestamps_q[channel],
      readout_timestamps_q[channel],
      buffer_pkg::TSTAMP_WIDTH,
      AXI_MM_WIDTH/buffer_pkg::TSTAMP_WIDTH
    );
    sample_q_util.samples_from_batches(
      wide_readout_samples_q[channel],
      readout_samples_q[channel],
      rx_pkg::DATA_WIDTH,
      AXI_MM_WIDTH/rx_pkg::DATA_WIDTH
    );
    total_timestamps = 0;
    total_samples = 0;
    for (int bank = channel; bank < rx_pkg::CHANNELS; bank += active_channels) begin
      total_timestamps += timestamps_write_depths_temp[bank];
      total_samples += samples_write_depths_temp[bank];
    end
    debug.display($sformatf(
      "total_timestamps[%0d] = %0d, total_samples[%0d] = %0d",
      channel, total_timestamps,
      channel, total_samples),
      sim_util_pkg::DEBUG
    );
    while (readout_timestamps_q[channel].size() > total_timestamps) begin
      readout_timestamps_q[channel].pop_front();
    end
    while (readout_samples_q[channel].size() > total_samples) begin
      readout_samples_q[channel].pop_front();
    end
  end
endtask

endmodule
