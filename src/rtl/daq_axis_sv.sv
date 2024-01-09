// daq_axis_sv.sv - Reed Foster
// DAQ toplevel with separate AXI-stream interface for each signal chain
// submodule configuration register
// Breaks out SV interfaces into verilog-compatible ports so that the toplevel
// can be instantiated in a block diagram

module daq_axis_sv #(
  // Shared parameters
  parameter int SAMPLE_WIDTH = 16, // width in bits of each sample
  parameter int PARALLEL_SAMPLES = 16, // number of parallel samples per clock cycle per channel
  parameter int CHANNELS = 8, // number of input channels
  parameter int AXI_MM_WIDTH = 128, // width of DMA AXI-stream interface

  // Sparse sample buffer parameters
  parameter int TSTAMP_BUFFER_DEPTH = 1024, // depth of timestamp buffer
  parameter int DATA_BUFFER_DEPTH = 16384, // depth of data/sample buffer
  // Sample discriminator parameters
  parameter int APPROX_CLOCK_WIDTH = 48, // requested width of timestamp

  // DDS parameters
  parameter int DDS_PHASE_BITS = 32,
  parameter int DDS_QUANT_BITS = 20,
  // DAC prescaler parameters
  parameter int SCALE_WIDTH = 18,
  parameter int SCALE_FRAC_BITS = 16,
  // AWG parameters
  parameter int AWG_DEPTH = 2048
) (
  input wire ps_clk, ps_reset,

  // dma input (AWG)
  input   wire [AXI_MM_WIDTH-1:0] s_axis_dma_tdata,
  input   wire                    s_axis_dma_tvalid,
  input   wire                    s_axis_dma_tlast,
  input   wire             [15:0] s_axis_dma_tkeep,
  output  wire                    s_axis_dma_tready,

  //////////////////////////////////////////////////////
  // ADC CONFIGURATION
  //////////////////////////////////////////////////////
  // sample discriminator config
  input   wire [2*CHANNELS*SAMPLE_WIDTH-1:0]      s_axis_sample_discriminator_config_tdata,
  input   wire                                    s_axis_sample_discriminator_config_tvalid,
  output  wire                                    s_axis_sample_discriminator_config_tready,
  // sparse buffer config
  input   wire [$clog2($clog2(CHANNELS)+1)-1:0]   s_axis_buffer_config_tdata,
  input   wire                                    s_axis_buffer_config_tvalid,
  output  wire                                    s_axis_buffer_config_tready,
  // buffer capture start/stop
  input   wire [1:0]                              s_axis_buffer_start_stop_tdata,
  input   wire                                    s_axis_buffer_start_stop_tvalid,
  output  wire                                    s_axis_buffer_start_stop_tready,
  // RX channel mux config
  input   wire [$clog2(2*CHANNELS)*CHANNELS-1:0]  s_axis_adc_mux_config_tdata,
  input   wire                                    s_axis_adc_mux_config_tvalid,
  output  wire                                    s_axis_adc_mux_config_tready,
  // buffer timestamp width out
  output  wire [31:0]                             m_axis_buffer_timestamp_width_tdata,
  output  wire                                    m_axis_buffer_timestamp_width_tvalid,
  input   wire                                    m_axis_buffer_timestamp_width_tready,
  // LMH6401 configuration
  input   wire [16+$clog2(CHANNELS)-1:0]          s_axis_lmh6401_config_tdata,
  input   wire                                    s_axis_lmh6401_config_tvalid,
  output  wire                                    s_axis_lmh6401_config_tready,

  //////////////////////////////////////////////////////
  // DAC CONFIGURATION
  //////////////////////////////////////////////////////
  // awg frame depth
  input   wire [(1+$clog2(AWG_DEPTH))*CHANNELS-1:0] s_axis_awg_frame_depth_tdata,
  input   wire                                      s_axis_awg_frame_depth_tvalid,
  output  wire                                      s_axis_awg_frame_depth_tready,
  // awg burst length
  input   wire [64*CHANNELS-1:0]                    s_axis_awg_burst_length_tdata,
  input   wire                                      s_axis_awg_burst_length_tvalid,
  output  wire                                      s_axis_awg_burst_length_tready,
  // awg trigger output config
  input   wire [2*CHANNELS-1:0]                     s_axis_awg_trigger_out_config_tdata,
  input   wire                                      s_axis_awg_trigger_out_config_tvalid,
  output  wire                                      s_axis_awg_trigger_out_config_tready,
  // awg start/stop
  input   wire [1:0]                                s_axis_awg_start_stop_tdata,
  input   wire                                      s_axis_awg_start_stop_tvalid,
  output  wire                                      s_axis_awg_start_stop_tready,
  // awg dma error
  output  wire [1:0]                                m_axis_awg_dma_error_tdata,
  output  wire                                      m_axis_awg_dma_error_tvalid,
  input   wire                                      m_axis_awg_dma_error_tready,
  // dac scale factor
  input   wire [SCALE_WIDTH*CHANNELS-1:0]           s_axis_dac_scale_config_tdata,
  input   wire                                      s_axis_dac_scale_config_tvalid,
  output  wire                                      s_axis_dac_scale_config_tready,
  // dds phase increment
  input   wire [DDS_PHASE_BITS*CHANNELS-1:0]        s_axis_dds_phase_inc_tdata,
  input   wire                                      s_axis_dds_phase_inc_tvalid,
  output  wire                                      s_axis_dds_phase_inc_tready,
  // trigger manager config
  input   wire [CHANNELS:0]                         s_axis_trigger_manager_config_tdata,
  input   wire                                      s_axis_trigger_manager_config_tvalid,
  output  wire                                      s_axis_trigger_manager_config_tready,
  // TX channel mux config
  input   wire [$clog2(2*CHANNELS)*CHANNELS-1:0]    s_axis_dac_mux_config_tdata,
  input   wire                                      s_axis_dac_mux_config_tvalid,
  output  wire                                      s_axis_dac_mux_config_tready,

  //////////////////////////////////////////////////////
  // ADC SIGNAL PATH
  //////////////////////////////////////////////////////
  input wire adc_clk, adc_reset,
  // adc data in
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  s00_axis_adc_tdata,
  input   wire                                      s00_axis_adc_tvalid,
  output  wire                                      s00_axis_adc_tready,
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  s02_axis_adc_tdata,
  input   wire                                      s02_axis_adc_tvalid,
  output  wire                                      s02_axis_adc_tready,
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  s10_axis_adc_tdata,
  input   wire                                      s10_axis_adc_tvalid,
  output  wire                                      s10_axis_adc_tready,
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  s12_axis_adc_tdata,
  input   wire                                      s12_axis_adc_tvalid,
  output  wire                                      s12_axis_adc_tready,
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  s20_axis_adc_tdata,
  input   wire                                      s20_axis_adc_tvalid,
  output  wire                                      s20_axis_adc_tready,
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  s22_axis_adc_tdata,
  input   wire                                      s22_axis_adc_tvalid,
  output  wire                                      s22_axis_adc_tready,
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  s30_axis_adc_tdata,
  input   wire                                      s30_axis_adc_tvalid,
  output  wire                                      s30_axis_adc_tready,
  input   wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  s32_axis_adc_tdata,
  input   wire                                      s32_axis_adc_tvalid,
  output  wire                                      s32_axis_adc_tready,

  // dma output (Sparse sample buffer -- TODO rewrite with split clock domains
  // for buffer write and read so that this doesn't need an external CDC FIFO)
  output  wire [AXI_MM_WIDTH-1:0] m_axis_dma_tdata,
  output  wire                    m_axis_dma_tvalid,
  output  wire                    m_axis_dma_tlast,
  output  wire             [15:0] m_axis_dma_tkeep,
  input   wire                    m_axis_dma_tready,

  //////////////////////////////////////////////////////
  // DAC SIGNAL PATH
  //////////////////////////////////////////////////////
  input wire dac_clk, dac_reset,
  // dac data out
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  m00_axis_dac_tdata,
  output  wire                                      m00_axis_dac_tvalid,
  input   wire                                      m00_axis_dac_tready,
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  m01_axis_dac_tdata,
  output  wire                                      m01_axis_dac_tvalid,
  input   wire                                      m01_axis_dac_tready,
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  m02_axis_dac_tdata,
  output  wire                                      m02_axis_dac_tvalid,
  input   wire                                      m02_axis_dac_tready,
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  m03_axis_dac_tdata,
  output  wire                                      m03_axis_dac_tvalid,
  input   wire                                      m03_axis_dac_tready,
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  m10_axis_dac_tdata,
  output  wire                                      m10_axis_dac_tvalid,
  input   wire                                      m10_axis_dac_tready,
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  m11_axis_dac_tdata,
  output  wire                                      m11_axis_dac_tvalid,
  input   wire                                      m11_axis_dac_tready,
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  m12_axis_dac_tdata,
  output  wire                                      m12_axis_dac_tvalid,
  input   wire                                      m12_axis_dac_tready,
  output  wire [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0]  m13_axis_dac_tdata,
  output  wire                                      m13_axis_dac_tvalid,
  input   wire                                      m13_axis_dac_tready,

  //////////////////////////////////////////////////////
  // SPI
  //////////////////////////////////////////////////////
  output wire [CHANNELS-1:0]  lmh6401_cs_n,
  output wire                 lmh6401_sck,
  output wire                 lmh6401_sdi
);

