// buffer_tb.sv - Reed Foster
// Utilities for verification of ADC receive buffer
// Tasks to drive configuration inputs of DUT
// Tasks to verify DUT response to input data

`timescale 1ns/1ps
module buffer_tb #(
  parameter int DATA_WIDTH,
  parameter int BUFFER_DEPTH
) (
  input logic adc_clk,
  input logic adc_reset,
  Realtime_Parallel_If.Master adc_data,

  input logic ps_clk,
  Axis_If.Master ps_capture_arm,
  Axis_If.Master ps_capture_banking_mode,
  Axis_If.Master ps_capture_sw_reset,
  Axis_If.Master ps_readout_sw_reset,
  Axis_If.Master ps_readout_start,
  Axis_If.Slave  ps_capture_write_depth,
  Axis_If.Slave  ps_readout_data
);

axis_driver #(
  .DWIDTH(1)
) ps_capture_arm_tx_i (
  .clk(ps_clk),
  .intf(ps_capture_arm)
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

axis_receiver #(
  .DWIDTH(rx_pkg::CHANNELS*($clog2(BUFFER_DEPTH)+1))
) ps_capture_write_depth_rx_i (
  .clk(ps_clk),
  .ready_rand(1'b1),
  .ready_en(1'b1),
  .intf(ps_capture_write_depth)
);

axis_receiver #(
  .DWIDTH(DATA_WIDTH)
) ps_readout_data_rx_i (
  .clk(ps_clk),
  .ready_rand(1'b1),
  .ready_en(1'b1), // always enable readout
  .intf(ps_readout_data)
);

realtime_parallel_driver #(
  .DWIDTH(DATA_WIDTH),
  .CHANNELS(rx_pkg::CHANNELS)
) adc_data_tx_i (
  .clk(adc_clk),
  .reset(adc_reset),
  .valid_rand('1),
  .valid_en({rx_pkg::CHANNELS{~adc_reset}}),
  .intf(adc_data)
);

/////////////////////////////////////////////////////////////////
// tasks for interacting with the DUT/test
/////////////////////////////////////////////////////////////////

task automatic init();
  ps_capture_arm_tx_i.init();
  ps_capture_banking_mode_tx_i.init();
  ps_capture_sw_reset_tx_i.init();
  ps_readout_sw_reset_tx_i.init();
  ps_readout_start_tx_i.init();
endtask

task automatic clear_sent_data();
  adc_data_tx_i.clear_queues();
endtask

task automatic clear_write_depth();
  ps_capture_write_depth_rx_i.clear_queues();
endtask

task automatic clear_received_data();
  ps_readout_data_rx_i.clear_queues();
endtask

task automatic capture_arm(
  inout sim_util_pkg::debug debug,
  input logic arm
);
  logic success;
  debug.display("sending arm to capture", sim_util_pkg::DEBUG);
  ps_capture_arm_tx_i.send_sample_with_timeout(10, arm, success);
  if (~success) begin
    debug.error("failed to write to arm register");
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
  inout sim_util_pkg::debug debug,
  input logic expected_response
);
  logic success;
  debug.display("starting readout", sim_util_pkg::DEBUG);
  ps_readout_start_tx_i.send_sample_with_timeout(10, 1'b1, success);
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

/////////////////////////////////////////////////////////////////
// tasks for verifying DUT output
/////////////////////////////////////////////////////////////////
// make sure that the reported write_depth (i.e. how many samples the DUT
// stored in each buffer bank) is maximal for at least one of the channels
task automatic check_write_depth_full (
  inout sim_util_pkg::debug debug,
  input int active_channels
);
  logic success;
  logic [rx_pkg::CHANNELS-1:0][$clog2(BUFFER_DEPTH):0] write_depths;
  debug.display("checking write_depth indicates at least one of the channels filled up", sim_util_pkg::DEBUG);
  success = 0;
  write_depths = ps_capture_write_depth_rx_i.data_q[$];
  for (int channel = 0; channel < active_channels; channel++) begin
    if (write_depths[rx_pkg::CHANNELS-1-channel][$clog2(BUFFER_DEPTH)]) begin
      success = 1;
    end
  end
  if (~success) begin
    debug.error($sformatf(
      "write_depth = %x does not indicate that any buffer filled up for active_channels = %0d",
      write_depths,
      active_channels)
    );
  end
endtask

// make sure that the correct number of transfers occurred on the
// write_depth interface
task automatic check_write_depth_num_packets (
  inout sim_util_pkg::debug debug,
  input int expected_packets
);
  debug.display("checking number of write_depth transfers", sim_util_pkg::DEBUG);
  // check write_depth queue is empty
  if (ps_capture_write_depth_rx_i.data_q.size() !== expected_packets) begin
    debug.error($sformatf(
      "write_depth.size() = %0d, expected %0d transactions",
      ps_capture_write_depth_rx_i.data_q.size(),
      expected_packets)
    );
  end
endtask

// check that the correct number of samples match between the output and
// input
task automatic check_output(
  inout sim_util_pkg::debug debug,
  input int active_channels
);
  logic [rx_pkg::CHANNELS-1:0][31:0] total_write_depth = '0;
  int sample_index;
  logic [rx_pkg::CHANNELS-1:0][$clog2(BUFFER_DEPTH):0] write_depths;
  debug.display("checking output data", sim_util_pkg::DEBUG);
  // check_output(samples_sent, samples_received, write_depth, 1 << banking_mode);
  // check that the correct number of samples match based on the write depth
  for (int channel = 0; channel < active_channels; channel++) begin
    for (int bank = channel; bank < rx_pkg::CHANNELS; bank += active_channels) begin
      write_depths = ps_capture_write_depth_rx_i.data_q[$];
      if (write_depths[bank][$clog2(BUFFER_DEPTH)]) begin
        total_write_depth[channel] += BUFFER_DEPTH;
      end else begin
        total_write_depth[channel] += write_depths[bank];
      end
    end
    // remove extra samples until we get something that matches the DMA data
    // since we aren't sure exactly when the DUT started saving data
    debug.display($sformatf(
      "received_data[$] = %x, received_data.size() = %0d",
      ps_readout_data_rx_i.data_q[$],
      ps_readout_data_rx_i.data_q.size()),
      sim_util_pkg::DEBUG
    );
    while ((adc_data_tx_i.data_q[channel].size() > 0)
          && (adc_data_tx_i.data_q[channel][$]
              !== ps_readout_data_rx_i.data_q[$-(channel*BUFFER_DEPTH)])) begin
      debug.display($sformatf(
        "sent_data[%0d][$] = %x, received_data[$-%0d*BUFFER_DEPTH] = %x",
        channel, adc_data_tx_i.data_q[channel][$],
        channel, ps_readout_data_rx_i.data_q[$-(channel*BUFFER_DEPTH)]),
        sim_util_pkg::DEBUG
      );
      adc_data_tx_i.data_q[channel].pop_back();
    end
    if (total_write_depth[channel] > adc_data_tx_i.data_q[channel].size()) begin
      debug.error($sformatf(
        "channel %0d: DUT reported write depth = %0d, but only %0d samples were sent to DUT",
        channel,
        total_write_depth[channel],
        adc_data_tx_i.data_q[channel].size())
      );
    end
  end
  for (int bank = 0; bank < rx_pkg::CHANNELS; bank++) begin
    for (int sample = 0; sample < BUFFER_DEPTH; sample++) begin
      sample_index = (bank / active_channels) * BUFFER_DEPTH + sample;
      if (sample_index < total_write_depth[bank % active_channels]) begin
        if (adc_data_tx_i.data_q[bank % active_channels][$] !== ps_readout_data_rx_i.data_q[$]) begin
          debug.error($sformatf(
            "channel %0d, bank %0d: sample mismatch: expected %x got %x",
            bank % active_channels,
            bank,
            adc_data_tx_i.data_q[bank % active_channels][$],
            ps_readout_data_rx_i.data_q[$])
          );
        end
        adc_data_tx_i.data_q[bank % active_channels].pop_back();
      end
      ps_readout_data_rx_i.data_q.pop_back();
    end
  end
endtask


endmodule
