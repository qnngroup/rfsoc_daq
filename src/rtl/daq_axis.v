// daq_axis.v - Reed Foster
// DAQ toplevel with separate AXI-stream interface for each signal chain
// submodule configuration register

`define ROUNDUP32(x) (32*(((x) + 31)/32))

`timescale 1ns/1ps
module daq_axis #(
  // DDS parameters
  parameter DDS_PHASE_BITS = 32, // default 32
  parameter DDS_QUANT_BITS = 20, // default 20
  // DAC prescaler parameters
  parameter SCALE_WIDTH = 16, // default 18
  parameter OFFSET_WIDTH = 16, // default 14
  parameter SCALE_INT_BITS = 2, // default 2
  // AWG parameters
  parameter AWG_DEPTH = 2048, // default 2048
  // Triangle wave parameters
  parameter TRI_PHASE_BITS = 32, // default 32

  // Sample discriminator parameters
  parameter DISCRIMINATOR_MAX_DELAY = 64, // default 64
  parameter BUFFER_READ_LATENCY = 4// default 4
) (
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ps_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "FREQ_HZ 99999001, ASSOCIATED_BUSIF \
    m_axis_adc_dma:\
    s_axis_awg_dma:\
    m_axis_samples_write_depth:\
    m_axis_timestamps_write_depth:\
    s_axis_capture_arm_start_stop:\
    s_axis_capture_banking_mode:\
    s_axis_capture_sw_reset:\
    s_axis_readout_sw_reset:\
    s_axis_readout_start:\
    s_axis_discriminator_thresholds:\
    s_axis_discriminator_delays:\
    s_axis_discriminator_trigger_source:\
    s_axis_discriminator_bypass:\
    s_axis_receive_channel_mux_config:\
    s_axis_capture_trigger_config:\
    s_axis_lmh6401_config:\
    m_axis_awg_dma_error:\
    s_axis_awg_frame_depth:\
    s_axis_awg_trigger_config:\
    s_axis_awg_burst_length:\
    s_axis_awg_start_stop:\
    s_axis_dac_scale_offset:\
    s_axis_dds_phase_inc:\
    s_axis_tri_phase_inc:\
    s_axis_transmit_channel_mux" *)
  input wire  ps_clk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ps_resetn RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input wire  ps_resetn,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_adc_dma TDATA" *)
  output wire [127:0] m_axis_adc_dma_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_adc_dma TVALID" *)
  output wire m_axis_adc_dma_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_adc_dma TLAST" *)
  output wire m_axis_adc_dma_tlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_adc_dma TKEEP" *)
  output wire [15:0] m_axis_adc_dma_tkeep,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_adc_dma TREADY" *)
  input wire  m_axis_adc_dma_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_dma TDATA" *)

  input wire  [127:0] s_axis_awg_dma_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_dma TVALID" *)
  input wire  s_axis_awg_dma_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_dma TLAST" *)
  input wire  s_axis_awg_dma_tlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_dma TKEEP" *)
  input wire  [15:0] s_axis_awg_dma_tkeep,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_dma TREADY" *)
  output wire s_axis_awg_dma_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_samples_write_depth TDATA" *)
  output wire [`ROUNDUP32(8*14)-1:0] m_axis_samples_write_depth_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_samples_write_depth TVALID" *)
  output wire m_axis_samples_write_depth_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_samples_write_depth TLAST" *)
  output wire m_axis_samples_write_depth_tlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_samples_write_depth TREADY" *)
  input wire m_axis_samples_write_depth_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_timestamps_write_depth TDATA" *)
  output wire [`ROUNDUP32(8*10)-1:0] m_axis_timestamps_write_depth_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_timestamps_write_depth TVALID" *)
  output wire m_axis_timestamps_write_depth_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_timestamps_write_depth TLAST" *)
  output wire m_axis_timestamps_write_depth_tlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_timestamps_write_depth TREADY" *)
  input wire m_axis_timestamps_write_depth_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_capture_arm_start_stop TDATA" *)
  input wire [31:0] s_axis_capture_arm_start_stop_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_capture_arm_start_stop TVALID" *)
  input wire s_axis_capture_arm_start_stop_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_capture_arm_start_stop TREADY" *)
  output wire s_axis_capture_arm_start_stop_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_capture_banking_mode TDATA" *)
  input wire [31:0] s_axis_capture_banking_mode_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_capture_banking_mode TVALID" *)
  input wire s_axis_capture_banking_mode_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_capture_banking_mode TREADY" *)
  output wire s_axis_capture_banking_mode_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_capture_sw_reset TDATA" *)
  input wire [31:0] s_axis_capture_sw_reset_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_capture_sw_reset TVALID" *)
  input wire s_axis_capture_sw_reset_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_capture_sw_reset TREADY" *)
  output wire s_axis_capture_sw_reset_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_readout_sw_reset TDATA" *)
  input wire [31:0] s_axis_readout_sw_reset_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_readout_sw_reset TVALID" *)
  input wire s_axis_readout_sw_reset_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_readout_sw_reset TREADY" *)
  output wire s_axis_readout_sw_reset_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_readout_start TDATA" *)
  input wire [31:0] s_axis_readout_start_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_readout_start TVALID" *)
  input wire s_axis_readout_start_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_readout_start TREADY" *)
  output wire s_axis_readout_start_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_discriminator_thresholds TDATA" *)
  input wire [`ROUNDUP32(2*8*16)-1:0] s_axis_discriminator_thresholds_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_discriminator_thresholds TVALID" *)
  input wire s_axis_discriminator_thresholds_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_discriminator_thresholds TREADY" *)
  output wire s_axis_discriminator_thresholds_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_discriminator_delays TDATA" *)
  input wire [`ROUNDUP32(3*8*$clog2(DISCRIMINATOR_MAX_DELAY))-1:0] s_axis_discriminator_delays_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_discriminator_delays TVALID" *)
  input wire s_axis_discriminator_delays_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_discriminator_delays TREADY" *)
  output wire s_axis_discriminator_delays_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_discriminator_trigger_source TDATA" *)
  input wire [8*$clog2(8+8)-1:0] s_axis_discriminator_trigger_source_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_discriminator_trigger_source TVALID" *)
  input wire s_axis_discriminator_trigger_source_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_discriminator_trigger_source TREADY" *)
  output wire s_axis_discriminator_trigger_source_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_discriminator_bypass TDATA" *)
  input wire [31:0] s_axis_discriminator_bypass_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_discriminator_bypass TVALID" *)
  input wire s_axis_discriminator_bypass_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_discriminator_bypass TREADY" *)
  output wire s_axis_discriminator_bypass_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_receive_channel_mux_config TDATA" *)
  input wire [8*$clog2(2*8)-1:0] s_axis_receive_channel_mux_config_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_receive_channel_mux_config TVALID" *)
  input wire s_axis_receive_channel_mux_config_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_receive_channel_mux_config TREADY" *)
  output wire s_axis_receive_channel_mux_config_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_capture_trigger_config TDATA" *)
  input wire [`ROUNDUP32(1+8)-1:0] s_axis_capture_trigger_config_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_capture_trigger_config TVALID" *)
  input wire s_axis_capture_trigger_config_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_capture_trigger_config TREADY" *)
  output wire s_axis_capture_trigger_config_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_lmh6401_config TDATA" *)
  input wire [`ROUNDUP32(16+3)-1:0] s_axis_lmh6401_config_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_lmh6401_config TVALID" *)
  input wire s_axis_lmh6401_config_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_lmh6401_config TREADY" *)
  output wire s_axis_lmh6401_config_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_awg_dma_error TDATA" *)
  output wire [`ROUNDUP32(2)-1:0] m_axis_awg_dma_error_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_awg_dma_error TVALID" *)
  output wire m_axis_awg_dma_error_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_awg_dma_error TLAST" *)
  output wire m_axis_awg_dma_error_tlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_awg_dma_error TREADY" *)
  input wire m_axis_awg_dma_error_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_frame_depth TDATA" *)
  input wire [`ROUNDUP32(8*$clog2(AWG_DEPTH))-1:0] s_axis_awg_frame_depth_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_frame_depth TVALID" *)
  input wire s_axis_awg_frame_depth_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_frame_depth TREADY" *)
  output wire s_axis_awg_frame_depth_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_trigger_config TDATA" *)
  input wire [`ROUNDUP32(8*2)-1:0] s_axis_awg_trigger_config_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_trigger_config TVALID" *)
  input wire s_axis_awg_trigger_config_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_trigger_config TREADY" *)
  output wire s_axis_awg_trigger_config_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_burst_length TDATA" *)
  input wire [64*8-1:0] s_axis_awg_burst_length_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_burst_length TVALID" *)
  input wire s_axis_awg_burst_length_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_burst_length TREADY" *)
  output wire s_axis_awg_burst_length_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_start_stop TDATA" *)
  input wire [`ROUNDUP32(2)-1:0] s_axis_awg_start_stop_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_start_stop TVALID" *)
  input wire s_axis_awg_start_stop_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_start_stop TREADY" *)
  output wire s_axis_awg_start_stop_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dac_scale_offset TDATA" *)
  input wire [`ROUNDUP32((SCALE_WIDTH+OFFSET_WIDTH)*8)-1:0] s_axis_dac_scale_offset_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dac_scale_offset TVALID" *)
  input wire s_axis_dac_scale_offset_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dac_scale_offset TREADY" *)
  output wire s_axis_dac_scale_offset_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dds_phase_inc TDATA" *)
  input wire [`ROUNDUP32(DDS_PHASE_BITS*8)-1:0] s_axis_dds_phase_inc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dds_phase_inc TVALID" *)
  input wire s_axis_dds_phase_inc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dds_phase_inc TREADY" *)
  output wire s_axis_dds_phase_inc_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_tri_phase_inc TDATA" *)
  input wire [`ROUNDUP32(TRI_PHASE_BITS*8)-1:0] s_axis_tri_phase_inc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_tri_phase_inc TVALID" *)
  input wire s_axis_tri_phase_inc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_tri_phase_inc TREADY" *)
  output wire s_axis_tri_phase_inc_tready,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_transmit_channel_mux TDATA" *)
  input wire [`ROUNDUP32(8*$clog2(3*8))-1:0] s_axis_transmit_channel_mux_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_transmit_channel_mux TVALID" *)
  input wire s_axis_transmit_channel_mux_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_transmit_channel_mux TREADY" *)
  output wire s_axis_transmit_channel_mux_tready,

  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 adc_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "FREQ_HZ 512000000, ASSOCIATED_BUSIF\
    s00_axis_adc:\
    s02_axis_adc:\
    s10_axis_adc:\
    s12_axis_adc:\
    s20_axis_adc:\
    s22_axis_adc:\
    s30_axis_adc:\
    s32_axis_adc" *)
  input wire adc_clk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 adc_resetn RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input wire adc_resetn,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s00_axis_adc TDATA" *)
  input wire [127:0] s00_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s00_axis_adc TVALID" *)
  input wire s00_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s02_axis_adc TDATA" *)
  input wire [127:0] s02_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s02_axis_adc TVALID" *)
  input wire s02_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s10_axis_adc TDATA" *)
  input wire [127:0] s10_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s10_axis_adc TVALID" *)
  input wire s10_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s12_axis_adc TDATA" *)
  input wire [127:0] s12_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s12_axis_adc TVALID" *)
  input wire s12_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s20_axis_adc TDATA" *)
  input wire [127:0] s20_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s20_axis_adc TVALID" *)
  input wire s20_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s22_axis_adc TDATA" *)
  input wire [127:0] s22_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s22_axis_adc TVALID" *)
  input wire s22_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s30_axis_adc TDATA" *)
  input wire [127:0] s30_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s30_axis_adc TVALID" *)
  input wire s30_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s32_axis_adc TDATA" *)
  input wire [127:0] s32_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s32_axis_adc TVALID" *)
  input wire s32_axis_adc_tvalid,

  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 dac_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "FREQ_HZ 384000000, ASSOCIATED_BUSIF\
    m00_axis_dac:\
    m01_axis_dac:\
    m02_axis_dac:\
    m03_axis_dac:\
    m10_axis_dac:\
    m11_axis_dac:\
    m12_axis_dac:\
    m13_axis_dac" *)
  input wire dac_clk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 dac_resetn RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input wire dac_resetn,

  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m00_axis_dac TDATA" *)
  output wire [255:0] m00_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m00_axis_dac TVALID" *)
  output wire m00_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m01_axis_dac TDATA" *)
  output wire [255:0] m01_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m01_axis_dac TVALID" *)
  output wire m01_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m02_axis_dac TDATA" *)
  output wire [255:0] m02_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m02_axis_dac TVALID" *)
  output wire m02_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m03_axis_dac TDATA" *)
  output wire [255:0] m03_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m03_axis_dac TVALID" *)
  output wire m03_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m10_axis_dac TDATA" *)
  output wire [255:0] m10_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m10_axis_dac TVALID" *)
  output wire m10_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m11_axis_dac TDATA" *)
  output wire [255:0] m11_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m11_axis_dac TVALID" *)
  output wire m11_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m12_axis_dac TDATA" *)
  output wire [255:0] m12_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m12_axis_dac TVALID" *)
  output wire m12_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m13_axis_dac TDATA" *)
  output wire [255:0] m13_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m13_axis_dac TVALID" *)
  output wire m13_axis_dac_tvalid,

  output wire [7:0] lmh6401_cs_n,
  output wire lmh6401_sck,
  output wire lmh6401_sdi
);