//////////////////////////////////////////////////////
// TRANSMIT TOP
//////////////////////////////////////////////////////
// AWG interfaces
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) ps_awg_dma_in ();
Axis_If #(.DWIDTH((1+$clog2(AWG_DEPTH))*CHANNELS)) ps_awg_frame_depth ();
Axis_If #(.DWIDTH(64*CHANNELS)) ps_awg_burst_length ();
Axis_If #(.DWIDTH(2*CHANNELS)) ps_awg_trigger_out_config ();
Axis_If #(.DWIDTH(2)) ps_awg_start_stop ();
Axis_If #(.DWIDTH(2)) ps_awg_dma_error ();
// DAC prescaler interface
Axis_If #(.DWIDTH(SCALE_WIDTH*CHANNELS)) ps_dac_scale_factor ();
// DDS interface
Axis_If #(.DWIDTH(DDS_PHASE_BITS*CHANNELS)) ps_dds_phase_inc ();
// Trigger manager interface
Axis_If #(.DWIDTH(1+CHANNELS)) ps_trigger_manager_config ();
// Channel mux interface
Axis_If #(.DWIDTH($clog2(2*CHANNELS)*CHANNELS)) ps_dac_mux_config ();
// Outputs
Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_data_out ();
logic dac_trigger_out, adc_trigger_in;

