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
  input wire adc_clk, adc_reset,
  // data pipeline
  Axis_Parallel_If.Slave_Realtime adc_data_in,

  // clock domain for DMA interface and register map
  input wire ps_clk, ps_reset,
  // data pipeline
  Axis_If.Master_Full dma_data_out,
  // configuration registers
  Axis_If.Slave_Realtime sample_discriminator_config,
  Axis_If.Slave_Realtime buffer_config,
  Axis_If.Slave_Realtime channel_mux_config,
  Axis_If.Slave_Realtime lmh6401_gain_config
);

axis_channel_mux #(
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .CHANNELS(CHANNELS),
  .FUNCTIONS_PER_CHANNEL(1)
) channel_mux_i (
  .clk(adc_clk),
  .reset(adc_reset),
  .data_in(adc_data_in),
  .config_in(sync_channel_mux_config)
);

// synchronize configuration registers


endmodule