daq_axis_sv #(
  .DDS_PHASE_BITS         (DDS_PHASE_BITS),
  .DDS_QUANT_BITS         (DDS_QUANT_BITS),
  .SCALE_WIDTH            (SCALE_WIDTH),
  .OFFSET_WIDTH           (OFFSET_WIDTH),
  .SCALE_INT_BITS         (SCALE_INT_BITS),
  .AWG_DEPTH              (AWG_DEPTH),
  .TRI_PHASE_BITS         (TRI_PHASE_BITS),
  .DISCRIMINATOR_MAX_DELAY(DISCRIMINATOR_MAX_DELAY),
  .BUFFER_READ_LATENCY    (BUFFER_READ_LATENCY)
) daq_axis_sv_i (
  .ps_clk                                    (ps_clk),
  .ps_reset                                  (~ps_resetn),
  .m_axis_adc_dma_tdata                      (m_axis_adc_dma_tdata),
  .m_axis_adc_dma_tvalid                     (m_axis_adc_dma_tvalid),
  .m_axis_adc_dma_tlast                      (m_axis_adc_dma_tlast),
  .m_axis_adc_dma_tkeep                      (m_axis_adc_dma_tkeep),
  .m_axis_adc_dma_tready                     (m_axis_adc_dma_tready),
  .s_axis_awg_dma_tdata                      (s_axis_awg_dma_tdata),
  .s_axis_awg_dma_tvalid                     (s_axis_awg_dma_tvalid),
  .s_axis_awg_dma_tlast                      (s_axis_awg_dma_tlast),
  .s_axis_awg_dma_tkeep                      (s_axis_awg_dma_tkeep),
  .s_axis_awg_dma_tready                     (s_axis_awg_dma_tready),
  .m_axis_samples_write_depth_tdata          (m_axis_samples_write_depth_tdata[8*12-1:0]),
  .m_axis_samples_write_depth_tvalid         (m_axis_samples_write_depth_tvalid),
  .m_axis_samples_write_depth_tlast          (m_axis_samples_write_depth_tlast),
  .m_axis_samples_write_depth_tready         (m_axis_samples_write_depth_tready),
  .m_axis_timestamps_write_depth_tdata       (m_axis_timestamps_write_depth_tdata[8*10-1:0]),
  .m_axis_timestamps_write_depth_tvalid      (m_axis_timestamps_write_depth_tvalid),
  .m_axis_timestamps_write_depth_tlast       (m_axis_timestamps_write_depth_tlast),
  .m_axis_timestamps_write_depth_tready      (m_axis_timestamps_write_depth_tready),
  .s_axis_capture_arm_start_stop_tdata       (s_axis_capture_arm_start_stop_tdata[2:0]),
  .s_axis_capture_arm_start_stop_tvalid      (s_axis_capture_arm_start_stop_tvalid),
  .s_axis_capture_arm_start_stop_tready      (s_axis_capture_arm_start_stop_tready),
  .s_axis_capture_banking_mode_tdata         (s_axis_capture_banking_mode_tdata[1:0]),
  .s_axis_capture_banking_mode_tvalid        (s_axis_capture_banking_mode_tvalid),
  .s_axis_capture_banking_mode_tready        (s_axis_capture_banking_mode_tready),
  .s_axis_capture_sw_reset_tdata             (s_axis_capture_sw_reset_tdata[0]),
  .s_axis_capture_sw_reset_tvalid            (s_axis_capture_sw_reset_tvalid),
  .s_axis_capture_sw_reset_tready            (s_axis_capture_sw_reset_tready),
  .s_axis_readout_sw_reset_tdata             (s_axis_readout_sw_reset_tdata[0]),
  .s_axis_readout_sw_reset_tvalid            (s_axis_readout_sw_reset_tvalid),
  .s_axis_readout_sw_reset_tready            (s_axis_readout_sw_reset_tready),
  .s_axis_readout_start_tdata                (s_axis_readout_start_tdata[0]),
  .s_axis_readout_start_tvalid               (s_axis_readout_start_tvalid),
  .s_axis_readout_start_tready               (s_axis_readout_start_tready),
  .s_axis_discriminator_thresholds_tdata     (s_axis_discriminator_thresholds_tdata[2*8*16-1:0]),
  .s_axis_discriminator_thresholds_tvalid    (s_axis_discriminator_thresholds_tvalid),
  .s_axis_discriminator_thresholds_tready    (s_axis_discriminator_thresholds_tready),
  .s_axis_discriminator_delays_tdata         (s_axis_discriminator_delays_tdata[3*8*6-1:0]),
  .s_axis_discriminator_delays_tvalid        (s_axis_discriminator_delays_tvalid),
  .s_axis_discriminator_delays_tready        (s_axis_discriminator_delays_tready),
  .s_axis_discriminator_trigger_source_tdata (s_axis_discriminator_trigger_source_tdata),
  .s_axis_discriminator_trigger_source_tvalid(s_axis_discriminator_trigger_source_tvalid),
  .s_axis_discriminator_trigger_source_tready(s_axis_discriminator_trigger_source_tready),
  .s_axis_discriminator_bypass_tdata         (s_axis_discriminator_bypass_tdata[7:0]),
  .s_axis_discriminator_bypass_tvalid        (s_axis_discriminator_bypass_tvalid),
  .s_axis_discriminator_bypass_tready        (s_axis_discriminator_bypass_tready),
  .s_axis_receive_channel_mux_config_tdata   (s_axis_receive_channel_mux_config_tdata),
  .s_axis_receive_channel_mux_config_tvalid  (s_axis_receive_channel_mux_config_tvalid),
  .s_axis_receive_channel_mux_config_tready  (s_axis_receive_channel_mux_config_tready),
  .s_axis_capture_trigger_config_tdata       (s_axis_capture_trigger_config_tdata[1+8-1:0]),
  .s_axis_capture_trigger_config_tvalid      (s_axis_capture_trigger_config_tvalid),
  .s_axis_capture_trigger_config_tready      (s_axis_capture_trigger_config_tready),
  .s_axis_lmh6401_config_tdata               (s_axis_lmh6401_config_tdata[16+3-1:0]),
  .s_axis_lmh6401_config_tvalid              (s_axis_lmh6401_config_tvalid),
  .s_axis_lmh6401_config_tready              (s_axis_lmh6401_config_tready),
  .m_axis_awg_dma_error_tdata                (m_axis_awg_dma_error_tdata[1:0]),
  .m_axis_awg_dma_error_tvalid               (m_axis_awg_dma_error_tvalid),
  .m_axis_awg_dma_error_tlast                (m_axis_awg_dma_error_tlast),
  .m_axis_awg_dma_error_tready               (m_axis_awg_dma_error_tready),
  .s_axis_awg_frame_depth_tdata              (s_axis_awg_frame_depth_tdata[8*$clog2(AWG_DEPTH)-1:0]),
  .s_axis_awg_frame_depth_tvalid             (s_axis_awg_frame_depth_tvalid),
  .s_axis_awg_frame_depth_tready             (s_axis_awg_frame_depth_tready),
  .s_axis_awg_trigger_config_tdata           (s_axis_awg_trigger_config_tdata[8*2-1:0]),
  .s_axis_awg_trigger_config_tvalid          (s_axis_awg_trigger_config_tvalid),
  .s_axis_awg_trigger_config_tready          (s_axis_awg_trigger_config_tready),
  .s_axis_awg_burst_length_tdata             (s_axis_awg_burst_length_tdata),
  .s_axis_awg_burst_length_tvalid            (s_axis_awg_burst_length_tvalid),
  .s_axis_awg_burst_length_tready            (s_axis_awg_burst_length_tready),
  .s_axis_awg_start_stop_tdata               (s_axis_awg_start_stop_tdata[1:0]),
  .s_axis_awg_start_stop_tvalid              (s_axis_awg_start_stop_tvalid),
  .s_axis_awg_start_stop_tready              (s_axis_awg_start_stop_tready),
  .s_axis_dac_scale_offset_tdata             (s_axis_dac_scale_offset_tdata[(SCALE_WIDTH+OFFSET_WIDTH)*8-1:0]),
  .s_axis_dac_scale_offset_tvalid            (s_axis_dac_scale_offset_tvalid),
  .s_axis_dac_scale_offset_tready            (s_axis_dac_scale_offset_tready),
  .s_axis_dds_phase_inc_tdata                (s_axis_dds_phase_inc_tdata[DDS_PHASE_BITS*8-1:0]),
  .s_axis_dds_phase_inc_tvalid               (s_axis_dds_phase_inc_tvalid),
  .s_axis_dds_phase_inc_tready               (s_axis_dds_phase_inc_tready),
  .s_axis_tri_phase_inc_tdata                (s_axis_tri_phase_inc_tdata[TRI_PHASE_BITS*8-1:0]),
  .s_axis_tri_phase_inc_tvalid               (s_axis_tri_phase_inc_tvalid),
  .s_axis_tri_phase_inc_tready               (s_axis_tri_phase_inc_tready),
  .s_axis_transmit_channel_mux_tdata         (s_axis_transmit_channel_mux_tdata[8*$clog2(3*8)-1:0]),
  .s_axis_transmit_channel_mux_tvalid        (s_axis_transmit_channel_mux_tvalid),
  .s_axis_transmit_channel_mux_tready        (s_axis_transmit_channel_mux_tready),
  .adc_clk                                   (adc_clk),
  .adc_reset                                 (~adc_resetn),
  .s00_axis_adc_tdata                        (s00_axis_adc_tdata),
  .s00_axis_adc_tvalid                       (s00_axis_adc_tvalid),
  .s02_axis_adc_tdata                        (s02_axis_adc_tdata),
  .s02_axis_adc_tvalid                       (s02_axis_adc_tvalid),
  .s10_axis_adc_tdata                        (s10_axis_adc_tdata),
  .s10_axis_adc_tvalid                       (s10_axis_adc_tvalid),
  .s12_axis_adc_tdata                        (s12_axis_adc_tdata),
  .s12_axis_adc_tvalid                       (s12_axis_adc_tvalid),
  .s20_axis_adc_tdata                        (s20_axis_adc_tdata),
  .s20_axis_adc_tvalid                       (s20_axis_adc_tvalid),
  .s22_axis_adc_tdata                        (s22_axis_adc_tdata),
  .s22_axis_adc_tvalid                       (s22_axis_adc_tvalid),
  .s30_axis_adc_tdata                        (s30_axis_adc_tdata),
  .s30_axis_adc_tvalid                       (s30_axis_adc_tvalid),
  .s32_axis_adc_tdata                        (s32_axis_adc_tdata),
  .s32_axis_adc_tvalid                       (s32_axis_adc_tvalid),
  .dac_clk                                   (dac_clk),
  .dac_reset                                 (~dac_resetn),
  .m00_axis_dac_tdata                        (m00_axis_dac_tdata),
  .m00_axis_dac_tvalid                       (m00_axis_dac_tvalid),
  .m01_axis_dac_tdata                        (m01_axis_dac_tdata),
  .m01_axis_dac_tvalid                       (m01_axis_dac_tvalid),
  .m02_axis_dac_tdata                        (m02_axis_dac_tdata),
  .m02_axis_dac_tvalid                       (m02_axis_dac_tvalid),
  .m03_axis_dac_tdata                        (m03_axis_dac_tdata),
  .m03_axis_dac_tvalid                       (m03_axis_dac_tvalid),
  .m10_axis_dac_tdata                        (m10_axis_dac_tdata),
  .m10_axis_dac_tvalid                       (m10_axis_dac_tvalid),
  .m11_axis_dac_tdata                        (m11_axis_dac_tdata),
  .m11_axis_dac_tvalid                       (m11_axis_dac_tvalid),
  .m12_axis_dac_tdata                        (m12_axis_dac_tdata),
  .m12_axis_dac_tvalid                       (m12_axis_dac_tvalid),
  .m13_axis_dac_tdata                        (m13_axis_dac_tdata),
  .m13_axis_dac_tvalid                       (m13_axis_dac_tvalid),
  .lmh6401_cs_n                              (lmh6401_cs_n),
  .lmh6401_sck                               (lmh6401_sck),
  .lmh6401_sdi                               (lmh6401_sdi)
);

endmodule
