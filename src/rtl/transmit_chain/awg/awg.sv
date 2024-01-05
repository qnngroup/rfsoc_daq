// awg.sv - Reed Foster
// Arbitrary waveform generator
// Simple buffer that loads a waveform from DMA and then transmits the
// waveform when triggered from an axi-stream interface
// Also outputs a trigger signal which can be used by the receive signal chain
// to start a capture

module awg #(
  parameter int DEPTH = 2048,
  parameter int PARALLEL_SAMPLES = 16,
  parameter int SAMPLE_WIDTH = 16,
  parameter int CHANNELS = 8
) (
  input wire dma_clk, dma_reset,
  Axis_If.Slave_Full dma_data_in,
  Axis_If.Slave_Stream

  input wire dac_clk, dac_reset,
  Axis_Parallel_If.Master_Stream dac_data_out

  output logic [CHANNELS-1:0] dac_trigger
);