// connect DMA interface
assign ps_awg_dma_in.data = s_axis_dma_tdata;
assign ps_awg_dma_in.valid = s_axis_dma_tvalid;
assign ps_awg_dma_in.last = s_axis_dma_tlast;
assign s_axis_dma_tready = ps_awg_dma_in.ready;

// connect configuration register interfaces
assign ps_awg_frame_depth.data = s_axis_awg_frame_depth_tdata;
assign ps_awg_frame_depth.valid = s_axis_awg_frame_depth_tvalid;
assign s_axis_awg_frame_depth_tready = ps_awg_frame_depth.ready;

assign ps_awg_burst_length.data = s_axis_awg_burst_length_tdata;
assign ps_awg_burst_length.valid = s_axis_awg_burst_length_tvalid;
assign s_axis_awg_burst_length_tready = ps_awg_burst_length.ready;

assign ps_awg_trigger_out_config.data = s_axis_awg_trigger_out_config_tdata;
assign ps_awg_trigger_out_config.valid = s_axis_awg_trigger_out_config_tvalid;
assign s_axis_awg_trigger_out_config_tready = ps_awg_trigger_out_config.ready;

assign ps_awg_start_stop.data = s_axis_awg_start_stop_tdata;
assign ps_awg_start_stop.valid = s_axis_awg_start_stop_tvalid;
assign s_axis_awg_start_stop_tready = ps_awg_start_stop.ready;

assign m_axis_awg_dma_error_tdata = ps_awg_dma_error.data;
assign m_axis_awg_dma_error_tvalid = ps_awg_dma_error.valid;
assign ps_awg_dma_error.ready = m_axis_awg_dma_error_tready;

assign ps_dac_scale_factor.data = s_axis_dac_scale_config_tdata;
assign ps_dac_scale_factor.valid = s_axis_dac_scale_config_tvalid;
assign s_axis_dac_scale_config_tready = ps_dac_scale_factor.ready;

assign ps_dds_phase_inc.data = s_axis_dds_phase_inc_tdata;
assign ps_dds_phase_inc.valid = s_axis_dds_phase_inc_tvalid;
assign s_axis_dds_phase_inc_tready = ps_dds_phase_inc.ready;

assign ps_trigger_manager_config.data = s_axis_trigger_manager_config_tdata;
assign ps_trigger_manager_config.valid = s_axis_trigger_manager_config_tvalid;
assign s_axis_trigger_manager_config_tready = ps_trigger_manager_config.ready;

