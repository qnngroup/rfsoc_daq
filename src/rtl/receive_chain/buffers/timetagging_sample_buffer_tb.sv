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
  .DWIDTH(rx_pkg::CHANNELS*$clog2(buffer_pkg::SAMPLE_BUFFER_DEPTH))
) ps_samples_write_depth_rx_i (
  .clk(ps_clk),
  .ready_rand(1'b1),
  .ready_en(1'b1),
  .intf(ps_samples_write_depth)
);

axis_receiver #(
  .DWIDTH(rx_pkg::CHANNELS*$clog2(buffer_pkg::TSTAMP_BUFFER_DEPTH))
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
  adc_disable_samples <= enable_disable;
endtask

task automatic adc_timestamps_enabled(input logic enable_disable);
  adc_disable_timestamps <= enable_disable;
endtask

task automatic capture_arm_start_stop(
  inout sim_util_pkg::debug debug,
  input logic arm,
  input logic start,
  input logic stop,
);
  logic success;
  debug.display($sformatf("sending arm(%0d)/start(%0d)/stop(%0d) to capture", arm, start, stop), sim_util_pkg::DEBUG);
  ps_capture_arm_start_stop_tx_i.send_sample_with_timeout(10, {arm, start, stop}, success);
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
    debug.error("failed to start readout");
  end
endtask

endmodule
