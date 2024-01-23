// daq_axis_test.sv - Reed Foster
// Basic integration test for DAQ toplevel to make sure all the signals are
// getting passed through okay

`timescale 1ns/1ps
module daq_axis_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT);

localparam int SAMPLE_WIDTH = 16;
localparam int PARALLEL_SAMPLES = 16;
localparam int CHANNELS = 8;
localparam int AXI_MM_WIDTH = 128;
localparam int TSTAMP_BUFFER_DEPTH = 64;
localparam int DATA_BUFFER_DEPTH = 512;
localparam int APPROX_CLOCK_WIDTH = 48;
localparam int DDS_PHASE_BITS = 32;
localparam int DDS_QUANT_BITS = 20;
localparam int SCALE_WIDTH = 18;
localparam int OFFSET_WIDTH = 14;
localparam int SCALE_INT_BITS = 2;
localparam int AWG_DEPTH = 2048;
localparam int TRI_PHASE_BITS = 32;

localparam int TIMESTAMP_WIDTH = 64; // hardcoded TODO replace with correct expression so if we change parameters it doesn't break

// util for parsing timestamp/sample data from buffer output
sparse_sample_buffer_pkg::util #(
  .AXI_MM_WIDTH(AXI_MM_WIDTH),
  .TIMESTAMP_WIDTH(TIMESTAMP_WIDTH),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) buf_util;

logic ps_reset;
logic ps_clk = 0;
localparam PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

logic dac_reset;
logic dac_clk = 0;
localparam DAC_CLK_RATE_HZ = 384_000_000;
always #(0.5s/DAC_CLK_RATE_HZ) dac_clk = ~dac_clk;

logic adc_reset;
logic adc_clk = 0;
localparam ADC_CLK_RATE_HZ = 256_000_000;
always #(0.5s/ADC_CLK_RATE_HZ) adc_clk = ~adc_clk;

Axis_If #(.DWIDTH(AXI_MM_WIDTH)) ps_awg_dma ();
Axis_If #(.DWIDTH(2*CHANNELS*SAMPLE_WIDTH)) ps_samp_disc_cfg ();
Axis_If #(.DWIDTH(32)) ps_buffer_cfg (); // banking mode (0: 1 channel, 1: 2 channels, 2: 4 channels, 3: 8 channels)
Axis_If #(.DWIDTH(32)) ps_buffer_ss ();
Axis_If #(.DWIDTH($clog2(2*CHANNELS)*CHANNELS)) ps_adc_mux_cfg ();
Axis_If #(.DWIDTH(32)) ps_buf_tstamp_width ();
Axis_If #(.DWIDTH(32)) ps_buf_capture_done ();
Axis_If #(.DWIDTH(32)) ps_lmh6401 ();
Axis_If #(.DWIDTH(96)) ps_awg_depth ();
Axis_If #(.DWIDTH(64*CHANNELS)) ps_awg_burst_len();
Axis_If #(.DWIDTH(32)) ps_awg_trigout_cfg ();
Axis_If #(.DWIDTH(32)) ps_awg_ss ();
Axis_If #(.DWIDTH(32)) ps_awg_dma_err ();
Axis_If #(.DWIDTH((SCALE_WIDTH+OFFSET_WIDTH)*CHANNELS)) ps_dac_scale_offset ();
Axis_If #(.DWIDTH(DDS_PHASE_BITS*CHANNELS)) ps_dds_phase ();
Axis_If #(.DWIDTH(TRI_PHASE_BITS*CHANNELS)) ps_tri_phase ();
Axis_If #(.DWIDTH(32)) ps_trigger_manager_cfg ();
Axis_If #(.DWIDTH(64)) ps_dac_mux_cfg ();

Axis_If #(.DWIDTH(AXI_MM_WIDTH)) adc_buffer_dma ();

Realtime_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) adc_data ();
Realtime_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_data ();

logic [CHANNELS-1:0] lmh6401_cs_n;
logic lmh6401_sck;
logic lmh6401_sdi;

daq_axis #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS),
  .AXI_MM_WIDTH(AXI_MM_WIDTH),
  .TSTAMP_BUFFER_DEPTH(TSTAMP_BUFFER_DEPTH),
  .DATA_BUFFER_DEPTH(DATA_BUFFER_DEPTH),
  .APPROX_CLOCK_WIDTH(APPROX_CLOCK_WIDTH),
  .DDS_PHASE_BITS(DDS_PHASE_BITS),
  .DDS_QUANT_BITS(DDS_QUANT_BITS),
  .SCALE_WIDTH(SCALE_WIDTH),
  .OFFSET_WIDTH(OFFSET_WIDTH),
  .SCALE_INT_BITS(SCALE_INT_BITS),
  .AWG_DEPTH(AWG_DEPTH),
  .TRI_PHASE_BITS(TRI_PHASE_BITS)
) dut_i (
  .ps_clk,
  .ps_resetn(~ps_reset),
  .s_axis_dma_tdata(ps_awg_dma.data),
  .s_axis_dma_tvalid(ps_awg_dma.valid),
  .s_axis_dma_tlast(ps_awg_dma.last),
  .s_axis_dma_tkeep(),
  .s_axis_dma_tready(ps_awg_dma.ready),
  .s_axis_sample_discriminator_config_tdata(ps_samp_disc_cfg.data),
  .s_axis_sample_discriminator_config_tvalid(ps_samp_disc_cfg.valid),
  .s_axis_sample_discriminator_config_tready(ps_samp_disc_cfg.ready),
  .s_axis_buffer_config_tdata(ps_buffer_cfg.data),
  .s_axis_buffer_config_tvalid(ps_buffer_cfg.valid),
  .s_axis_buffer_config_tready(ps_buffer_cfg.ready),
  .s_axis_buffer_start_stop_tdata(ps_buffer_ss.data),
  .s_axis_buffer_start_stop_tvalid(ps_buffer_ss.valid),
  .s_axis_buffer_start_stop_tready(ps_buffer_ss.ready),
  .s_axis_adc_mux_config_tdata(ps_adc_mux_cfg.data),
  .s_axis_adc_mux_config_tvalid(ps_adc_mux_cfg.valid),
  .s_axis_adc_mux_config_tready(ps_adc_mux_cfg.ready),
  .m_axis_buffer_timestamp_width_tdata(ps_buf_tstamp_width.data),
  .m_axis_buffer_timestamp_width_tvalid(ps_buf_tstamp_width.valid),
  .m_axis_buffer_timestamp_width_tready(ps_buf_tstamp_width.ready),
  .m_axis_buffer_timestamp_width_tlast(ps_buf_tstamp_width.last),
  .m_axis_buffer_capture_done_tdata(ps_buf_capture_done.data),
  .m_axis_buffer_capture_done_tvalid(ps_buf_capture_done.valid),
  .m_axis_buffer_capture_done_tready(ps_buf_capture_done.ready),
  .m_axis_buffer_capture_done_tlast(ps_buf_capture_done.last),
  .s_axis_lmh6401_config_tdata(ps_lmh6401.data),
  .s_axis_lmh6401_config_tvalid(ps_lmh6401.valid),
  .s_axis_lmh6401_config_tready(ps_lmh6401.ready),
  .s_axis_awg_frame_depth_tdata(ps_awg_depth.data),
  .s_axis_awg_frame_depth_tvalid(ps_awg_depth.valid),
  .s_axis_awg_frame_depth_tready(ps_awg_depth.ready),
  .s_axis_awg_burst_length_tdata(ps_awg_burst_len.data),
  .s_axis_awg_burst_length_tvalid(ps_awg_burst_len.valid),
  .s_axis_awg_burst_length_tready(ps_awg_burst_len.ready),
  .s_axis_awg_trigger_out_config_tdata(ps_awg_trigout_cfg.data),
  .s_axis_awg_trigger_out_config_tvalid(ps_awg_trigout_cfg.valid),
  .s_axis_awg_trigger_out_config_tready(ps_awg_trigout_cfg.ready),
  .s_axis_awg_start_stop_tdata(ps_awg_ss.data),
  .s_axis_awg_start_stop_tvalid(ps_awg_ss.valid),
  .s_axis_awg_start_stop_tready(ps_awg_ss.ready),
  .m_axis_awg_dma_error_tdata(ps_awg_dma_err.data),
  .m_axis_awg_dma_error_tvalid(ps_awg_dma_err.valid),
  .m_axis_awg_dma_error_tready(ps_awg_dma_err.ready),
  .m_axis_awg_dma_error_tlast(ps_awg_dma_err.last),
  .s_axis_dac_scale_offset_config_tdata(ps_dac_scale_offset.data),
  .s_axis_dac_scale_offset_config_tvalid(ps_dac_scale_offset.valid),
  .s_axis_dac_scale_offset_config_tready(ps_dac_scale_offset.ready),
  .s_axis_dds_phase_inc_tdata(ps_dds_phase.data),
  .s_axis_dds_phase_inc_tvalid(ps_dds_phase.valid),
  .s_axis_dds_phase_inc_tready(ps_dds_phase.ready),
  .s_axis_tri_phase_inc_tdata(ps_tri_phase.data),
  .s_axis_tri_phase_inc_tvalid(ps_tri_phase.valid),
  .s_axis_tri_phase_inc_tready(ps_tri_phase.ready),
  .s_axis_trigger_manager_config_tdata(ps_trigger_manager_cfg.data),
  .s_axis_trigger_manager_config_tvalid(ps_trigger_manager_cfg.valid),
  .s_axis_trigger_manager_config_tready(ps_trigger_manager_cfg.ready),
  .s_axis_dac_mux_config_tdata(ps_dac_mux_cfg.data),
  .s_axis_dac_mux_config_tvalid(ps_dac_mux_cfg.valid),
  .s_axis_dac_mux_config_tready(ps_dac_mux_cfg.ready),

  .adc_clk,
  .adc_resetn(~adc_reset),
  .s00_axis_adc_tdata(adc_data.data[0]),
  .s02_axis_adc_tdata(adc_data.data[1]),
  .s10_axis_adc_tdata(adc_data.data[2]),
  .s12_axis_adc_tdata(adc_data.data[3]),
  .s20_axis_adc_tdata(adc_data.data[4]),
  .s22_axis_adc_tdata(adc_data.data[5]),
  .s30_axis_adc_tdata(adc_data.data[6]),
  .s32_axis_adc_tdata(adc_data.data[7]),
  .s00_axis_adc_tvalid(adc_data.valid[0]),
  .s02_axis_adc_tvalid(adc_data.valid[1]),
  .s10_axis_adc_tvalid(adc_data.valid[2]),
  .s12_axis_adc_tvalid(adc_data.valid[3]),
  .s20_axis_adc_tvalid(adc_data.valid[4]),
  .s22_axis_adc_tvalid(adc_data.valid[5]),
  .s30_axis_adc_tvalid(adc_data.valid[6]),
  .s32_axis_adc_tvalid(adc_data.valid[7]),
  .s00_axis_adc_tready(),
  .s02_axis_adc_tready(),
  .s10_axis_adc_tready(),
  .s12_axis_adc_tready(),
  .s20_axis_adc_tready(),
  .s22_axis_adc_tready(),
  .s30_axis_adc_tready(),
  .s32_axis_adc_tready(),
  .m_axis_dma_tdata(adc_buffer_dma.data),
  .m_axis_dma_tvalid(adc_buffer_dma.valid),
  .m_axis_dma_tready(adc_buffer_dma.ready),
  .m_axis_dma_tlast(adc_buffer_dma.last),
  .m_axis_dma_tkeep(),

  .dac_clk,
  .dac_resetn(~dac_reset),
  .m00_axis_dac_tdata(dac_data.data[0]),
  .m01_axis_dac_tdata(dac_data.data[1]),
  .m02_axis_dac_tdata(dac_data.data[2]),
  .m03_axis_dac_tdata(dac_data.data[3]),
  .m10_axis_dac_tdata(dac_data.data[4]),
  .m11_axis_dac_tdata(dac_data.data[5]),
  .m12_axis_dac_tdata(dac_data.data[6]),
  .m13_axis_dac_tdata(dac_data.data[7]),
  .m00_axis_dac_tvalid(dac_data.valid[0]),
  .m01_axis_dac_tvalid(dac_data.valid[1]),
  .m02_axis_dac_tvalid(dac_data.valid[2]),
  .m03_axis_dac_tvalid(dac_data.valid[3]),
  .m10_axis_dac_tvalid(dac_data.valid[4]),
  .m11_axis_dac_tvalid(dac_data.valid[5]),
  .m12_axis_dac_tvalid(dac_data.valid[6]),
  .m13_axis_dac_tvalid(dac_data.valid[7]),

  .lmh6401_cs_n,
  .lmh6401_sck,
  .lmh6401_sdi
);

typedef logic [TRI_PHASE_BITS-1:0] tri_phase_t;

typedef logic [SAMPLE_WIDTH-1:0] sample_t;
logic [AXI_MM_WIDTH-1:0] dma_received [$];
// data structures for organizing DMA output
logic [TIMESTAMP_WIDTH-1:0] timestamps [CHANNELS][$];
logic [SAMPLE_WIDTH*PARALLEL_SAMPLES-1:0] samples [CHANNELS][$];

initial begin
  debug.display("### TESTING DAQ_AXIS TOPLEVEL ###", sim_util_pkg::DEFAULT);
  ps_reset <= 1'b1;
  dac_reset <= 1'b1;
  adc_reset <= 1'b1;

  adc_data.data <= '0;
  adc_data.valid <= '0;

  // configuration interfaces
  // Axis_If #(.DWIDTH(AXI_MM_WIDTH)) ps_awg_dma ();
  // Axis_If #(.DWIDTH(2*CHANNELS*SAMPLE_WIDTH)) ps_samp_disc_cfg ();
  // Axis_If #(.DWIDTH(32)) ps_buffer_cfg ();
  // Axis_If #(.DWIDTH(32)) ps_buffer_ss ();
  // Axis_If #(.DWIDTH($clog2(2*CHANNELS)*CHANNELS)) ps_adc_mux_cfg ();
  // Axis_If #(.DWIDTH(32)) ps_buf_tstamp_width ();
  // Axis_If #(.DWIDTH(32)) ps_lmh6401 ();
  // Axis_If #(.DWIDTH($clog2(AWG_DEPTH)*CHANNELS)) ps_awg_depth ();
  // Axis_If #(.DWIDTH(64*CHANNELS)) ps_awg_burst_len();
  // Axis_If #(.DWIDTH(32)) ps_awg_trigout_cfg ();
  // Axis_If #(.DWIDTH(32)) ps_awg_ss ();
  // Axis_If #(.DWIDTH(32)) ps_awg_dma_err ();
  // Axis_If #(.DWIDTH(160)) ps_dac_scale_offset ();
  // Axis_If #(.DWIDTH(DDS_PHASE_BITS*CHANNELS)) ps_dds_phase ();
  // Axis_If #(.DWIDTH(TRI_PHASE_BITS*CHANNELS)) ps_tri_phase ();
  // Axis_If #(.DWIDTH(32)) ps_trigger_manager_cfg ();
  // Axis_If #(.DWIDTH(64) ps_adc_mux_cfg ();
  ps_awg_dma.valid <= '0;
  ps_samp_disc_cfg.valid <= '0;
  ps_buffer_cfg.valid <= '0;
  ps_buffer_ss.valid <= '0;
  ps_adc_mux_cfg.valid <= '0;
  ps_buf_tstamp_width.ready <= '0;
  ps_buf_capture_done.ready <= 1'b0;
  ps_lmh6401.valid <= '0;
  ps_awg_depth.valid <= '0;
  ps_awg_burst_len.valid <= '0;
  ps_awg_trigout_cfg.valid <= '0;
  ps_awg_ss.valid <= '0;
  ps_awg_dma_err.ready <= '0;
  ps_dac_scale_offset.valid <= '0;
  ps_dds_phase.valid <= '0;
  ps_tri_phase.valid <= '0;
  ps_trigger_manager_cfg.valid <= '0;
  ps_adc_mux_cfg.valid <= '0;
  adc_buffer_dma.ready <= '0;

  repeat (100) @(posedge ps_clk);
  ps_reset <= 1'b0;
  @(posedge dac_clk);
  dac_reset <= 1'b0;
  @(posedge adc_clk);
  adc_reset <= 1'b0;
  @(posedge adc_clk);
  adc_data.valid <= '1;
 
  // always read capture_done
  ps_buf_capture_done.ready <= 1'b1;

  // check that we can generate triangle waves
  // send stop to AWG
  ps_awg_ss.data <= {'0, 2'b01};
  ps_awg_ss.valid <= 1'b1;
  do @(posedge ps_clk); while (~ps_awg_ss.ok);
  ps_awg_ss.valid <= 1'b0;
  // set AWG triggers to all 0
  ps_awg_trigout_cfg.data <= '0;
  ps_awg_trigout_cfg.valid <= 1'b1;
  do @(posedge ps_clk); while (~ps_awg_trigout_cfg.ok);
  ps_awg_trigout_cfg.valid <= 1'b0;
  // disable triggers in trigger manager
  ps_trigger_manager_cfg.data <= '0;
  ps_trigger_manager_cfg.valid <= 1'b1;
  do @(posedge ps_clk); while (~ps_trigger_manager_cfg.ok);
  ps_trigger_manager_cfg.valid <= 1'b0;
  // select all triangle wave gens
  ps_dac_mux_cfg.data <= '0;
  for (int channel = 0; channel < CHANNELS; channel++) begin
    ps_dac_mux_cfg.data[channel*$clog2(3*CHANNELS)+:$clog2(3*CHANNELS)] <= channel + 2*CHANNELS;
  end
  ps_dac_mux_cfg.valid <= 1'b1;
  do @(posedge ps_clk); while (~ps_dac_mux_cfg.ok);
  ps_dac_mux_cfg.valid <= 1'b0;
  // set dac scale to 0.25, zero offset
  ps_dac_scale_offset.data <= {CHANNELS{18'h04000, 14'h0}};
  ps_dac_scale_offset.valid <= 1'b1;
  do @(posedge ps_clk); while (~ps_dac_scale_offset.ok);
  ps_dac_scale_offset.valid <= 1'b0;
  // set tri frequency to 10MHz
  for (int channel = 0; channel < CHANNELS; channel++) begin
    ps_tri_phase.data[channel*TRI_PHASE_BITS+:TRI_PHASE_BITS] <= tri_phase_t'(int'($floor((real'(10_000_000+channel*1_000_000)/6_144_000_000.0) * (2.0**(TRI_PHASE_BITS)))));
  end
  ps_tri_phase.valid <= 1'b1;
  do @(posedge ps_clk); while (~ps_tri_phase.ok);
  ps_tri_phase.valid <= 1'b0;

  // set adc signal source
  for (int channel = 0; channel < CHANNELS; channel++) begin
    ps_adc_mux_cfg.data[channel*$clog2(2*CHANNELS)+:$clog2(2*CHANNELS)] <= channel; // just take the raw ADC data
  end
  ps_adc_mux_cfg.valid <= 1'b1;
  do @(posedge ps_clk); while (~ps_adc_mux_cfg.ok);
  ps_adc_mux_cfg.valid <= 1'b0;
  // set sample discriminator to save everything
  ps_samp_disc_cfg.data <= {CHANNELS{16'h8000, 16'h8000}};
  ps_samp_disc_cfg.valid <= 1'b1;
  do @(posedge ps_clk); while (~ps_samp_disc_cfg.ok);
  ps_samp_disc_cfg.valid <= 1'b0;
  // set banking mode
  ps_buffer_cfg.data <= 32'h3; // enable all 8 channels
  ps_buffer_cfg.valid <= 1'b1;
  do @(posedge ps_clk); while (~ps_buffer_cfg.ok);
  ps_buffer_cfg.valid <= 1'b0;

  // enable trigger for channel 0 in trigger manager
  ps_trigger_manager_cfg.data <= {15'b0, 1'b0, 16'h0100};
  ps_trigger_manager_cfg.valid <= 1'b1;
  do @(posedge ps_clk); while (~ps_trigger_manager_cfg.ok);
  ps_trigger_manager_cfg.valid <= 1'b0;

  // wait until we get capture_done == 1
  while (~(ps_buf_capture_done.ok & ps_buf_capture_done.data == 32'b1)) @(posedge ps_clk);

  repeat (10) @(posedge adc_clk);
  // assert dma_ready
  adc_buffer_dma.ready <= 1'b1;
  while (~(adc_buffer_dma.last & adc_buffer_dma.ok)) begin
    if (adc_buffer_dma.ok) begin
      dma_received.push_front(adc_buffer_dma.data);
    end
    @(posedge adc_clk);
  end
  // convert dma data to samples, then check with triangle wave checker
  buf_util.parse_buffer_output(dma_received, timestamps, samples);
  debug.display("parsed data_received:", sim_util_pkg::VERBOSE);
  for (int channel = 0; channel < CHANNELS; channel++) begin
    debug.display($sformatf("timestamps[%0d].size() = %0d", channel, timestamps[channel].size()), sim_util_pkg::VERBOSE);
    debug.display($sformatf("samples[%0d].size() = %0d", channel, samples[channel].size()), sim_util_pkg::VERBOSE);
    if (timestamps[channel].size() !== 1) begin
      debug.error($sformatf(
        "expected exactly one timestamp for for channel %0d, got %0d",
        channel,
        timestamps[channel].size())
      );
    end
  end
  // check channel 0
  while (samples[0].size() > 0) begin
    for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
      debug.display($sformatf(
        "got sample %x (%0f)",
        samples[0][$][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH],
        real'(sample_t'(samples[0][$][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH]))/(2.0**SAMPLE_WIDTH)),
        sim_util_pkg::DEBUG
      );
    end
    samples[0].pop_back();
  end

  // check output
  debug.finish();
end

endmodule
