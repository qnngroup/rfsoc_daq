// transmit_top_test.sv - Reed Foster
// Basic integration test to make sure that all signal sources and
// configuration registers are working

import sim_util_pkg::*;
import awg_pkg::*;

`timescale 1ns/1ps
module transmit_top_test ();

sim_util_pkg::debug debug = new(DEFAULT);

logic dac_reset;
logic dac_clk = 0;
localparam DAC_CLK_RATE_HZ = 384_000_000;
always #(0.5s/DAC_CLK_RATE_HZ) dac_clk = ~dac_clk;

logic ps_reset;
logic ps_clk = 0;
localparam PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

localparam int CHANNELS = 8;
localparam int PARALLEL_SAMPLES = 16;
localparam int SAMPLE_WIDTH = 16;
// DDS parameters
localparam int DDS_PHASE_BITS = 32;
localparam int DDS_QUANT_BITS = 20;
// DAC prescaler parameters
localparam int SCALE_WIDTH = 18;
localparam int SCALE_FRAC_BITS = 16;
// AWG parameters
localparam int AWG_DEPTH = 256;
localparam int AXI_MM_WIDTH = 128;

// AWG interfaces
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) ps_dma_in ();
Axis_If #(.DWIDTH((1+$clog2(AWG_DEPTH))*CHANNELS)) ps_awg_frame_depth ();
Axis_If #(.DWIDTH(2*CHANNELS)) ps_awg_trigger_out_config ();
Axis_If #(.DWIDTH(64*CHANNELS)) ps_awg_burst_length ();
Axis_If #(.DWIDTH(2)) ps_awg_start_stop ();
Axis_If #(.DWIDTH(2)) ps_awg_dma_error ();
// DAC prescaler interface
Axis_If #(.DWIDTH(SCALE_WIDTH*CHANNELS)) ps_scale_factor ();
// DDS interface
Axis_If #(.DWIDTH(DDS_PHASE_BITS*CHANNELS)) ps_dds_phase_inc ();
// Trigger manager interface
Axis_If #(.DWIDTH(1+CHANNELS)) ps_trigger_config ();
// Channel mux interface
Axis_If #(.DWIDTH($clog2(2*CHANNELS)*CHANNELS)) ps_channel_mux_config ();
// Outputs
Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_data_out ();
logic dac_trigger_out;

awg_pkg::util awg_util = new(
  ps_awg_frame_depth,
  ps_awg_trigger_out_config,
  ps_awg_burst_length,
  ps_awg_start_stop,
  ps_awg_dma_error,
  dac_data_out
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
) dut_i (
  .ps_clk,
  .ps_reset,
  .ps_dma_in,
  .ps_awg_frame_depth,
  .ps_awg_trigger_out_config,
  .ps_awg_burst_length,
  .ps_awg_start_stop,
  .ps_awg_dma_error,
  .ps_scale_factor,
  .ps_dds_phase_inc,
  .ps_trigger_config,
  .ps_channel_mux_config,
  .dac_clk,
  .dac_reset,
  .dac_data_out,
  .dac_trigger_out
);

logic [$clog2(AWG_DEPTH):0] write_depths [CHANNELS];
logic [63:0] burst_lengths [CHANNELS];
logic [1:0] trigger_modes [CHANNELS];

logic [SAMPLE_WIDTH-1:0] samples_to_send [CHANNELS][$];
logic [AXI_MM_WIDTH-1:0] dma_words [$];
logic [SAMPLE_WIDTH-1:0] samples_received [CHANNELS][$];
int trigger_arrivals [CHANNELS][$];

always @(posedge ps_clk) begin
  if (ps_dma_in.ok) begin
    if (dma_words.size() > 0) begin
      ps_dma_in.data <= dma_words.pop_back();
    end else begin
      ps_dma_in.data <= '0;
    end
  end
end

logic [4:0][CHANNELS-1:0] dac_awg_triggers_pipe;
always @(posedge dac_clk) begin
  dac_awg_triggers_pipe <= {dac_awg_triggers_pipe[3:0], dut_i.dac_awg_triggers};
end

initial begin
  debug.display("### TESTING TRANSMIT TOPLEVEL ###", DEFAULT);

  dac_reset <= 1'b1;
  ps_reset <= 1'b1;

  // reset all configuration interfaces
  ps_awg_frame_depth.data <= '0;
  ps_awg_trigger_out_config.data <= '0;
  ps_awg_burst_length.data <= '0;
  ps_awg_start_stop.data <= '0;
  ps_scale_factor.data <= '0;
  ps_dds_phase_inc.data <= '0;
  ps_trigger_config.data <= '0;
  ps_channel_mux_config.data <= '0;

  ps_awg_frame_depth.valid <= 1'b0;
  ps_awg_trigger_out_config.valid <= 1'b0;
  ps_awg_burst_length.valid <= 1'b0;
  ps_awg_start_stop.valid <= 1'b0;
  ps_scale_factor.valid <= 1'b0;
  ps_dds_phase_inc.valid <= 1'b0;
  ps_trigger_config.valid <= 1'b0;
  ps_channel_mux_config.valid <= 1'b0;

  // don't accept data from dma_error tracking output
  ps_awg_dma_error.ready <= 1'b0;

  dac_data_out.ready <= 1'b0;

  repeat (100) @(posedge ps_clk);
  ps_reset <= 1'b0;
  @(posedge dac_clk);
  dac_reset <= 1'b0;
  dac_data_out.ready <= 1'b1;

  // configure the mux to select the AWG
  for (int channel = 0; channel < CHANNELS; channel++) begin
    ps_channel_mux_config.data[channel*$clog2(2*CHANNELS)+:$clog2(2*CHANNELS)] <= channel;
  end

  // configure the scale factor to be 1
  for (int channel = 0; channel < CHANNELS; channel++) begin
    ps_scale_factor.data[channel*SCALE_WIDTH+:SCALE_WIDTH] <= 1 << SCALE_FRAC_BITS;
  end

  // configure the trigger manager to output a trigger from whenever awg_trigger_out[0] fires
  ps_trigger_config.data <= {'0, 1'b1};

  ps_channel_mux_config.valid <= 1'b1;
  ps_scale_factor.valid <= 1'b1;
  ps_trigger_config.valid <= 1'b1;
  @(posedge ps_clk);
  ps_channel_mux_config.valid <= 1'b0;
  ps_scale_factor.valid <= 1'b0;
  ps_trigger_config.valid <= 1'b0;

  // configure the AWG
  // set frame depth, burst length, and output trigger configuration
  for (int channel = 0; channel < CHANNELS; channel++) begin
    write_depths[channel] = 16;
    burst_lengths[channel] = 1;
    trigger_modes[channel] = 1;
  end

  awg_util.configure_dut(
    debug,
    ps_clk,
    trigger_modes,
    write_depths,
    burst_lengths
  );
  
  awg_util.generate_samples(debug, write_depths, samples_to_send, dma_words);

  // just send some basic data on the AWG to make sure it's producing something
  ps_dma_in.data <= dma_words.pop_back();
  ps_dma_in.send_samples(ps_clk, dma_words.size(), 1'b0, 1'b0, 1'b0);
  ps_dma_in.last <= 1'b1;
  do @(posedge ps_clk); while (~ps_dma_in.ok);
  ps_dma_in.valid <= 1'b0;
  ps_dma_in.last <= 1'b0;
  
  awg_util.check_transfer_error(debug, ps_clk, 0); // no tlast error was introduced

  debug.display("finished sending data to AWG over DMA", VERBOSE);

  // enable the DAC
  awg_util.do_dac_burst(
    debug,
    dac_clk,
    ps_clk,
    dac_awg_triggers_pipe[4],
    trigger_arrivals,
    samples_received,
    write_depths,
    burst_lengths
  );

  awg_util.check_output_data(
    debug,
    samples_to_send,
    samples_received,
    trigger_arrivals,
    trigger_modes,
    write_depths,
    burst_lengths
  );
 
  // enable the phase inc on the DDS, just set every channel to the same phase
  // and make sure they're all correct
  // configure the mux to select the DDS
  //for (int channel = 0; channel < CHANNELS; channel++) begin
  //  ps_channel_mux_config.data[channel*$clog2(2*CHANNELS)+:$clog2(2*CHANNELS)] <= channel + CHANNELS;
  //end

  debug.finish();
end

endmodule
