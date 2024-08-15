// transmit_top.sv - Reed Foster
// Toplevel for transmit signal chain, generates data from either DDS signal
// generator or from AWG arbitrary generator and sends the data tothe RFDAC

`timescale 1ns/1ps
module transmit_top #(
  parameter int CHANNELS = 8,
  parameter int PARALLEL_SAMPLES = 16,
  parameter int SAMPLE_WIDTH = 16,
  // DDS parameters
  parameter int DDS_PHASE_BITS = 32,
  parameter int DDS_QUANT_BITS = 20,
  // DAC prescaler parameters
  parameter int SCALE_WIDTH = 18,
  parameter int OFFSET_WIDTH = 14,
  parameter int SCALE_INT_BITS = 2,
  // AWG parameters
  parameter int AWG_DEPTH = 2048,
  parameter int AXI_MM_WIDTH = 128,
  // Triangle wave parameters
  parameter int TRI_PHASE_BITS = 32
) (
  // DMA/PS clock domain: 100 MHz
  input wire ps_clk, ps_reset,

  // AWG PS interfaces
  Axis_If.Slave   ps_awg_dma_in, // DMA interface
  Axis_If.Slave   ps_awg_frame_depth, // $clog2(DEPTH)*CHANNELS bits
  Axis_If.Slave   ps_awg_trigger_out_config, // 2*CHANNELS bits
  Axis_If.Slave   ps_awg_burst_length, // 64*CHANNELS bits
  Axis_If.Slave   ps_awg_start_stop, // 2 bits
  Axis_If.Master  ps_awg_dma_error, // 2 bits

  // DAC prescaler configuration
  Axis_If.Slave   ps_scale_offset, // (SCALE_WIDTH+OFFSET_WIDTH)*CHANNELS

  // DDS configuration
  Axis_If.Slave   ps_dds_phase_inc, // DDS_PHASE_BITS*CHANNELS

  // Triangle wave configuration
  Axis_If.Slave   ps_tri_phase_inc, // TRI_PHASE_BITS*CHANNELS

  // Trigger manager configuration
  Axis_If.Slave   ps_trigger_config, // 1 + 2*CHANNELS

  Axis_If.Slave   ps_channel_mux_config, // $clog2(3*CHANNELS)*CHANNELS

  // RFDAC clock domain: 384 MHz
  input wire dac_clk, dac_reset,
  // Datapath
  Realtime_Parallel_If.Master dac_data_out,

  // Trigger output
  output logic dac_trigger_out
);
////////////////////////////////////////////////////////////////////////////////
// CDC for configuration registers for DAC prescaler and DDS
////////////////////////////////////////////////////////////////////////////////
Axis_If #(.DWIDTH(1+2*CHANNELS)) dac_trigger_config ();

// synchronize trigger configuration to RFDAC clock domain
axis_config_reg_cdc #(
  .DWIDTH(1+2*CHANNELS)
) ps_to_dac_trigger_config_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_trigger_config),
  .dest_clk(dac_clk),
  .dest_reset(dac_reset),
  .dest(dac_trigger_config)
);

////////////////////////////////////////////////////////////////////////////////
// Signal chain
////////////////////////////////////////////////////////////////////////////////
Realtime_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_awg_data_out ();
Realtime_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_dds_data_out ();
Realtime_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_tri_data_out ();
Realtime_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(3*CHANNELS)) dac_mux_data_in ();
Realtime_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_mux_data_out ();

logic [CHANNELS-1:0] dac_awg_triggers;
awg #(
  .DEPTH(AWG_DEPTH),
  .AXI_MM_WIDTH(AXI_MM_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .CHANNELS(CHANNELS)
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
  .QUANT_BITS(DDS_QUANT_BITS),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) dds_i (
  .ps_clk,
  .ps_reset,
  .ps_phase_inc(ps_dds_phase_inc),
  .dac_clk,
  .dac_reset,
  .dac_data_out(dac_dds_data_out)
);

// triangle wave
logic [CHANNELS-1:0] dac_tri_triggers;
triangle #(
  .PHASE_BITS(TRI_PHASE_BITS),
  .CHANNELS(CHANNELS),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH)
) tri_i (
  .ps_clk,
  .ps_reset,
  .ps_phase_inc(ps_tri_phase_inc),
  .dac_clk,
  .dac_reset,
  .dac_data_out(dac_tri_data_out),
  .dac_trigger(dac_tri_triggers)
);

// combine awg/tri triggers to send a single value to the ADC buffer
logic [2*CHANNELS-1:0] dac_triggers_combined;
assign dac_triggers_combined = {dac_tri_triggers, dac_awg_triggers};
trigger_manager #(
  .CHANNELS(2*CHANNELS)
) trigger_manager_i (
  .clk(dac_clk),
  .reset(dac_reset),
  .triggers_in(dac_triggers_combined),
  .trigger_config(dac_trigger_config),
  .trigger_out(dac_trigger_out)
);

assign dac_mux_data_in.data[CHANNELS-1:0] = dac_awg_data_out.data;
assign dac_mux_data_in.valid[CHANNELS-1:0] = dac_awg_data_out.valid;
assign dac_mux_data_in.data[2*CHANNELS-1:CHANNELS] = dac_dds_data_out.data;
assign dac_mux_data_in.valid[2*CHANNELS-1:CHANNELS] = dac_dds_data_out.valid;
assign dac_mux_data_in.data[3*CHANNELS-1:2*CHANNELS] = dac_tri_data_out.data;
assign dac_mux_data_in.valid[3*CHANNELS-1:2*CHANNELS] = dac_tri_data_out.valid;

// mux
axis_channel_mux #(
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .INPUT_CHANNELS(3*CHANNELS),
  .OUTPUT_CHANNELS(CHANNELS)
) channel_mux_i (
  .data_clk(dac_clk),
  .data_reset(dac_reset),
  .data_in(dac_mux_data_in),
  .data_out(dac_mux_data_out),
  .config_clk(ps_clk),
  .config_reset(ps_reset),
  .config_in(ps_channel_mux_config)
);

// scaler
realtime_affine #(
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .CHANNELS(CHANNELS),
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
