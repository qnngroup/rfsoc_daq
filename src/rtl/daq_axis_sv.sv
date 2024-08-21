// daq_axis_sv.sv - Reed Foster
// DAQ toplevel with separate AXI-stream interface for each signal chain
// submodule configuration register
// Breaks out SV interfaces into verilog-compatible ports so that the toplevel
// can be instantiated in a block diagram

`timescale 1ns/1ps
module daq_axis_sv #(
  // DDS parameters
  parameter int DDS_PHASE_BITS, // default 32
  parameter int DDS_QUANT_BITS, // default 20
  // DAC prescaler parameters
  parameter int SCALE_WIDTH, // default 18
  parameter int OFFSET_WIDTH, // default 14
  parameter int SCALE_INT_BITS, // default 2
  // AWG parameters
  parameter int AWG_DEPTH, // default 2048
  // Triangle wave parameters
  parameter int TRI_PHASE_BITS, // default 32
 
  // Sample discriminator parameters
  parameter int DISCRIMINATOR_MAX_DELAY, // default 64
  parameter int BUFFER_READ_LATENCY // default 4
) (
  input logic ps_clk,
  input logic ps_reset,

  //////////////////////////////////////////////////////
  // DMA DATASTREAMS
  //////////////////////////////////////////////////////
  // Timetagging sample buffer DMA output
  output  logic [rx_pkg::AXI_MM_WIDTH-1:0] m_axis_adc_dma_tdata,
  output  logic                            m_axis_adc_dma_tvalid,
  output  logic                            m_axis_adc_dma_tlast,
  output  logic                     [15:0] m_axis_adc_dma_tkeep,
  input   logic                            m_axis_adc_dma_tready,
  // AWG DMA input
  input   logic [tx_pkg::AXI_MM_WIDTH-1:0] s_axis_awg_dma_tdata,
  input   logic                            s_axis_awg_dma_tvalid,
  input   logic                            s_axis_awg_dma_tlast,
  input   logic                     [15:0] s_axis_awg_dma_tkeep,
  output  logic                            s_axis_awg_dma_tready,

  //////////////////////////////////////////////////////
  // ADC STATUS
  //////////////////////////////////////////////////////
  // sample write depth
  output  logic [rx_pkg::CHANNELS*($clog2(buffer_pkg::SAMPLE_BUFFER_DEPTH)+1)-1:0]  m_axis_samples_write_depth_tdata,
  output  logic                                                                     m_axis_samples_write_depth_tvalid,
  output  logic                                                                     m_axis_samples_write_depth_tlast,
  input   logic                                                                     m_axis_samples_write_depth_tready,
  // timestamp write depth
  output  logic [rx_pkg::CHANNELS*($clog2(buffer_pkg::TSTAMP_BUFFER_DEPTH)+1)-1:0]  m_axis_timestamps_write_depth_tdata,
  output  logic                                                                     m_axis_timestamps_write_depth_tvalid,
  output  logic                                                                     m_axis_timestamps_write_depth_tlast,
  input   logic                                                                     m_axis_timestamps_write_depth_tready,
  //////////////////////////////////////////////////////
  // ADC CONFIGURATION
  //////////////////////////////////////////////////////
  // buffer capture arm/start/stop
  input   logic [2:0]                                 s_axis_capture_arm_start_stop_tdata,
  input   logic                                       s_axis_capture_arm_start_stop_tvalid,
  output  logic                                       s_axis_capture_arm_start_stop_tready,
  // buffer banking mode
  input   logic [buffer_pkg::BANKING_MODE_WIDTH-1:0]  s_axis_capture_banking_mode_tdata,
  input   logic                                       s_axis_capture_banking_mode_tvalid,
  output  logic                                       s_axis_capture_banking_mode_tready,
  // buffer capture reset
  input   logic                                       s_axis_capture_sw_reset_tdata,
  input   logic                                       s_axis_capture_sw_reset_tvalid,
  output  logic                                       s_axis_capture_sw_reset_tready,
  // buffer readout reset
  input   logic                                       s_axis_readout_sw_reset_tdata,
  input   logic                                       s_axis_readout_sw_reset_tvalid,
  output  logic                                       s_axis_readout_sw_reset_tready,
  // buffer readout start
  input   logic                                       s_axis_readout_start_tdata,
  input   logic                                       s_axis_readout_start_tvalid,
  output  logic                                       s_axis_readout_start_tready,
  // sample discriminator thresholds
  input   logic [2*rx_pkg::CHANNELS*rx_pkg::SAMPLE_WIDTH-1:0]                     s_axis_discriminator_thresholds_tdata,
  input   logic                                                                   s_axis_discriminator_thresholds_tvalid,
  output  logic                                                                   s_axis_discriminator_thresholds_tready,
  // sample discriminator delays
  input   logic [3*rx_pkg::CHANNELS*$clog2(DISCRIMINATOR_MAX_DELAY)-1:0]          s_axis_discriminator_delays_tdata,
  input   logic                                                                   s_axis_discriminator_delays_tvalid,
  output  logic                                                                   s_axis_discriminator_delays_tready,
  // sample discriminator trigger select
  input   logic [rx_pkg::CHANNELS*$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS)-1:0]  s_axis_discriminator_trigger_source_tdata,
  input   logic                                                                   s_axis_discriminator_trigger_source_tvalid,
  output  logic                                                                   s_axis_discriminator_trigger_source_tready,
  // sample discriminator bypass
  input   logic [rx_pkg::CHANNELS-1:0]                                            s_axis_discriminator_bypass_tdata,
  input   logic                                                                   s_axis_discriminator_bypass_tvalid,
  output  logic                                                                   s_axis_discriminator_bypass_tready,
  // channel mux config
  input   logic [$clog2(2*rx_pkg::CHANNELS)*rx_pkg::CHANNELS-1:0] s_axis_receive_channel_mux_config_tdata,
  input   logic                                                   s_axis_receive_channel_mux_config_tvalid,
  output  logic                                                   s_axis_receive_channel_mux_config_tready,
  // capture trigger config
  input   logic [1+tx_pkg::CHANNELS-1:0]  s_axis_capture_trigger_config_tdata,
  input   logic                           s_axis_capture_trigger_config_tvalid,
  output  logic                           s_axis_capture_trigger_config_tready,
  // LMH6401 configuration
  input   logic [16+$clog2(rx_pkg::CHANNELS)-1:0] s_axis_lmh6401_config_tdata,
  input   logic                                   s_axis_lmh6401_config_tvalid,
  output  logic                                   s_axis_lmh6401_config_tready,

  //////////////////////////////////////////////////////
  // DAC STATUS
  //////////////////////////////////////////////////////
  // DMA error
  output  logic [1:0] m_axis_awg_dma_error_tdata,
  output  logic       m_axis_awg_dma_error_tvalid,
  output  logic       m_axis_awg_dma_error_tlast,
  input   logic       m_axis_awg_dma_error_tready,

  //////////////////////////////////////////////////////
  // DAC CONFIGURATION
  //////////////////////////////////////////////////////
  // AWG frame depth
  input   logic [$clog2(AWG_DEPTH)*tx_pkg::CHANNELS-1:0]  s_axis_awg_frame_depth_tdata,
  input   logic                                           s_axis_awg_frame_depth_tvalid,
  output  logic                                           s_axis_awg_frame_depth_tready,
  // AWG trigger output config
  input   logic [2*tx_pkg::CHANNELS-1:0]                  s_axis_awg_trigger_config_tdata,
  input   logic                                           s_axis_awg_trigger_config_tvalid,
  output  logic                                           s_axis_awg_trigger_config_tready,
  // AWG burst length
  input   logic [64*tx_pkg::CHANNELS-1:0]                 s_axis_awg_burst_length_tdata,
  input   logic                                           s_axis_awg_burst_length_tvalid,
  output  logic                                           s_axis_awg_burst_length_tready,
  // AWG start/stop
  input   logic [1:0]                                     s_axis_awg_start_stop_tdata,
  input   logic                                           s_axis_awg_start_stop_tvalid,
  output  logic                                           s_axis_awg_start_stop_tready,
  // DAC scale/offset
  input   logic [(SCALE_WIDTH+OFFSET_WIDTH)*tx_pkg::CHANNELS-1:0] s_axis_dac_scale_offset_tdata,
  input   logic                                                   s_axis_dac_scale_offset_tvalid,
  output  logic                                                   s_axis_dac_scale_offset_tready,
  // DDS phase increment
  input   logic [DDS_PHASE_BITS*tx_pkg::CHANNELS-1:0] s_axis_dds_phase_inc_tdata,
  input   logic                                       s_axis_dds_phase_inc_tvalid,
  output  logic                                       s_axis_dds_phase_inc_tready,
  // Triangle-wave phase increment
  input   logic [TRI_PHASE_BITS*tx_pkg::CHANNELS-1:0] s_axis_tri_phase_inc_tdata,
  input   logic                                       s_axis_tri_phase_inc_tvalid,
  output  logic                                       s_axis_tri_phase_inc_tready,
  // DAC siggen source mux
  input   logic [$clog2(3*tx_pkg::CHANNELS)*tx_pkg::CHANNELS-1:0] s_axis_transmit_channel_mux_tdata,
  input   logic                                                   s_axis_transmit_channel_mux_tvalid,
  output  logic                                                   s_axis_transmit_channel_mux_tready,

  //////////////////////////////////////////////////////
  // ADC SIGNAL PATH
  //////////////////////////////////////////////////////
  input logic adc_clk,
  input logic adc_reset,
  // adc data in
  input   logic [rx_pkg::DATA_WIDTH-1:0]  s00_axis_adc_tdata,
  input   logic                           s00_axis_adc_tvalid,
  input   logic [rx_pkg::DATA_WIDTH-1:0]  s02_axis_adc_tdata,
  input   logic                           s02_axis_adc_tvalid,
  input   logic [rx_pkg::DATA_WIDTH-1:0]  s10_axis_adc_tdata,
  input   logic                           s10_axis_adc_tvalid,
  input   logic [rx_pkg::DATA_WIDTH-1:0]  s12_axis_adc_tdata,
  input   logic                           s12_axis_adc_tvalid,
  input   logic [rx_pkg::DATA_WIDTH-1:0]  s20_axis_adc_tdata,
  input   logic                           s20_axis_adc_tvalid,
  input   logic [rx_pkg::DATA_WIDTH-1:0]  s22_axis_adc_tdata,
  input   logic                           s22_axis_adc_tvalid,
  input   logic [rx_pkg::DATA_WIDTH-1:0]  s30_axis_adc_tdata,
  input   logic                           s30_axis_adc_tvalid,
  input   logic [rx_pkg::DATA_WIDTH-1:0]  s32_axis_adc_tdata,
  input   logic                           s32_axis_adc_tvalid,

  //////////////////////////////////////////////////////
  // DAC SIGNAL PATH
  //////////////////////////////////////////////////////
  input logic dac_clk,
  input logic dac_reset,
  // dac data out
  output  logic [tx_pkg::DATA_WIDTH-1:0]  m00_axis_dac_tdata,
  output  logic                           m00_axis_dac_tvalid,
  output  logic [tx_pkg::DATA_WIDTH-1:0]  m01_axis_dac_tdata,
  output  logic                           m01_axis_dac_tvalid,
  output  logic [tx_pkg::DATA_WIDTH-1:0]  m02_axis_dac_tdata,
  output  logic                           m02_axis_dac_tvalid,
  output  logic [tx_pkg::DATA_WIDTH-1:0]  m03_axis_dac_tdata,
  output  logic                           m03_axis_dac_tvalid,
  output  logic [tx_pkg::DATA_WIDTH-1:0]  m10_axis_dac_tdata,
  output  logic                           m10_axis_dac_tvalid,
  output  logic [tx_pkg::DATA_WIDTH-1:0]  m11_axis_dac_tdata,
  output  logic                           m11_axis_dac_tvalid,
  output  logic [tx_pkg::DATA_WIDTH-1:0]  m12_axis_dac_tdata,
  output  logic                           m12_axis_dac_tvalid,
  output  logic [tx_pkg::DATA_WIDTH-1:0]  m13_axis_dac_tdata,
  output  logic                           m13_axis_dac_tvalid,

  //////////////////////////////////////////////////////
  // SPI
  //////////////////////////////////////////////////////
  output logic [rx_pkg::CHANNELS-1:0] lmh6401_cs_n,
  output logic                        lmh6401_sck,
  output logic                        lmh6401_sdi
);

///////////////////////////
// DMA interfaces
///////////////////////////
// ADC
Axis_If #(.DWIDTH(rx_pkg::AXI_MM_WIDTH)) m_axis_adc_dma ();
assign m_axis_adc_dma_tdata   = m_axis_adc_dma.data;
assign m_axis_adc_dma_tvalid  = m_axis_adc_dma.valid;
assign m_axis_adc_dma_tlast   = m_axis_adc_dma.last;
assign m_axis_adc_dma_tkeep   = '1;
assign m_axis_adc_dma.ready   = m_axis_adc_dma_tready;
// AWG
Axis_If #(.DWIDTH(tx_pkg::AXI_MM_WIDTH)) s_axis_awg_dma ();
assign s_axis_awg_dma.data   = s_axis_awg_dma_tdata;
assign s_axis_awg_dma.valid  = s_axis_awg_dma_tvalid;
assign s_axis_awg_dma.last   = s_axis_awg_dma_tlast;
assign s_axis_awg_dma_tready = s_axis_awg_dma.ready;

///////////////////////////
// ADC status: write depth
///////////////////////////
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*($clog2(buffer_pkg::SAMPLE_BUFFER_DEPTH)+1)))  m_axis_samples_write_depth ();
assign m_axis_samples_write_depth_tdata   = m_axis_samples_write_depth.data;
assign m_axis_samples_write_depth_tvalid  = m_axis_samples_write_depth.valid;
assign m_axis_samples_write_depth_tlast   = m_axis_samples_write_depth.last;
assign m_axis_samples_write_depth.ready   = m_axis_samples_write_depth_tready;
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*($clog2(buffer_pkg::TSTAMP_BUFFER_DEPTH)+1)))  m_axis_timestamps_write_depth ();
assign m_axis_timestamps_write_depth_tdata   = m_axis_timestamps_write_depth.data;
assign m_axis_timestamps_write_depth_tvalid  = m_axis_timestamps_write_depth.valid;
assign m_axis_timestamps_write_depth_tlast   = m_axis_timestamps_write_depth.last;
assign m_axis_timestamps_write_depth.ready   = m_axis_timestamps_write_depth_tready;
///////////////////////////
// ADC configuration
///////////////////////////
// buffer capture arm/start/stop
Axis_If #(.DWIDTH(3)) s_axis_capture_arm_start_stop ();
assign s_axis_capture_arm_start_stop.data   = s_axis_capture_arm_start_stop_tdata;
assign s_axis_capture_arm_start_stop.valid  = s_axis_capture_arm_start_stop_tvalid;
assign s_axis_capture_arm_start_stop_tready = s_axis_capture_arm_start_stop.ready;
// buffer banking mode
Axis_If #(.DWIDTH(buffer_pkg::BANKING_MODE_WIDTH)) s_axis_capture_banking_mode ();
assign s_axis_capture_banking_mode.data   = s_axis_capture_banking_mode_tdata;
assign s_axis_capture_banking_mode.valid  = s_axis_capture_banking_mode_tvalid;
assign s_axis_capture_banking_mode_tready = s_axis_capture_banking_mode.ready;
// buffer capture reset
Axis_If #(.DWIDTH(1)) s_axis_capture_sw_reset ();
assign s_axis_capture_sw_reset.data   = s_axis_capture_sw_reset_tdata;
assign s_axis_capture_sw_reset.valid  = s_axis_capture_sw_reset_tvalid;
assign s_axis_capture_sw_reset_tready = s_axis_capture_sw_reset.ready;
// buffer readout reset
Axis_If #(.DWIDTH(1)) s_axis_readout_sw_reset ();
assign s_axis_readout_sw_reset.data   = s_axis_readout_sw_reset_tdata;
assign s_axis_readout_sw_reset.valid  = s_axis_readout_sw_reset_tvalid;
assign s_axis_readout_sw_reset_tready = s_axis_readout_sw_reset.ready;
// buffer readout start
Axis_If #(.DWIDTH(1)) s_axis_readout_start ();
assign s_axis_readout_start.data   = s_axis_readout_start_tdata;
assign s_axis_readout_start.valid  = s_axis_readout_start_tvalid;
assign s_axis_readout_start_tready = s_axis_readout_start.ready;
// sample discriminator thresholds
Axis_If #(.DWIDTH(2*rx_pkg::CHANNELS*rx_pkg::SAMPLE_WIDTH)) s_axis_discriminator_thresholds ();
assign s_axis_discriminator_thresholds.data   = s_axis_discriminator_thresholds_tdata;
assign s_axis_discriminator_thresholds.valid  = s_axis_discriminator_thresholds_tvalid;
assign s_axis_discriminator_thresholds_tready = s_axis_discriminator_thresholds.ready;
// sample discriminator delays
Axis_If #(.DWIDTH(3*rx_pkg::CHANNELS*$clog2(DISCRIMINATOR_MAX_DELAY))) s_axis_discriminator_delays ();
assign s_axis_discriminator_delays.data   = s_axis_discriminator_delays_tdata;
assign s_axis_discriminator_delays.valid  = s_axis_discriminator_delays_tvalid;
assign s_axis_discriminator_delays_tready = s_axis_discriminator_delays.ready;
// sample discriminator trigger select
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS))) s_axis_discriminator_trigger_source ();
assign s_axis_discriminator_trigger_source.data   = s_axis_discriminator_trigger_source_tdata;
assign s_axis_discriminator_trigger_source.valid  = s_axis_discriminator_trigger_source_tvalid;
assign s_axis_discriminator_trigger_source_tready = s_axis_discriminator_trigger_source.ready;
// sample discriminator bypass
Axis_If #(.DWIDTH(rx_pkg::CHANNELS)) s_axis_discriminator_bypass ();
assign s_axis_discriminator_bypass.data   = s_axis_discriminator_bypass_tdata;
assign s_axis_discriminator_bypass.valid  = s_axis_discriminator_bypass_tvalid;
assign s_axis_discriminator_bypass_tready = s_axis_discriminator_bypass.ready;
// channel mux config
Axis_If #(.DWIDTH($clog2(2*rx_pkg::CHANNELS)*rx_pkg::CHANNELS)) s_axis_receive_channel_mux_config ();
assign s_axis_receive_channel_mux_config.data   = s_axis_receive_channel_mux_config_tdata;
assign s_axis_receive_channel_mux_config.valid  = s_axis_receive_channel_mux_config_tvalid;
assign s_axis_receive_channel_mux_config_tready = s_axis_receive_channel_mux_config.ready;
// capture trigger config
Axis_If #(.DWIDTH(1+tx_pkg::CHANNELS)) s_axis_capture_trigger_config ();
assign s_axis_capture_trigger_config.data   = s_axis_capture_trigger_config_tdata;
assign s_axis_capture_trigger_config.valid  = s_axis_capture_trigger_config_tvalid;
assign s_axis_capture_trigger_config_tready = s_axis_capture_trigger_config.ready;

///////////////////////////
// LMH6401 configuration
///////////////////////////
Axis_If #(.DWIDTH(16+$clog2(tx_pkg::CHANNELS))) s_axis_lmh6401_config ();
assign s_axis_lmh6401_config.data   = s_axis_lmh6401_config_tdata;
assign s_axis_lmh6401_config.valid  = s_axis_lmh6401_config_tvalid;
assign s_axis_lmh6401_config_tready = s_axis_lmh6401_config.ready;

SPI_Parallel_If #(.CHANNELS(rx_pkg::CHANNELS)) lmh6401_spi ();
assign lmh6401_cs_n = lmh6401_spi.cs_n;
assign lmh6401_sck = lmh6401_spi.sck;
assign lmh6401_sdi = lmh6401_spi.sdi;

///////////////////////////
// DAC status: DMA error
///////////////////////////
Axis_If #(.DWIDTH(2)) m_axis_awg_dma_error ();
assign m_axis_awg_dma_error_tdata   = m_axis_awg_dma_error.data;
assign m_axis_awg_dma_error_tvalid  = m_axis_awg_dma_error.valid;
assign m_axis_awg_dma_error_tlast   = m_axis_awg_dma_error.last;
assign m_axis_awg_dma_error.ready   = m_axis_awg_dma_error_tready;

///////////////////////////
// DAC configuration
///////////////////////////
// AWG frame depth
Axis_If #(.DWIDTH($clog2(AWG_DEPTH)*tx_pkg::CHANNELS)) s_axis_awg_frame_depth ();
assign s_axis_awg_frame_depth.data   = s_axis_awg_frame_depth_tdata;
assign s_axis_awg_frame_depth.valid  = s_axis_awg_frame_depth_tvalid;
assign s_axis_awg_frame_depth_tready = s_axis_awg_frame_depth.ready;
// AWG trigger output config
Axis_If #(.DWIDTH(2*tx_pkg::CHANNELS)) s_axis_awg_trigger_config ();
assign s_axis_awg_trigger_config.data   = s_axis_awg_trigger_config_tdata;
assign s_axis_awg_trigger_config.valid  = s_axis_awg_trigger_config_tvalid;
assign s_axis_awg_trigger_config_tready = s_axis_awg_trigger_config.ready;
// AWG burst length
Axis_If #(.DWIDTH(64*tx_pkg::CHANNELS)) s_axis_awg_burst_length ();
assign s_axis_awg_burst_length.data   = s_axis_awg_burst_length_tdata;
assign s_axis_awg_burst_length.valid  = s_axis_awg_burst_length_tvalid;
assign s_axis_awg_burst_length_tready = s_axis_awg_burst_length.ready;
// AWG start/stop
Axis_If #(.DWIDTH(2)) s_axis_awg_start_stop ();
assign s_axis_awg_start_stop.data   = s_axis_awg_start_stop_tdata;
assign s_axis_awg_start_stop.valid  = s_axis_awg_start_stop_tvalid;
assign s_axis_awg_start_stop_tready = s_axis_awg_start_stop.ready;
// DAC scale/offset
Axis_If #(.DWIDTH((SCALE_WIDTH+OFFSET_WIDTH)*tx_pkg::CHANNELS)) s_axis_dac_scale_offset ();
assign s_axis_dac_scale_offset.data   = s_axis_dac_scale_offset_tdata;
assign s_axis_dac_scale_offset.valid  = s_axis_dac_scale_offset_tvalid;
assign s_axis_dac_scale_offset_tready = s_axis_dac_scale_offset.ready;
// DDS phase increment
Axis_If #(.DWIDTH(DDS_PHASE_BITS*tx_pkg::CHANNELS)) s_axis_dds_phase_inc ();
assign s_axis_dds_phase_inc.data   = s_axis_dds_phase_inc_tdata;
assign s_axis_dds_phase_inc.valid  = s_axis_dds_phase_inc_tvalid;
assign s_axis_dds_phase_inc_tready = s_axis_dds_phase_inc.ready;
// Triangle-wave phase increment
Axis_If #(.DWIDTH(TRI_PHASE_BITS*tx_pkg::CHANNELS)) s_axis_tri_phase_inc ();
assign s_axis_tri_phase_inc.data   = s_axis_tri_phase_inc_tdata;
assign s_axis_tri_phase_inc.valid  = s_axis_tri_phase_inc_tvalid;
assign s_axis_tri_phase_inc_tready = s_axis_tri_phase_inc.ready;
// DAC siggen source mux
Axis_If #(.DWIDTH($clog2(3*tx_pkg::CHANNELS)*tx_pkg::CHANNELS)) s_axis_transmit_channel_mux ();
assign s_axis_transmit_channel_mux.data   = s_axis_transmit_channel_mux_tdata;
assign s_axis_transmit_channel_mux.valid  = s_axis_transmit_channel_mux_tvalid;
assign s_axis_transmit_channel_mux_tready = s_axis_transmit_channel_mux.ready;

Realtime_Parallel_If #(.DWIDTH(tx_pkg::DATA_WIDTH), .CHANNELS(tx_pkg::CHANNELS)) m_dac_data_d ();
assign m00_axis_dac_tdata = m_dac_data_d.data[0];
assign m01_axis_dac_tdata = m_dac_data_d.data[1];
assign m02_axis_dac_tdata = m_dac_data_d.data[2];
assign m03_axis_dac_tdata = m_dac_data_d.data[3];
assign m10_axis_dac_tdata = m_dac_data_d.data[4];
assign m11_axis_dac_tdata = m_dac_data_d.data[5];
assign m12_axis_dac_tdata = m_dac_data_d.data[6];
assign m13_axis_dac_tdata = m_dac_data_d.data[7];
assign m00_axis_dac_tvalid = m_dac_data_d.valid[0];
assign m01_axis_dac_tvalid = m_dac_data_d.valid[1];
assign m02_axis_dac_tvalid = m_dac_data_d.valid[2];
assign m03_axis_dac_tvalid = m_dac_data_d.valid[3];
assign m10_axis_dac_tvalid = m_dac_data_d.valid[4];
assign m11_axis_dac_tvalid = m_dac_data_d.valid[5];
assign m12_axis_dac_tvalid = m_dac_data_d.valid[6];
assign m13_axis_dac_tvalid = m_dac_data_d.valid[7];
Realtime_Parallel_If #(.DWIDTH(tx_pkg::DATA_WIDTH), .CHANNELS(tx_pkg::CHANNELS)) m_dac_data ();
realtime_delay #(
  .DATA_WIDTH(tx_pkg::DATA_WIDTH),
  .CHANNELS(tx_pkg::CHANNELS),
  .DELAY(2)
) m_dac_delay_i (
  .clk(dac_clk),
  .reset(dac_reset),
  .data_in(m_dac_data),
  .data_out(m_dac_data_d)
);
Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) s_adc_data ();
assign s_adc_data.data[0] = s00_axis_adc_tdata;
assign s_adc_data.data[1] = s02_axis_adc_tdata;
assign s_adc_data.data[2] = s10_axis_adc_tdata;
assign s_adc_data.data[3] = s12_axis_adc_tdata;
assign s_adc_data.data[4] = s20_axis_adc_tdata;
assign s_adc_data.data[5] = s22_axis_adc_tdata;
assign s_adc_data.data[6] = s30_axis_adc_tdata;
assign s_adc_data.data[7] = s32_axis_adc_tdata;
assign s_adc_data.valid[0] = s00_axis_adc_tvalid;
assign s_adc_data.valid[1] = s02_axis_adc_tvalid;
assign s_adc_data.valid[2] = s10_axis_adc_tvalid;
assign s_adc_data.valid[3] = s12_axis_adc_tvalid;
assign s_adc_data.valid[4] = s20_axis_adc_tvalid;
assign s_adc_data.valid[5] = s22_axis_adc_tvalid;
assign s_adc_data.valid[6] = s30_axis_adc_tvalid;
assign s_adc_data.valid[7] = s32_axis_adc_tvalid;
Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) s_adc_data_d ();
realtime_delay #(
  .DATA_WIDTH(tx_pkg::DATA_WIDTH),
  .CHANNELS(tx_pkg::CHANNELS),
  .DELAY(2)
) s_adc_delay_i (
  .clk(adc_clk),
  .reset(adc_reset),
  .data_in(s_adc_data),
  .data_out(s_adc_data_d)
);
// CDC triggers from AWG -> sample buffer
// TODO actually implement proper deterministic-delay triggering
logic [tx_pkg::CHANNELS-1:0] adc_digital_triggers;
logic [tx_pkg::CHANNELS-1:0] dac_digital_triggers;
xpm_cdc_array_single #(
  .DEST_SYNC_FF(4), // number of registers used to sync to dest_clk
  .INIT_SYNC_FF(0), // disable simulation initialization of sync regs
  .SIM_ASSERT_CHK(1), // report potential misuse
  .SRC_INPUT_REG(1), // register input with src_clk
  .WIDTH(tx_pkg::CHANNELS)
) trigger_cdc_i (
  .dest_clk(adc_clk),
  .dest_out(adc_digital_triggers),
  .src_clk(dac_clk),
  .src_in(dac_digital_triggers)
);

///////////////////////////////////////////
// Receive top
///////////////////////////////////////////
receive_top #(
  .DISCRIMINATOR_MAX_DELAY(DISCRIMINATOR_MAX_DELAY),
  .BUFFER_READ_LATENCY(BUFFER_READ_LATENCY)
) rx_top_i (
  .adc_clk,
  .adc_reset,
  .adc_data_in(s_adc_data_d),
  .adc_digital_triggers,
  .ps_clk,
  .ps_reset,
  .ps_readout_data(m_axis_adc_dma),
  .ps_samples_write_depth(m_axis_samples_write_depth),
  .ps_timestamps_write_depth(m_axis_timestamps_write_depth),
  .ps_capture_arm_start_stop(s_axis_capture_arm_start_stop),
  .ps_capture_banking_mode(s_axis_capture_banking_mode),
  .ps_capture_sw_reset(s_axis_capture_sw_reset),
  .ps_readout_sw_reset(s_axis_readout_sw_reset),
  .ps_readout_start(s_axis_readout_start),
  .ps_discriminator_thresholds(s_axis_discriminator_thresholds),
  .ps_discriminator_delays(s_axis_discriminator_delays),
  .ps_discriminator_trigger_select(s_axis_discriminator_trigger_source),
  .ps_discriminator_bypass(s_axis_discriminator_bypass),
  .ps_channel_mux_config(s_axis_receive_channel_mux_config),
  .ps_capture_digital_trigger_select(s_axis_capture_trigger_config)
);

///////////////////////////////////////////
// SPI
///////////////////////////////////////////
lmh6401_spi #(
  .AXIS_CLK_FREQ(100_000_000),
  .SPI_CLK_FREQ(1_000_000),
  .NUM_CHANNELS(rx_pkg::CHANNELS)
) lmh6401_spi_i (
  .clk(ps_clk),
  .reset(ps_reset),
  .command_in(s_axis_lmh6401_config),
  .spi(lmh6401_spi)
);

///////////////////////////////////////////
// Transmit top
///////////////////////////////////////////
transmit_top #(
  .DDS_PHASE_BITS(DDS_PHASE_BITS),
  .DDS_QUANT_BITS(DDS_QUANT_BITS),
  .SCALE_WIDTH(SCALE_WIDTH),
  .OFFSET_WIDTH(OFFSET_WIDTH),
  .SCALE_INT_BITS(SCALE_INT_BITS),
  .AWG_DEPTH(AWG_DEPTH),
  .TRI_PHASE_BITS(TRI_PHASE_BITS)
) tx_top_i (
  .dac_clk,
  .dac_reset,
  .dac_data_out(m_dac_data),
  .dac_triggers_out(dac_digital_triggers),
  .ps_clk,
  .ps_reset,
  .ps_awg_dma_in(s_axis_awg_dma),
  .ps_awg_frame_depth(s_axis_awg_frame_depth),
  .ps_awg_trigger_out_config(s_axis_awg_trigger_config),
  .ps_awg_burst_length(s_axis_awg_burst_length),
  .ps_awg_start_stop(s_axis_awg_start_stop),
  .ps_awg_dma_error(m_axis_awg_dma_error),
  .ps_scale_offset(s_axis_dac_scale_offset),
  .ps_dds_phase_inc(s_axis_dds_phase_inc),
  .ps_tri_phase_inc(s_axis_tri_phase_inc),
  .ps_channel_mux_config(s_axis_transmit_channel_mux)
);

endmodule
