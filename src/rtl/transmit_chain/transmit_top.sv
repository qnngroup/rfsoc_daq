// transmit_top.sv - Reed Foster
// Toplevel for transmit signal chain, generates data from either DDS signal
// generator or from AWG arbitrary generator and sends the data tothe RFDAC

module transmit_top #(
  parameter int CHANNELS = 8,
  parameter int PARALLEL_SAMPLES = 16,
  parameter int SAMPLE_WIDTH = 16,
  // DDS parameters
  parameter int DDS_PHASE_BITS = 32,
  parameter int DDS_QUANT_BITS = 20,
  // DAC prescaler parameters
  parameter int SCALE_WIDTH = 18,
  parameter int SCALE_FRAC_BITS = 16,
  // AWG parameters
  parameter int AWG_DEPTH = 2048,
  parameter int AXI_MM_WIDTH = 128
) (
  // DMA/PS clock domain: 100 MHz
  input wire ps_clk, ps_reset,

  // AWG PS interfaces
  Axis_If.Slave_Full ps_dma_in, // DMA interface
  Axis_If.Slave_Stream ps_awg_frame_depth, // (1+$clog2(DEPTH))*CHANNELS bits
  Axis_If.Slave_Stream ps_awg_trigger_out_config, // 2*CHANNELS bits
  Axis_If.Slave_Stream ps_awg_burst_length, // 64*CHANNELS bits
  Axis_If.Slave_Stream ps_awg_start_stop, // 2 bits
  Axis_If.Master_Stream ps_awg_dma_error, // 2 bits

  // DAC prescaler configuration
  Axis_If.Slave_Stream ps_scale_factor, // SCALE_WIDTH*CHANNELS

  // DDS configuration
  Axis_If.Slave_Stream ps_dds_phase_inc, // DDS_PHASE_BITS*CHANNELS

  // Trigger manager configuration
  Axis_If.Slave_Stream ps_trigger_config, // 1 + CHANNELS

  Axis_If.Slave_Stream ps_channel_mux_config, // $clog2(2*CHANNELS)*CHANNELS

  // RFDAC clock domain: 384 MHz
  input wire dac_clk, dac_reset,
  // Datapath
  Axis_Parallel_If.Master_Realtime dac_data_out,

  // Trigger output
  output logic dac_trigger_out
);

////////////////////////////////////////////////////////////////////////////////
// CDC for configuration registers for DAC prescaler and DDS
////////////////////////////////////////////////////////////////////////////////
Axis_If #(.DWIDTH(SCALE_WIDTH*CHANNELS)) dac_scale_factor ();
Axis_If #(.DWIDTH(DDS_PHASE_BITS*CHANNELS)) dac_dds_phase_inc ();
Axis_If #(.DWIDTH(1+CHANNELS)) dac_trigger_config ();
Axis_If #(.DWIDTH($clog2(CHANNELS*2)*CHANNELS)) dac_channel_mux_config ();
// Configuration registers are Axis_If.Realtime modports, so assign ready = 1'b1
assign dac_scale_factor.ready = 1'b1;
assign dac_dds_phase_inc.ready = 1'b1;
assign dac_trigger_config.ready = 1'b1;
assign dac_channel_mux_config.ready = 1'b1;

// synchronize dac_prescaler scale factor
axis_config_reg_cdc #(
  .DWIDTH(SCALE_WIDTH*CHANNELS)
) ps_to_dac_scale_factor_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_scale_factor),
  .dest_clk(dac_clk),
  .dest_reset(dac_reset),
  .dest(dac_scale_factor)
);

// synchronize DDS phase increment
axis_config_reg_cdc #(
  .DWIDTH(DDS_PHASE_BITS*CHANNELS)
) ps_to_dac_dds_phase_inc_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_dds_phase_inc),
  .dest_clk(dac_clk),
  .dest_reset(dac_reset),
  .dest(dac_dds_phase_inc)
);

// synchronize trigger configuration to RFDAC clock domain
axis_config_reg_cdc #(
  .DWIDTH(1+CHANNELS)
) ps_to_dac_trigger_config_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_trigger_config),
  .dest_clk(dac_clk),
  .dest_reset(dac_reset),
  .dest(dac_trigger_config)
);

// synchronize multiplexer configuration to RFDAC clock domain
axis_config_reg_cdc #(
  .DWIDTH($clog2(2*CHANNELS)*CHANNELS)
) ps_to_dac_mux_config_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_channel_mux_config),
  .dest_clk(dac_clk),
  .dest_reset(dac_reset),
  .dest(dac_channel_mux_config)
);

////////////////////////////////////////////////////////////////////////////////
// Signal chain
////////////////////////////////////////////////////////////////////////////////
Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_awg_data_out ();
Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_dds_data_out ();
Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(2*CHANNELS)) dac_mux_data_in ();
Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_mux_data_out ();

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
  .dma_data_in(ps_dma_in),
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

// combine awg triggers to send a single value to the ADC buffer
trigger_manager #(
  .CHANNELS(CHANNELS)
) trigger_manager_i (
  .clk(dac_clk),
  .reset(dac_reset),
  .triggers_in(dac_awg_triggers),
  .trigger_config(dac_trigger_config),
  .trigger_out(dac_trigger_out)
);

// dds
dds_multichannel #(
  .PHASE_BITS(DDS_PHASE_BITS),
  .QUANT_BITS(DDS_QUANT_BITS),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) dds_i (
  .clk(dac_clk),
  .reset(dac_reset),
  .data_out(dac_dds_data_out),
  .phase_inc_in(dac_dds_phase_inc)
);

assign dac_mux_data_in.data[CHANNELS-1:0] = dac_awg_data_out.data;
assign dac_mux_data_in.valid[CHANNELS-1:0] = dac_awg_data_out.valid;
assign dac_mux_data_in.data[2*CHANNELS-1:CHANNELS] = dac_dds_data_out.data;
assign dac_mux_data_in.valid[2*CHANNELS-1:CHANNELS] = dac_dds_data_out.valid;
assign dac_awg_data_out.ready = '1; // mux has realtime interface (no backpressure), so always accept data
assign dac_dds_data_out.ready = '1;

// mux
axis_channel_mux #(
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .INPUT_CHANNELS(2*CHANNELS),
  .OUTPUT_CHANNELS(CHANNELS)
) channel_mux_i (
  .clk(dac_clk),
  .reset(dac_reset),
  .data_in(dac_mux_data_in),
  .data_out(dac_mux_data_out),
  .config_in(dac_channel_mux_config)
);

Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_prescaler_out ();
assign dac_data_out.valid = dac_prescaler_out.valid;
assign dac_data_out.data = dac_prescaler_out.data;
assign dac_prescaler_out.ready = '1;

// scaler
dac_prescaler_multichannel #(
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .SAMPLE_FRAC_BITS(16),
  .SCALE_WIDTH(SCALE_WIDTH),
  .SCALE_FRAC_BITS(SCALE_FRAC_BITS),
  .CHANNELS(CHANNELS)
) dac_prescaler_i (
  .clk(dac_clk),
  .reset(dac_reset),
  .data_out(dac_prescaler_out),
  .data_in(dac_mux_data_out),
  .scale_factor(dac_scale_factor)
);

endmodule
