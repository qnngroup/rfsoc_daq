// receive_top.sv - Reed Foster
// toplevel for receive signal chain, takes in data from physical ADC channels
// and provides a DMA interface for readout of data saved in sample buffers

`timescale 1ns/1ps
module receive_top #(
  parameter int CHANNELS = 8, // number of input channels
  parameter int TSTAMP_BUFFER_DEPTH = 1024, // depth of timestamp buffer
  parameter int DATA_BUFFER_DEPTH = 16384, // depth of data/sample buffer
  parameter int AXI_MM_WIDTH = 128, // width of DMA AXI-stream interface
  parameter int PARALLEL_SAMPLES = 16, // number of parallel samples per clock cycle per channel
  parameter int SAMPLE_WIDTH = 16, // width in bits of each sample
  parameter int APPROX_CLOCK_WIDTH = 48 // requested width of timestamp
) (
  // PS clock, reset (100MHz)
  input logic ps_clk, ps_reset,
  // Output data
  Axis_If.Master ps_readout_data,
  // Command registers
  Axis_If.Slave ps_capture_arm,
  Axis_If.Slave ps_capture_sw_reset,
  Axis_If.Slave ps_readout_sw_reset,
  Axis_If.Slave ps_readout_start,
  // Configuration registers
  Axis_If.Slave ps_discriminator_config, // {thresholds, delays, trigger_select, bypass}
  Axis_If.Slave ps_capture_banking_mode,
  // Status registers
  Axis_If.Master ps_capture_write_depth

  Axis_If.Slave ps_buffer_start_stop,
  Axis_If.Slave ps_channel_mux_config, // $clog2(2*CHANNELS)*CHANNELS bits
  // output registers
  Axis_If.Master ps_buffer_timestamp_width, // 32 bits
  Axis_If.Master ps_buffer_capture_done, // 1 bits

  // ADC clock, reset (256MHz)
  input logic adc_clk, adc_reset,
  // data pipeline
  Realtime_Parallel_If.Slave adc_data_in,
  Axis_If.Master adc_dma_out,
  // trigger from transmit_top
  input logic [tx_pkg::CHANNELS-1:0] adc_digital_trigger_in
);

//////////////////////////////////////////////////////////////////////////
// PS clock domain (100MHz) -> RFADC clock domain (256MHz) CDC
//////////////////////////////////////////////////////////////////////////
Axis_If #(.DWIDTH(2*CHANNELS*SAMPLE_WIDTH)) adc_sample_discriminator_config ();
Axis_If #(.DWIDTH($clog2($clog2(CHANNELS)+1))) adc_buffer_config ();
Axis_If #(.DWIDTH(2)) adc_buffer_start_stop ();
Axis_If #(.DWIDTH($clog2(2*CHANNELS)*CHANNELS)) adc_channel_mux_config ();
Axis_If #(.DWIDTH(32)) adc_buffer_timestamp_width ();
Axis_If #(.DWIDTH(1)) adc_buffer_capture_done ();

axis_config_reg_cdc #(
  .DWIDTH(2*CHANNELS*SAMPLE_WIDTH)
) ps_to_adc_sample_discriminator_config_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_sample_discriminator_config),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_sample_discriminator_config)
);
axis_config_reg_cdc #(
  .DWIDTH($clog2($clog2(CHANNELS)+1))
) ps_to_adc_buffer_config_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_buffer_config),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_buffer_config)
);
axis_config_reg_cdc #(
  .DWIDTH(2)
) ps_to_adc_buffer_start_stop_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_buffer_start_stop),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_buffer_start_stop)
);
axis_config_reg_cdc #(
  .DWIDTH($clog2(2*CHANNELS)*CHANNELS)
) ps_to_adc_channel_mux_config_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_channel_mux_config),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_channel_mux_config)
);
axis_config_reg_cdc #(
  .DWIDTH(32)
) adc_to_ps_buffer_timestamp_width_i (
  .src_clk(adc_clk),
  .src_reset(adc_reset),
  .src(adc_buffer_timestamp_width),
  .dest_clk(ps_clk),
  .dest_reset(ps_reset),
  .dest(ps_buffer_timestamp_width)
);
axis_config_reg_cdc #(
  .DWIDTH(1)
) adc_to_ps_buffer_capture_done_i (
  .src_clk(adc_clk),
  .src_reset(adc_reset),
  .src(adc_buffer_capture_done),
  .dest_clk(ps_clk),
  .dest_reset(ps_reset),
  .dest(ps_buffer_capture_done)
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