assign ps_dac_mux_config.data = s_axis_dac_mux_config_tdata;
assign ps_dac_mux_config.valid = s_axis_dac_mux_config_tvalid;
assign s_axis_dac_mux_config_tready = ps_dac_mux_config.ready;

// connect dac output
assign m00_axis_dac_tdata = dac_data_out.data[0];
assign m01_axis_dac_tdata = dac_data_out.data[1];
assign m02_axis_dac_tdata = dac_data_out.data[2];
assign m03_axis_dac_tdata = dac_data_out.data[3];
assign m10_axis_dac_tdata = dac_data_out.data[4];
assign m11_axis_dac_tdata = dac_data_out.data[5];
assign m12_axis_dac_tdata = dac_data_out.data[6];
assign m13_axis_dac_tdata = dac_data_out.data[7];
assign m00_axis_dac_tvalid = dac_data_out.valid[0];
assign m01_axis_dac_tvalid = dac_data_out.valid[1];
assign m02_axis_dac_tvalid = dac_data_out.valid[2];
assign m03_axis_dac_tvalid = dac_data_out.valid[3];
assign m10_axis_dac_tvalid = dac_data_out.valid[4];
assign m11_axis_dac_tvalid = dac_data_out.valid[5];
assign m12_axis_dac_tvalid = dac_data_out.valid[6];
assign m13_axis_dac_tvalid = dac_data_out.valid[7];
assign dac_data_out.ready = '1; // don't apply backpressure

// CDC to pass trigger to ADC
xpm_cdc_pulse #(
  .DEST_SYNC_FF(4), // 4 synchronization stages
  .INIT_SYNC_FF(0), // don't allow behavioral initialization
  .REG_OUTPUT(1), // register the output
  .RST_USED(1), // use resets
  .SIM_ASSERT_CHK(1) // report potential violations
) start_cdc_i (
  .src_clk(dac_clk),
  .src_rst(dac_reset),
  .src_pulse(dac_trigger_out),
  .dest_clk(adc_clk),
  .dest_rst(adc_reset),
  .dest_pulse(adc_trigger_in)
);

transmit_top #(
  .CHANNELS(CHANNELS),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .DDS_PHASE_BITS(DDS_PHASE_BITS),
  .DDS_QUANT_BITS(DDS_QUANT_BITS),
  .SCALE_WIDTH(SCALE_WIDTH),
  .SCALE_FRAC_BITS(SCALE_FRAC_BITS),
  .AWG_DEPTH(AWG_DEPTH),
  .AXI_MM_WIDTH(AXI_MM_WIDTH)
) transmit_top_i (
  .ps_clk,
  .ps_reset,
  .ps_awg_dma_in,
  .ps_awg_frame_depth,
  .ps_awg_burst_length,
  .ps_awg_trigger_out_config,
  .ps_awg_start_stop,
  .ps_awg_dma_error,
  .ps_scale_factor(ps_dac_scale_factor),
  .ps_dds_phase_inc,
  .ps_trigger_config(ps_trigger_manager_config),
  .ps_channel_mux_config(ps_dac_mux_config),
  .dac_clk,
  .dac_reset,
  .dac_data_out,
  .dac_trigger_out
);

//////////////////////////////////////////////////////
// RECEIVE TOP
//////////////////////////////////////////////////////
Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) adc_data_in ();
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) adc_dma_out ();
// DUT configuration interfaces
Axis_If #(.DWIDTH(CHANNELS*SAMPLE_WIDTH*2)) ps_sample_discriminator_config ();
Axis_If #(.DWIDTH($clog2($clog2(CHANNELS)+1))) ps_buffer_config ();
Axis_If #(.DWIDTH(2)) ps_buffer_start_stop ();
Axis_If #(.DWIDTH(CHANNELS*$clog2(2*CHANNELS))) ps_channel_mux_config ();
Axis_If #(.DWIDTH(32)) ps_buffer_timestamp_width ();
Axis_If #(.DWIDTH(16+$clog2(CHANNELS))) ps_lmh6401_config ();

// connect DMA interface
assign m_axis_dma_tdata = adc_dma_out.data;
assign m_axis_dma_tvalid = adc_dma_out.valid;
assign m_axis_dma_tlast = adc_dma_out.last;
assign m_axis_dma_tkeep = 16'hffff;
assign adc_dma_out.ready = m_axis_dma_tready;

// connect configuration register interfaces
assign ps_sample_discriminator_config.data = s_axis_sample_discriminator_config_tdata;
assign ps_sample_discriminator_config.valid = s_axis_sample_discriminator_config_tvalid;
assign s_axis_sample_discriminator_config_tready = ps_sample_discriminator_config.ready;

