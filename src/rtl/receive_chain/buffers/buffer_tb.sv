// buffer_tb.sv - Reed Foster
// Utilities for verification of ADC receive buffer
// Tasks to drive configuration inputs of DUT
// Tasks to verify DUT response to input data

`timescale 1ns/1ps
module buffer_tb #(
  parameter int BUFFER_DEPTH = 1024
) (
  Axis_If arm_start_stop,
  Axis_If capture_banking_mode,
  Axis_If capture_reset,
  Axis_If readout_reset,
  Axis_If readout_start
);

/////////////////////////////////////////////////////////////////
// tasks for interacting with the DUT/test
/////////////////////////////////////////////////////////////////
task automatic capture_arm_start_stop(
  inout sim_util_pkg::debug debug,
  ref ps_clk,
  input logic [2:0] bits
);
  logic success;
  case (bits)
    1: debug.display("sending stop to capture", sim_util_pkg::DEBUG);
    2: debug.display("sending sw_start to capture", sim_util_pkg::DEBUG);
    4: debug.display("sending arm to capture", sim_util_pkg::DEBUG);
    default: begin
      debug.error($sformatf("invalid arm_start_stop value %0d", bits));
      return;
    end
  endcase
  arm_start_stop.send_sample_with_timeout(ps_clk, bits, 10, success);
  if (~success) begin
    debug.error("failed to start capture");
  end
endtask

task automatic set_banking_mode(
  inout sim_util_pkg::debug debug,
  ref ps_clk,
  input logic [$clog2($clog2(rx_pkg::CHANNELS+1))-1:0] banking_mode
);
  logic success;
  debug.display($sformatf("writing banking_mode = %0d", banking_mode), sim_util_pkg::DEBUG);
  capture_banking_mode.send_sample_with_timeout(ps_clk, banking_mode, 10, success);
  if (~success) begin
    debug.error("failed to set banking mode");
  end
endtask

task automatic reset_capture(
  inout sim_util_pkg::debug debug,
  ref ps_clk,
  inout logic [rx_pkg::DATA_WIDTH-1:0] samples_sent [rx_pkg::CHANNELS][$]
);
  logic success;
  debug.display("resetting capture", sim_util_pkg::DEBUG);
  capture_reset.send_sample_with_timeout(ps_clk, 1'b1, 10, success);
  if (~success) begin
    debug.error("failed to reset capture");
  end
  // delete all saved samples
  clear_samples_sent(samples_sent);
endtask

task automatic reset_readout(
  inout sim_util_pkg::debug debug,
  ref ps_clk,
  inout logic [rx_pkg::DATA_WIDTH-1:0] samples_received [$]
);
  logic success;
  debug.display("resetting readout", sim_util_pkg::DEBUG);
  readout_reset.send_sample_with_timeout(ps_clk, 1'b1, 10, success);
  if (~success) begin
    debug.error("failed to reset readout");
  end
  // delete all saved samples
  while (samples_received.size() > 0) samples_received.pop_back();
endtask

task automatic start_readout(
  inout sim_util_pkg::debug debug,
  ref ps_clk,
  input logic expected_response
);
  logic success;
  debug.display("starting readout", sim_util_pkg::DEBUG);
  readout_start.send_sample_with_timeout(ps_clk, 1'b1, 10, success);
  case (expected_response)
    1'b1: begin
      if (~success) begin
        debug.error("failed to start readout");
      end
    end
    1'b0: begin
      if (success) begin
        debug.error("started readout, but shouldn't have been able to");
      end
    end
  endcase
endtask

// clear samples_sent queues (used at the end of each trial, or when
// a capture is manually restarted)
task automatic clear_samples_sent (
  inout logic [rx_pkg::DATA_WIDTH-1:0] samples_sent [rx_pkg::CHANNELS][$]
);
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    while (samples_sent[channel].size() > 0) samples_sent[channel].pop_back();
  end
endtask

/////////////////////////////////////////////////////////////////
// tasks for verifying DUT output
/////////////////////////////////////////////////////////////////
// make sure that the reported write_depth (i.e. how many samples the DUT
// stored in each buffer bank) is maximal for at least one of the channels
task automatic check_write_depth_full (
  inout sim_util_pkg::debug debug,
  input [rx_pkg::CHANNELS-1:0][$clog2(BUFFER_DEPTH):0] write_depth [$],
  input int active_channels,
  output bit success
);
  success = 0;
  debug.display("checking write_depth indicates at least one of the channels filled up", sim_util_pkg::DEBUG);
  for (int channel = 0; channel < active_channels; channel++) begin
    if (write_depth[$][rx_pkg::CHANNELS-1-channel][$clog2(BUFFER_DEPTH)]) begin
      success = 1;
    end
  end
  if (~success) begin
    debug.error($sformatf(
      "write_depth = %x does not indicate that any buffer filled up for active_channels = %0d",
      write_depth[$],
      active_channels)
    );
  end
endtask

// make sure that the correct number of transfers occurred on the
// write_depth interface
task automatic check_write_depth_num_packets (
  inout sim_util_pkg::debug debug,
  input [rx_pkg::CHANNELS-1:0][$clog2(BUFFER_DEPTH):0] write_depth [$],
  input int expected_packets,
  output bit success
);
  debug.display("checking number of write_depth transfers", sim_util_pkg::DEBUG);
  // check write_depth queue is empty
  if (write_depth.size() !== expected_packets) begin
    debug.error($sformatf(
      "write_depth.size() = %0d, expected %0d transactions",
      write_depth.size(),
      expected_packets)
    );
    success = 0;
  end else begin
    success = 1;
  end
endtask

// check that the correct number of samples match between the output and
// input
task automatic check_output(
  inout sim_util_pkg::debug debug,
  inout logic [rx_pkg::DATA_WIDTH-1:0] samples_sent [rx_pkg::CHANNELS][$],
  inout logic [rx_pkg::DATA_WIDTH-1:0] samples_received [$],
  inout [rx_pkg::CHANNELS-1:0][$clog2(BUFFER_DEPTH):0] write_depth [$],
  input int active_channels
);
  logic [rx_pkg::CHANNELS-1:0][31:0] total_write_depth = '0;
  int sample_index;
  debug.display("checking output data", sim_util_pkg::DEBUG);
  // check_output(samples_sent, samples_received, write_depth, 1 << banking_mode);
  // check that the correct number of samples match based on the write depth
  for (int channel = 0; channel < active_channels; channel++) begin
    for (int bank = channel; bank < rx_pkg::CHANNELS; bank += active_channels) begin
      if (write_depth[$][bank][$clog2(BUFFER_DEPTH)]) begin
        total_write_depth[channel] += BUFFER_DEPTH;
      end else begin
        total_write_depth[channel] += write_depth[$][bank];
      end
    end
    // remove extra samples until we get something that matches the DMA data
    // since we aren't sure exactly when the DUT started saving data
    while ((samples_sent[channel].size() > 0) && (samples_sent[channel][$] !== samples_received[$-channel*BUFFER_DEPTH])) begin
      samples_sent[channel].pop_back();
    end
    if (total_write_depth[channel] > samples_sent[channel].size()) begin
      debug.error($sformatf(
        "channel %0d: DUT reported write depth = %0d, but only %0d samples were sent to DUT",
        channel,
        total_write_depth[channel],
        samples_sent[channel].size())
      );
    end
  end
  for (int bank = 0; bank < rx_pkg::CHANNELS; bank++) begin
    for (int sample = 0; sample < BUFFER_DEPTH; sample++) begin
      sample_index = (bank / active_channels) * BUFFER_DEPTH + sample;
      if (sample_index < total_write_depth[bank % active_channels]) begin
        if (samples_sent[bank % active_channels][$] !== samples_received[$]) begin
          debug.error($sformatf(
            "channel %0d, bank %0d: sample mismatch: expected %x got %x",
            bank % active_channels,
            bank,
            samples_sent[bank % active_channels][$],
            samples_received[$])
          );
        end
        samples_sent[bank % active_channels].pop_back();
      end
      samples_received.pop_back();
    end
  end
  // clear queues
  clear_samples_sent(samples_sent);
  while (samples_received.size() > 0) samples_received.pop_back();
  while (write_depth.size() > 0) write_depth.pop_back();
endtask


endmodule
