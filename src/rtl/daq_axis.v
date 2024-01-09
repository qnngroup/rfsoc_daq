// daq_axis.v - Reed Foster
// DAQ toplevel with separate AXI-stream interface for each signal chain
// submodule configuration register

module daq_axis #(
  // Shared parameters
  parameter SAMPLE_WIDTH = 16, // width in bits of each sample
  parameter PARALLEL_SAMPLES = 16, // number of parallel samples per clock cycle per channel
  parameter CHANNELS = 8, // number of input channels
  parameter AXI_MM_WIDTH = 128, // width of DMA AXI-stream interface

  // Sparse sample buffer parameters
  parameter TSTAMP_BUFFER_DEPTH = 1024, // depth of timestamp buffer
  parameter DATA_BUFFER_DEPTH = 16384, // depth of data/sample buffer
  // Sample discriminator parameters
  parameter APPROX_CLOCK_WIDTH = 48, // requested width of timestamp

  // DDS parameters
  parameter DDS_PHASE_BITS = 32,
  parameter DDS_QUANT_BITS = 20,
  // DAC prescaler parameters
  parameter SCALE_WIDTH = 18,
  parameter SCALE_FRAC_BITS = 16,
  // AWG parameters
  parameter AWG_DEPTH = 2048
) (
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ps_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "FREQ_HZ 99999001, ASSOCIATED_BUSIF \
    s_axis_dma:\
    s_axis_sample_discriminator_config:\
    s_axis_buffer_config:\
    s_axis_buffer_start_stop:\
    s_axis_adc_mux_config:\
    m_axis_buffer_timestamp_width:\
    s_axis_awg_frame_depth:\
    s_axis_awg_burst_length:\
    s_axis_awg_trigger_out_config:\
    s_axis_awg_start_stop:\
    m_axis_awg_dma_error:\
    s_axis_dac_scale_config:\
    s_axis_dds_phase_inc:\
    s_axis_trigger_manager_config:\
    s_axis_dac_mux_config" *)
  input wire ps_clk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ps_rst RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input wire ps_reset,

  // dma input (AWG)
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dma TDATA" *)
  input   wire [AXI_MM_WIDTH-1:0] s_axis_dma_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dma TVALID" *)
  input   wire                    s_axis_dma_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dma TLAST" *)
  input   wire                    s_axis_dma_tlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dma TKEEP" *)
  input   wire             [15:0] s_axis_dma_tkeep,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dma TREADY" *)
  output  wire                    s_axis_dma_tready,

  //////////////////////////////////////////////////////
  // ADC CONFIGURATION
  //////////////////////////////////////////////////////
  // sample discriminator config
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_sample_discriminator_config TDATA" *)
  input   wire [2*CHANNELS*SAMPLE_WIDTH-1:0]      s_axis_sample_discriminator_config_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_sample_discriminator_config TVALID" *)
  input   wire                                    s_axis_sample_discriminator_config_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_sample_discriminator_config TREADY" *)
  output  wire                                    s_axis_sample_discriminator_config_tready,
  // sparse buffer config
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_buffer_config TDATA" *)
  input   wire [31:0]                             s_axis_buffer_config_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_buffer_config TVALID" *)
  input   wire                                    s_axis_buffer_config_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_buffer_config TREADY" *)
  output  wire                                    s_axis_buffer_config_tready,
  // buffer capture start/stop
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_buffer_start_stop TDATA" *)
  input   wire [31:0]                             s_axis_buffer_start_stop_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_buffer_start_stop TVALID" *)
  input   wire                                    s_axis_buffer_start_stop_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_buffer_start_stop TREADY" *)
  output  wire                                    s_axis_buffer_start_stop_tready,
  // RX channel mux config
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_adc_mux_config TDATA" *)
  input   wire [$clog2(2*CHANNELS)*CHANNELS-1:0]  s_axis_adc_mux_config_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_adc_mux_config TVALID" *)
  input   wire                                    s_axis_adc_mux_config_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_adc_mux_config TREADY" *)
  output  wire                                    s_axis_adc_mux_config_tready,
  // buffer timestamp width out
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_buffer_timestamp_width TDATA" *)
  output  wire [31:0]                             m_axis_buffer_timestamp_width_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_buffer_timestamp_width TVALID" *)
  output  wire                                    m_axis_buffer_timestamp_width_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_buffer_timestamp_width TREADY" *)
  input   wire                                    m_axis_buffer_timestamp_width_tready,

  //////////////////////////////////////////////////////
  // DAC CONFIGURATION
  //////////////////////////////////////////////////////
  // awg frame depth
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_frame_depth TDATA" *)
  input   wire [(1+$clog2(AWG_DEPTH))*CHANNELS-1:0] s_axis_awg_frame_depth_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_frame_depth TVALID" *)
  input   wire                                      s_axis_awg_frame_depth_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_frame_depth TREADY" *)
  output  wire                                      s_axis_awg_frame_depth_tready,
  // awg burst length
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_burst_length TDATA" *)
  input   wire [64*CHANNELS-1:0]                    s_axis_awg_burst_length_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_burst_length TVALID" *)
  input   wire                                      s_axis_awg_burst_length_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_burst_length TREADY" *)
  output  wire                                      s_axis_awg_burst_length_tready,
  // awg trigger output config
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_trigger_out_config TDATA" *)
  input   wire [31:0]                               s_axis_awg_trigger_out_config_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_trigger_out_config TVALID" *)
  input   wire                                      s_axis_awg_trigger_out_config_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_trigger_out_config TREADY" *)
  output  wire                                      s_axis_awg_trigger_out_config_tready,
  // awg start/stop
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_start_stop TDATA" *)
  input   wire [31:0]                               s_axis_awg_start_stop_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_start_stop TVALID" *)
  input   wire                                      s_axis_awg_start_stop_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_awg_start_stop TREADY" *)
  output  wire                                      s_axis_awg_start_stop_tready,
  // awg dma error
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_awg_dma_error TDATA" *)
  output  wire [31:0]                               m_axis_awg_dma_error_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_awg_dma_error TVALID" *)
  output  wire                                      m_axis_awg_dma_error_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_awg_dma_error TREADY" *)
  input   wire                                      m_axis_awg_dma_error_tready,
  // dac scale factor
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dac_scale_config TDATA" *)
  input   wire [SCALE_WIDTH*CHANNELS-1:0]           s_axis_dac_scale_config_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dac_scale_config TVALID" *)
  input   wire                                      s_axis_dac_scale_config_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dac_scale_config TREADY" *)
  output  wire                                      s_axis_dac_scale_config_tready,
  // dds phase increment
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dds_phase_inc TDATA" *)
  input   wire [DDS_PHASE_BITS*CHANNELS-1:0]        s_axis_dds_phase_inc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dds_phase_inc TVALID" *)
  input   wire                                      s_axis_dds_phase_inc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dds_phase_inc TREADY" *)
  output  wire                                      s_axis_dds_phase_inc_tready,
  // trigger manager config
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_trigger_manager_config TDATA" *)
  input   wire [31:0]                               s_axis_trigger_manager_config_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_trigger_manager_config TVALID" *)
  input   wire                                      s_axis_trigger_manager_config_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_trigger_manager_config TREADY" *)
  output  wire                                      s_axis_trigger_manager_config_tready,
  // TX channel mux config
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dac_mux_config TDATA" *)
  input   wire [$clog2(2*CHANNELS)*CHANNELS-1:0]    s_axis_dac_mux_config_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dac_mux_config TVALID" *)
  input   wire                                      s_axis_dac_mux_config_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s_axis_dac_mux_config TREADY" *)
  output  wire                                      s_axis_dac_mux_config_tready,

  //////////////////////////////////////////////////////
  // ADC SIGNAL PATH
  //////////////////////////////////////////////////////
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 adc_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "FREQ_HZ 256000000, ASSOCIATED_BUSIF \
    s00_axis_adc:\
    s02_axis_adc:\
    s10_axis_adc:\
    s12_axis_adc:\
    s20_axis_adc:\
    s22_axis_adc:\
    s30_axis_adc:\
    s32_axis_adc:\
    m_axis_dma" *)
  input wire adc_clk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 adc_rst RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input wire adc_reset,
  // adc data in
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s00_axis_adc TDATA" *)
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         s00_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s00_axis_adc TVALID" *)
  input   wire                                             s00_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s00_axis_adc TREADY" *)
  output  wire                                             s00_axis_adc_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s02_axis_adc TDATA" *)
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         s02_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s02_axis_adc TVALID" *)
  input   wire                                             s02_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s02_axis_adc TREADY" *)
  output  wire                                             s02_axis_adc_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s10_axis_adc TDATA" *)
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         s10_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s10_axis_adc TVALID" *)
  input   wire                                             s10_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s10_axis_adc TREADY" *)
  output  wire                                             s10_axis_adc_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s12_axis_adc TDATA" *)
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         s12_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s12_axis_adc TVALID" *)
  input   wire                                             s12_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s12_axis_adc TREADY" *)
  output  wire                                             s12_axis_adc_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s20_axis_adc TDATA" *)
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         s20_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s20_axis_adc TVALID" *)
  input   wire                                             s20_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s20_axis_adc TREADY" *)
  output  wire                                             s20_axis_adc_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s22_axis_adc TDATA" *)
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         s22_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s22_axis_adc TVALID" *)
  input   wire                                             s22_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s22_axis_adc TREADY" *)
  output  wire                                             s22_axis_adc_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s30_axis_adc TDATA" *)
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         s30_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s30_axis_adc TVALID" *)
  input   wire                                             s30_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s30_axis_adc TREADY" *)
  output  wire                                             s30_axis_adc_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s32_axis_adc TDATA" *)
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         s32_axis_adc_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s32_axis_adc TVALID" *)
  input   wire                                             s32_axis_adc_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 s32_axis_adc TREADY" *)
  output  wire                                             s32_axis_adc_tready,

  // dma output (Sparse sample buffer -- TODO rewrite with split clock domains
  // for buffer write and read so that this doesn't need an external CDC FIFO)
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_dma TDATA" *)
  output  wire [AXI_MM_WIDTH-1:0] m_axis_dma_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_dma TVALID" *)
  output  wire                    m_axis_dma_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_dma TLAST" *)
  output  wire                    m_axis_dma_tlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_dma TKEEP" *)
  output  wire             [15:0] m_axis_dma_tkeep,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m_axis_dma TREADY" *)
  input   wire                    m_axis_dma_tready,

  //////////////////////////////////////////////////////
  // DAC SIGNAL PATH
  //////////////////////////////////////////////////////
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 dac_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "FREQ_HZ 384000000, ASSOCIATED_BUSIF \
    m00_axis_dac:\
    m01_axis_dac:\
    m02_axis_dac:\
    m03_axis_dac:\
    m10_axis_dac:\
    m11_axis_dac:\
    m12_axis_dac:\
    m13_axis_dac" *)
  input wire dac_clk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 dac_rst RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input wire dac_reset,
  // dac data out
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m00_axis_dac TDATA" *)
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         m00_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m00_axis_dac TVALID" *)
  output  wire                                             m00_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m00_axis_dac TREADY" *)
  input   wire                                             m00_axis_dac_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m01_axis_dac TDATA" *)
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         m01_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m01_axis_dac TVALID" *)
  output  wire                                             m01_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m01_axis_dac TREADY" *)
  input   wire                                             m01_axis_dac_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m02_axis_dac TDATA" *)
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         m02_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m02_axis_dac TVALID" *)
  output  wire                                             m02_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m02_axis_dac TREADY" *)
  input   wire                                             m02_axis_dac_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m03_axis_dac TDATA" *)
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         m03_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m03_axis_dac TVALID" *)
  output  wire                                             m03_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m03_axis_dac TREADY" *)
  input   wire                                             m03_axis_dac_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m10_axis_dac TDATA" *)
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         m10_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m10_axis_dac TVALID" *)
  output  wire                                             m10_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m10_axis_dac TREADY" *)
  input   wire                                             m10_axis_dac_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m11_axis_dac TDATA" *)
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         m11_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m11_axis_dac TVALID" *)
  output  wire                                             m11_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m11_axis_dac TREADY" *)
  input   wire                                             m11_axis_dac_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m12_axis_dac TDATA" *)
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         m12_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m12_axis_dac TVALID" *)
  output  wire                                             m12_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m12_axis_dac TREADY" *)
  input   wire                                             m12_axis_dac_tready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m13_axis_dac TDATA" *)
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]         m13_axis_dac_tdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m13_axis_dac TVALID" *)
  output  wire                                             m13_axis_dac_tvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 m13_axis_dac TREADY" *)
  input   wire                                             m13_axis_dac_tready
);