assign ps_buffer_config.data = s_axis_buffer_config_tdata;
assign ps_buffer_config.valid = s_axis_buffer_config_tvalid;
assign s_axis_buffer_config_tready = ps_buffer_config.ready;

assign ps_buffer_start_stop.data = s_axis_buffer_start_stop_tdata;
assign ps_buffer_start_stop.valid = s_axis_buffer_start_stop_tvalid;
assign s_axis_buffer_start_stop_tready = ps_buffer_start_stop.ready;

assign ps_channel_mux_config.data = s_axis_adc_mux_config_tdata;
assign ps_channel_mux_config.valid = s_axis_adc_mux_config_tvalid;
assign s_axis_adc_mux_config_tready = ps_channel_mux_config.ready;

assign m_axis_buffer_timestamp_width_tdata = ps_buffer_timestamp_width.data;
assign m_axis_buffer_timestamp_width_tvalid = ps_buffer_timestamp_width.valid;
assign ps_buffer_timestamp_width.ready = m_axis_buffer_timestamp_width_tready;

assign ps_lmh6401_config.data = s_axis_lmh6401_config_tdata;
assign ps_lmh6401_config.valid = s_axis_lmh6401_config_tvalid;
assign s_axis_lmh6401_config_tready = ps_lmh6401_config.ready;

// connect datastream interface
assign adc_data_in.data[0] = s00_axis_adc_tdata;
assign adc_data_in.data[1] = s02_axis_adc_tdata;
assign adc_data_in.data[2] = s10_axis_adc_tdata;
assign adc_data_in.data[3] = s12_axis_adc_tdata;
assign adc_data_in.data[4] = s20_axis_adc_tdata;
assign adc_data_in.data[5] = s22_axis_adc_tdata;
assign adc_data_in.data[6] = s30_axis_adc_tdata;
assign adc_data_in.data[7] = s32_axis_adc_tdata;
assign adc_data_in.valid[0] = s00_axis_adc_tvalid;
assign adc_data_in.valid[1] = s02_axis_adc_tvalid;
assign adc_data_in.valid[2] = s10_axis_adc_tvalid;
assign adc_data_in.valid[3] = s12_axis_adc_tvalid;
assign adc_data_in.valid[4] = s20_axis_adc_tvalid;
assign adc_data_in.valid[5] = s22_axis_adc_tvalid;
assign adc_data_in.valid[6] = s30_axis_adc_tvalid;
assign adc_data_in.valid[7] = s32_axis_adc_tvalid;
assign s00_axis_adc_tready = 1'b1;
assign s02_axis_adc_tready = 1'b1;
assign s10_axis_adc_tready = 1'b1;
assign s12_axis_adc_tready = 1'b1;
assign s20_axis_adc_tready = 1'b1;
assign s22_axis_adc_tready = 1'b1;
assign s30_axis_adc_tready = 1'b1;
assign s32_axis_adc_tready = 1'b1;

receive_top #(
  .CHANNELS(CHANNELS),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .AXI_MM_WIDTH(AXI_MM_WIDTH),
  .TSTAMP_BUFFER_DEPTH(TSTAMP_BUFFER_DEPTH),
  .DATA_BUFFER_DEPTH(DATA_BUFFER_DEPTH),
  .APPROX_CLOCK_WIDTH(APPROX_CLOCK_WIDTH)
) receive_top_i (
  .ps_clk,
  .ps_reset,
  .ps_sample_discriminator_config,
  .ps_buffer_config,
  .ps_buffer_start_stop,
  .ps_channel_mux_config,
  .ps_buffer_timestamp_width,
  .adc_clk,
  .adc_reset,
  .adc_data_in,
  .adc_dma_out,
  .adc_trigger_in
);

SPI_Parallel_If #(.CHANNELS(CHANNELS)) spi ();

assign lmh6401_cs_n = spi.cs_n;
assign lmh6401_sck = spi.sck;
assign lmh6401_sdi = spi.sdi;

// LMH6401 SPI interface
lmh6401_spi #(
  .AXIS_CLK_FREQ(100_000_000),
  .SPI_CLK_FREQ(1_000_000),
  .NUM_CHANNELS(CHANNELS)
) lmh6401_spi_i (
  .clk(ps_clk),
  .reset(ps_reset),
  .command_in(ps_lmh6401_config),
  .spi
);


endmodule
