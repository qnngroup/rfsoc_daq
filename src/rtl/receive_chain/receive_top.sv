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
  Axis_If.Slave ps_capture_digtal_trigger_select
);

// CDC ps_capture_digital_trigger_select
Axis_If #(.DWIDTH(tx_pkg::CHANNELS)) adc_capture_digital_trigger_select_sync ();
axis_config_reg_cdc #(
  .DWIDTH(tx_pkg::CHANNELS)
) cdc_digital_trigger_select_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_capture_digtal_trigger_select),
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
// RFADC clock domain (256MHz)
//////////////////////////////////////////////////////////////////////////
// multiplexer takes in physical ADC channels + differentiator outputs and
// produces logical channels
Realtime_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(2*CHANNELS)) adc_mux_input ();
Realtime_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) adc_mux_output ();

genvar channel;
generate
  for (channel = 0; channel < CHANNELS; channel++) begin
    //////////////////////////////////////////////////////////////////
    // connect ADC outputs to lower CHANNELS inputs of channel mux
    //////////////////////////////////////////////////////////////////
    assign adc_mux_input.data[channel] = adc_data_in.data[channel];
    assign adc_mux_input.valid[channel] = adc_data_in.valid[channel];

    //////////////////////////////////////////////////////////////////
    // instantiate and connect differentiator
    //////////////////////////////////////////////////////////////////
    Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) differentiator_input ();
    Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) differentiator_output ();

    assign differentiator_input.data = adc_data_in.data[channel];
    assign differentiator_input.valid = adc_data_in.valid[channel];
    assign differentiator_input.last = 1'b0; // unused; tie to 0 to suppress warning
    // differentiator_input.ready is ignored, since we're not applying backpressure
    assign adc_mux_input.data[CHANNELS + channel] = differentiator_output.data;
    assign adc_mux_input.valid[CHANNELS + channel] = differentiator_output.valid;
    // sample discriminator won't apply backpressure, so make sure the differentiator always outputs data
    assign differentiator_output.ready = 1'b1;

    axis_differentiator #(
      .SAMPLE_WIDTH(SAMPLE_WIDTH),
      .PARALLEL_SAMPLES(PARALLEL_SAMPLES)
    ) differentiator_i (
      .clk(adc_clk),
      .reset(adc_reset),
      .data_in(differentiator_input),
      .data_out(differentiator_output)
    );

    //////////////////////////////////////////////////////////////////
    // insert more math/filter blocks below for additional functions
    //////////////////////////////////////////////////////////////////
  end
endgenerate

axis_channel_mux #(
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .INPUT_CHANNELS(2*CHANNELS),
  .OUTPUT_CHANNELS(CHANNELS)
) channel_mux_i (
  .clk(adc_clk),
  .reset(adc_reset),
  .data_in(adc_mux_input),
  .data_out(adc_mux_output),
  .config_in(adc_channel_mux_config)
);

logic [31:0] timestamp_width;
assign adc_buffer_timestamp_width.data = timestamp_width;
assign adc_buffer_timestamp_width.valid = 1'b1;
assign adc_buffer_timestamp_width.last = 1'b1;

logic capture_done, capture_done_d;
always_ff @(posedge adc_clk) begin
  capture_done_d <= capture_done;
  if (adc_reset) begin
    adc_buffer_capture_done.valid <= 1'b1;
  end else begin
    if (capture_done ^ capture_done_d) begin
      adc_buffer_capture_done.valid <= 1'b1;
    end else if (adc_buffer_capture_done.ok) begin
      adc_buffer_capture_done.valid <= 1'b0;
    end
  end
end
assign adc_buffer_capture_done.data = capture_done;
assign adc_buffer_capture_done.last = 1'b1;

sparse_sample_buffer #(
  .CHANNELS(CHANNELS),
  .TSTAMP_BUFFER_DEPTH(TSTAMP_BUFFER_DEPTH),
  .DATA_BUFFER_DEPTH(DATA_BUFFER_DEPTH),
  .AXI_MM_WIDTH(AXI_MM_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .APPROX_CLOCK_WIDTH(APPROX_CLOCK_WIDTH)
) buffer_i (
  .clk(adc_clk),
  .reset(adc_reset),
  .timestamp_width,
  .capture_done,
  .data_in(adc_mux_output),
  .data_out(adc_dma_out),
  .sample_discriminator_config(adc_sample_discriminator_config),
  .buffer_config(adc_buffer_config),
  .buffer_start_stop(adc_buffer_start_stop),
  .start_aux(adc_trigger_in)
);

endmodule