assign m_axis_awg_dma_error_tdata[31:2] = 30'b0; // unused bits

daq_axis_sv #(
  .SAMPLE_WIDTH        (SAMPLE_WIDTH),
  .PARALLEL_SAMPLES    (PARALLEL_SAMPLES),
  .CHANNELS            (CHANNELS),
  .AXI_MM_WIDTH        (AXI_MM_WIDTH),
  .TSTAMP_BUFFER_DEPTH (TSTAMP_BUFFER_DEPTH),
  .DATA_BUFFER_DEPTH   (DATA_BUFFER_DEPTH),
  .APPROX_CLOCK_WIDTH  (APPROX_CLOCK_WIDTH),
  .DDS_PHASE_BITS      (DDS_PHASE_BITS),
  .DDS_QUANT_BITS      (DDS_QUANT_BITS),
  .SCALE_WIDTH         (SCALE_WIDTH),
  .SCALE_FRAC_BITS     (SCALE_FRAC_BITS),
  .AWG_DEPTH           (AWG_DEPTH)
) daq_axis_sv_i (
  .ps_clk                                             (ps_clk),
  .ps_reset                                           (~ps_reset),
  .s_axis_dma_tdata                                   (s_axis_dma_tdata),
  .s_axis_dma_tvalid                                  (s_axis_dma_tvalid),
  .s_axis_dma_tlast                                   (s_axis_dma_tlast),
  .s_axis_dma_tkeep                                   (s_axis_dma_tkeep),
  .s_axis_dma_tready                                  (s_axis_dma_tready),
  .s_axis_sample_discriminator_config_tdata           (s_axis_sample_discriminator_config_tdata),
  .s_axis_sample_discriminator_config_tvalid          (s_axis_sample_discriminator_config_tvalid),
  .s_axis_sample_discriminator_config_tready          (s_axis_sample_discriminator_config_tready),
  .s_axis_buffer_config_tdata                         (s_axis_buffer_config_tdata[$clog2($clog2(CHANNELS)+1)-1:0]),
  .s_axis_buffer_config_tvalid                        (s_axis_buffer_config_tvalid),
  .s_axis_buffer_config_tready                        (s_axis_buffer_config_tready),
  .s_axis_buffer_start_stop_tdata                     (s_axis_buffer_start_stop_tdata[1:0]),
  .s_axis_buffer_start_stop_tvalid                    (s_axis_buffer_start_stop_tvalid),
  .s_axis_buffer_start_stop_tready                    (s_axis_buffer_start_stop_tready),
  .s_axis_adc_mux_config_tdata                        (s_axis_adc_mux_config_tdata),
  .s_axis_adc_mux_config_tvalid                       (s_axis_adc_mux_config_tvalid),
  .s_axis_adc_mux_config_tready                       (s_axis_adc_mux_config_tready),
  .m_axis_buffer_timestamp_width_tdata                (m_axis_buffer_timestamp_width_tdata),
  .m_axis_buffer_timestamp_width_tvalid               (m_axis_buffer_timestamp_width_tvalid),
  .m_axis_buffer_timestamp_width_tready               (m_axis_buffer_timestamp_width_tready),
  .s_axis_awg_frame_depth_tdata                       (s_axis_awg_frame_depth_tdata),
  .s_axis_awg_frame_depth_tvalid                      (s_axis_awg_frame_depth_tvalid),
  .s_axis_awg_frame_depth_tready                      (s_axis_awg_frame_depth_tready),
  .s_axis_awg_burst_length_tdata                      (s_axis_awg_burst_length_tdata),
  .s_axis_awg_burst_length_tvalid                     (s_axis_awg_burst_length_tvalid),
  .s_axis_awg_burst_length_tready                     (s_axis_awg_burst_length_tready),
  .s_axis_awg_trigger_out_config_tdata                (s_axis_awg_trigger_out_config_tdata[2*CHANNELS-1:0]),
  .s_axis_awg_trigger_out_config_tvalid               (s_axis_awg_trigger_out_config_tvalid),
  .s_axis_awg_trigger_out_config_tready               (s_axis_awg_trigger_out_config_tready),
  .s_axis_awg_start_stop_tdata                        (s_axis_awg_start_stop_tdata[1:0]),
  .s_axis_awg_start_stop_tvalid                       (s_axis_awg_start_stop_tvalid),
  .s_axis_awg_start_stop_tready                       (s_axis_awg_start_stop_tready),
  .m_axis_awg_dma_error_tdata                         (m_axis_awg_dma_error_tdata[1:0]),
  .m_axis_awg_dma_error_tvalid                        (m_axis_awg_dma_error_tvalid),
  .m_axis_awg_dma_error_tready                        (m_axis_awg_dma_error_tready),
  .s_axis_dac_scale_config_tdata                      (s_axis_dac_scale_config_tdata),
  .s_axis_dac_scale_config_tvalid                     (s_axis_dac_scale_config_tvalid),
  .s_axis_dac_scale_config_tready                     (s_axis_dac_scale_config_tready),
  .s_axis_dds_phase_inc_tdata                         (s_axis_dds_phase_inc_tdata),
  .s_axis_dds_phase_inc_tvalid                        (s_axis_dds_phase_inc_tvalid),
  .s_axis_dds_phase_inc_tready                        (s_axis_dds_phase_inc_tready),
  .s_axis_trigger_manager_config_tdata                (s_axis_trigger_manager_config_tdata[CHANNELS:0]),
  .s_axis_trigger_manager_config_tvalid               (s_axis_trigger_manager_config_tvalid),
  .s_axis_trigger_manager_config_tready               (s_axis_trigger_manager_config_tready),
  .s_axis_dac_mux_config_tdata                        (s_axis_dac_mux_config_tdata),
  .s_axis_dac_mux_config_tvalid                       (s_axis_dac_mux_config_tvalid),
  .s_axis_dac_mux_config_tready                       (s_axis_dac_mux_config_tready),
  .adc_clk                                            (adc_clk),
  .adc_reset                                          (~adc_reset),
  .s00_axis_adc_tdata                                 (s00_axis_adc_tdata),
  .s00_axis_adc_tvalid                                (s00_axis_adc_tvalid),
  .s00_axis_adc_tready                                (s00_axis_adc_tready),
  .s02_axis_adc_tdata                                 (s02_axis_adc_tdata),
  .s02_axis_adc_tvalid                                (s02_axis_adc_tvalid),
  .s02_axis_adc_tready                                (s02_axis_adc_tready),
  .s10_axis_adc_tdata                                 (s10_axis_adc_tdata),
  .s10_axis_adc_tvalid                                (s10_axis_adc_tvalid),
  .s10_axis_adc_tready                                (s10_axis_adc_tready),
  .s12_axis_adc_tdata                                 (s12_axis_adc_tdata),
  .s12_axis_adc_tvalid                                (s12_axis_adc_tvalid),
  .s12_axis_adc_tready                                (s12_axis_adc_tready),
  .s20_axis_adc_tdata                                 (s20_axis_adc_tdata),
  .s20_axis_adc_tvalid                                (s20_axis_adc_tvalid),
  .s20_axis_adc_tready                                (s20_axis_adc_tready),
  .s22_axis_adc_tdata                                 (s22_axis_adc_tdata),
  .s22_axis_adc_tvalid                                (s22_axis_adc_tvalid),
  .s22_axis_adc_tready                                (s22_axis_adc_tready),
  .s30_axis_adc_tdata                                 (s30_axis_adc_tdata),
  .s30_axis_adc_tvalid                                (s30_axis_adc_tvalid),
  .s30_axis_adc_tready                                (s30_axis_adc_tready),
  .s32_axis_adc_tdata                                 (s32_axis_adc_tdata),
  .s32_axis_adc_tvalid                                (s32_axis_adc_tvalid),
  .s32_axis_adc_tready                                (s32_axis_adc_tready),
  .m_axis_dma_tdata                                   (m_axis_dma_tdata),
  .m_axis_dma_tvalid                                  (m_axis_dma_tvalid),
  .m_axis_dma_tlast                                   (m_axis_dma_tlast),
  .m_axis_dma_tkeep                                   (m_axis_dma_tkeep),
  .m_axis_dma_tready                                  (m_axis_dma_tready),
  .dac_clk                                            (dac_clk),
  .dac_reset                                          (~dac_reset),
  .m00_axis_dac_tdata                                 (m00_axis_dac_tdata),
  .m00_axis_dac_tvalid                                (m00_axis_dac_tvalid),
  .m00_axis_dac_tready                                (m00_axis_dac_tready),
  .m01_axis_dac_tdata                                 (m01_axis_dac_tdata),
  .m01_axis_dac_tvalid                                (m01_axis_dac_tvalid),
  .m01_axis_dac_tready                                (m01_axis_dac_tready),
  .m02_axis_dac_tdata                                 (m02_axis_dac_tdata),
  .m02_axis_dac_tvalid                                (m02_axis_dac_tvalid),
  .m02_axis_dac_tready                                (m02_axis_dac_tready),
  .m03_axis_dac_tdata                                 (m03_axis_dac_tdata),
  .m03_axis_dac_tvalid                                (m03_axis_dac_tvalid),
  .m03_axis_dac_tready                                (m03_axis_dac_tready),
  .m10_axis_dac_tdata                                 (m10_axis_dac_tdata),
  .m10_axis_dac_tvalid                                (m10_axis_dac_tvalid),
  .m10_axis_dac_tready                                (m10_axis_dac_tready),
  .m11_axis_dac_tdata                                 (m11_axis_dac_tdata),
  .m11_axis_dac_tvalid                                (m11_axis_dac_tvalid),
  .m11_axis_dac_tready                                (m11_axis_dac_tready),
  .m12_axis_dac_tdata                                 (m12_axis_dac_tdata),
  .m12_axis_dac_tvalid                                (m12_axis_dac_tvalid),
  .m12_axis_dac_tready                                (m12_axis_dac_tready),
  .m13_axis_dac_tdata                                 (m13_axis_dac_tdata),
  .m13_axis_dac_tvalid                                (m13_axis_dac_tvalid),
  .m13_axis_dac_tready                                (m13_axis_dac_tready)
);

endmodule
