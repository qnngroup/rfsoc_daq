// transmit_top.sv - Reed Foster
// Toplevel for transmit signal chain, generates data from either DDS signal
// generator or from AWG arbitrary generator and sends the data tothe RFDAC

`timescale 1ns/1ps
module transmit_top #(
  // DDS parameters
  parameter int DDS_PHASE_BITS = 32,
  parameter int DDS_QUANT_BITS = 20,
  // DAC prescaler parameters
  parameter int SCALE_WIDTH = 18,
  parameter int OFFSET_WIDTH = 14,
  parameter int SCALE_INT_BITS = 2,
  // AWG parameters
  parameter int AWG_DEPTH = 2048,
  // Triangle wave parameters
  parameter int TRI_PHASE_BITS = 32
) (
  // DMA/PS clock domain: 100 MHz
  input wire ps_clk, ps_reset,

  // AWG PS interfaces
  Axis_If.Slave   ps_awg_dma_in, // DMA interface
  Axis_If.Slave   ps_awg_frame_depth, // $clog2(DEPTH)*tx_pkg::CHANNELS bits
  Axis_If.Slave   ps_awg_trigger_out_config, // 2*tx_pkg::CHANNELS bits
  Axis_If.Slave   ps_awg_burst_length, // 64*tx_pkg::CHANNELS bits
  Axis_If.Slave   ps_awg_start_stop, // 2 bits
  Axis_If.Master  ps_awg_dma_error, // 2 bits

  // DAC prescaler configuration
  Axis_If.Slave   ps_scale_offset, // (SCALE_WIDTH+OFFSET_WIDTH)*tx_pkg::CHANNELS

  // DDS configuration
  Axis_If.Slave   ps_dds_phase_inc, // DDS_PHASE_BITS*tx_pkg::CHANNELS

  // Triangle wave configuration
  Axis_If.Slave   ps_tri_phase_inc, // TRI_PHASE_BITS*tx_pkg::CHANNELS

  // Select which signal generator is in use
  Axis_If.Slave   ps_channel_mux_config, // $clog2(3*tx_pkg::CHANNELS)*tx_pkg::CHANNELS

  // RFDAC clock domain: 384 MHz
  input wire dac_clk, dac_reset,
  // Datapath
  Realtime_Parallel_If.Master dac_data_out,

  // Trigger output
  output logic [tx_pkg::CHANNELS-1:0] dac_triggers_out
);

////////////////////////////////////////////////////////////////////////////////
// Signal chain
////////////////////////////////////////////////////////////////////////////////
Realtime_Parallel_If #(.DWIDTH(tx_pkg::DATA_WIDTH), .CHANNELS(tx_pkg::CHANNELS)) dac_awg_data_out ();
Realtime_Parallel_If #(.DWIDTH(tx_pkg::DATA_WIDTH), .CHANNELS(tx_pkg::CHANNELS)) dac_dds_data_out ();
Realtime_Parallel_If #(.DWIDTH(tx_pkg::DATA_WIDTH), .CHANNELS(tx_pkg::CHANNELS)) dac_tri_data_out ();
Realtime_Parallel_If #(.DWIDTH(tx_pkg::DATA_WIDTH), .CHANNELS(3*tx_pkg::CHANNELS)) dac_mux_data_in ();
Realtime_Parallel_If #(.DWIDTH(tx_pkg::DATA_WIDTH), .CHANNELS(tx_pkg::CHANNELS)) dac_mux_data_out ();

logic [tx_pkg::CHANNELS-1:0] dac_awg_triggers;
awg #(
  .DEPTH(AWG_DEPTH)
) awg_i (
  .dma_clk(ps_clk),
  .dma_reset(ps_reset),
  .dma_data_in(ps_awg_dma_in),
  .dma_write_depth(ps_awg_frame_depth),
  .dma_trigger_out_config(ps_awg_trigger_out_config),
  .dma_awg_burst_length(ps_awg_burst_length),
  .dma_awg_start_stop(ps_awg_start_stop),
  .dma_transfer_error(ps_awg_dma_error),
  .dac_clk,
  .dac_reset,
  .dac_data_out(dac_awg_data_out),
  .dac_trigger(dac_awg_triggers)
);

// dds
dds #(
  .PHASE_BITS(DDS_PHASE_BITS),
  .QUANT_BITS(DDS_QUANT_BITS)
) dds_i (
  .ps_clk,
  .ps_reset,
  .ps_phase_inc(ps_dds_phase_inc),
  .dac_clk,
  .dac_reset,
  .dac_data_out(dac_dds_data_out)
);

// triangle wave
triangle #(
  .PHASE_BITS(TRI_PHASE_BITS),
  .CHANNELS(tx_pkg::CHANNELS),
  .PARALLEL_SAMPLES(tx_pkg::PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(tx_pkg::SAMPLE_WIDTH)
) tri_i (
  .ps_clk,
  .ps_reset,
  .ps_phase_inc(ps_tri_phase_inc),
  .dac_clk,
  .dac_reset,
  .dac_data_out(dac_tri_data_out),
  .dac_trigger() // don't use triangle triggers for now
);

// just send awg trigger out
assign dac_triggers_out = dac_awg_triggers;

// mux awg/dds/tri data
assign dac_mux_data_in.data[tx_pkg::CHANNELS-1:0] = dac_awg_data_out.data;
assign dac_mux_data_in.valid[tx_pkg::CHANNELS-1:0] = dac_awg_data_out.valid;
assign dac_mux_data_in.data[2*tx_pkg::CHANNELS-1:tx_pkg::CHANNELS] = dac_dds_data_out.data;
assign dac_mux_data_in.valid[2*tx_pkg::CHANNELS-1:tx_pkg::CHANNELS] = dac_dds_data_out.valid;
assign dac_mux_data_in.data[3*tx_pkg::CHANNELS-1:2*tx_pkg::CHANNELS] = dac_tri_data_out.data;
assign dac_mux_data_in.valid[3*tx_pkg::CHANNELS-1:2*tx_pkg::CHANNELS] = dac_tri_data_out.valid;

// mux
realtime_channel_mux #(
  .INPUT_CHANNELS(3*tx_pkg::CHANNELS),
  .OUTPUT_CHANNELS(tx_pkg::CHANNELS)
) channel_mux_i (
  .data_clk(dac_clk),
  .data_reset(dac_reset),
  .data_in(dac_mux_data_in),
  .data_out(dac_mux_data_out),
  .config_clk(ps_clk),
  .config_reset(ps_reset),
  .config_in(ps_channel_mux_config)
);

// scale and offset
realtime_affine #(
  .PARALLEL_SAMPLES(tx_pkg::PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(tx_pkg::SAMPLE_WIDTH),
  .CHANNELS(tx_pkg::CHANNELS),
  .SCALE_WIDTH(SCALE_WIDTH),
  .OFFSET_WIDTH(OFFSET_WIDTH),
  .SCALE_INT_BITS(SCALE_INT_BITS)
) dac_prescaler_i (
  .data_clk(dac_clk),
  .data_reset(dac_reset),
  .data_out(dac_data_out),
  .data_in(dac_mux_data_out),
  .config_clk(ps_clk),
  .config_reset(ps_reset),
  .config_scale_offset(ps_scale_offset)
);

endmodule
