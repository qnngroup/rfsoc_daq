// receive_top.sv - Reed Foster
// toplevel for receive signal chain, takes in data from physical ADC channels
// and provides a DMA interface for readout of data saved in sample buffers

module receive_top #(
  parameter int CHANNELS = 8, // number of input channels
  parameter int TSTAMP_BUFFER_DEPTH = 1024, // depth of timestamp buffer
  parameter int DATA_BUFFER_DEPTH = 16384, // depth of data/sample buffer
  parameter int AXI_MM_WIDTH = 128, // width of DMA AXI-stream interface
  parameter int PARALLEL_SAMPLES = 16, // number of parallel samples per clock cycle per channel
  parameter int SAMPLE_WIDTH = 16, // width in bits of each sample
  parameter int APPROX_CLOCK_WIDTH = 48 // requested width of timestamp
) (
  // signals in RFADC clock domain (256MHz)
  input wire clk, reset,
  // data pipeline
  Axis_Parallel_If.Slave_Realtime adc_data_in,
  Axis_If.Master_Full dma_data_out,
  // configuration registers
  Axis_If.Slave_Realtime sample_discriminator_config, // 2*CHANNELS*SAMPLE_WIDTH bits
  Axis_If.Slave_Realtime buffer_config, // 2 + $clog2($clog2(CHANNELS) + 1) bits
  Axis_If.Slave_Realtime channel_mux_config, // $clog2((1+FUNCTIONS_PER_CHANNEL)*CHANNELS)*CHANNELS bits
  // output register
  Axis_If.Master_Realtime buffer_timestamp_width // 32 bits
);

// multiplexer takes in physical ADC channels + differentiator outputs and
// produces logical channels
Axis_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(2*CHANNELS)) mux_input ();
Axis_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) logical_channels ();

assign mux_input.ready = 1'b0; // unused; tie to 0 to suppress warning
assign mux_input.last = 1'b0; // unused; tie to 0 to suppress warning
assign logical_channels.ready = 1'b0; // unused; tie to 0 to suppress warning
assign logical_channels.last = 1'b0; // unused; tie to 0 to suppress warning

genvar channel;
generate
  for (channel = 0; channel < CHANNELS; channel++) begin
    //////////////////////////////////////////////////////////////////
    // connect ADC outputs to lower CHANNELS inputs of channel mux
    //////////////////////////////////////////////////////////////////
    assign mux_input.data[channel] = adc_data_in.data[channel];
    assign mux_input.valid[channel] = adc_data_in.valid[channel];

    //////////////////////////////////////////////////////////////////
    // instantiate and connect differentiator
    //////////////////////////////////////////////////////////////////
    Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) differentiator_input ();
    Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) differentiator_output ();

    assign differentiator_input.data = adc_data_in.data[channel];
    assign differentiator_input.valid = adc_data_in.valid[channel];
    assign differentiator_input.last = 1'b0; // unused; tie to 0 to suppress warning
    // differentiator_input.ready is ignored, since we're not applying backpressure
    assign mux_input.data[CHANNELS + channel] = differentiator_output.data;
    assign mux_input.valid[CHANNELS + channel] = differentiator_output.valid;
    assign mux_input.last = 1'b0; // unused; tie to 0 to suppress warning
    // sample discriminator won't apply backpressure, so make sure the differentiator always outputs data
    assign differentiator_output.ready = 1'b1;
    assign differentiator_output.last = 1'b0; // unused; tie to 0 to suppress warning

    axis_differentiator #(
      .SAMPLE_WIDTH(SAMPLE_WIDTH),
      .PARALLEL_SAMPLES(PARALLEL_SAMPLES)
    ) differentiator_i (
      .clk,
      .reset,
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
  .CHANNELS(CHANNELS),
  .FUNCTIONS_PER_CHANNEL(1)
) channel_mux_i (
  .clk,
  .reset,
  .data_in(mux_input),
  .data_out(logical_channels),
  .config_in(channel_mux_config)
);

logic [31:0] timestamp_width;
assign buffer_timestamp_width.data = timestamp_width;
assign buffer_timestamp_width.valid = 1'b1;

sparse_sample_buffer #(
  .CHANNELS(CHANNELS),
  .TSTAMP_BUFFER_DEPTH(TSTAMP_BUFFER_DEPTH),
  .DATA_BUFFER_DEPTH(DATA_BUFFER_DEPTH),
  .AXI_MM_WIDTH(AXI_MM_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .APPROX_CLOCK_WIDTH(APPROX_CLOCK_WIDTH)
) buffer_i (
  .clk,
  .reset,
  .timestamp_width,
  .data_in(logical_channels),
  .data_out(dma_data_out),
  .discriminator_config_in(sample_discriminator_config),
  .buffer_config_in(buffer_config)
);

endmodule
