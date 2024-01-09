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
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) ps_awg_dma_in ();
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

// DDS util
typedef logic signed [SAMPLE_WIDTH-1:0] sample_t;
typedef logic [DDS_PHASE_BITS-1:0] phase_t;
typedef logic [CHANNELS-1:0][DDS_PHASE_BITS-1:0] multi_phase_t;

sim_util_pkg::math #(sample_t) math; // abs, max functions on sample_t

multi_phase_t phase_inc;
sample_t dds_received [CHANNELS][$];

localparam real PI = 3.14159265;

localparam int N_FREQS = 8;
int freqs [N_FREQS] = {
  12_130_000,
  517_036_000,
  1_729_725_000,
  2_759_000,
  127_420,
  8_143_219,
  14_892_357,
  764_987_640
};

function phase_t get_phase_inc_from_freq(input int freq);
  return phase_t'($floor((real'(freq)/6_400_000_000.0) * (2.0**(DDS_PHASE_BITS))));
endfunction

always @(posedge ps_clk) begin
  if (ps_reset) begin
    phase_inc <= '0;
  end else begin
    if (ps_dds_phase_inc.valid) begin
      phase_inc <= ps_dds_phase_inc.data;
    end
  end
end

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
  .ps_awg_dma_in,
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
  if (ps_awg_dma_in.ok) begin
    if (dma_words.size() > 0) begin
      ps_awg_dma_in.data <= dma_words.pop_back();
    end else begin
      ps_awg_dma_in.data <= '0;
    end
  end
end

logic [4:0][CHANNELS-1:0] dac_awg_triggers_pipe;
always @(posedge dac_clk) begin
  dac_awg_triggers_pipe <= {dac_awg_triggers_pipe[3:0], dut_i.dac_awg_triggers};
end

task automatic check_dds_output();
  multi_phase_t phase;
  sample_t expected;
  phase = '0;
  for (int channel = 0; channel < CHANNELS; channel++) begin
    while (dds_received[channel].size() > 0) begin
      expected = sample_t'($floor((2.0**(SAMPLE_WIDTH-1) - 0.5)*$cos((2.0*PI/2.0**DDS_PHASE_BITS)*real'(phase[channel])) - 0.5));
      // we won't get the phase exactly right
      if (math.abs(dds_received[channel][$] - expected) > 6'h3f) begin
        debug.error($sformatf(
          "channel %0d: mismatched sample value for phase = %x: expected %x got %x",
          channel,
          phase[channel],
          expected,
          dds_received[channel][$])
        );
      end
      phase[channel] = phase[channel] + phase_inc[channel];
      dds_received[channel].pop_back();
    end
  end
endtask

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

  repeat (100) @(posedge ps_clk);
  ps_reset <= 1'b0;
  @(posedge dac_clk);
  dac_reset <= 1'b0;

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
  ps_awg_dma_in.data <= dma_words.pop_back();
  ps_awg_dma_in.send_samples(ps_clk, dma_words.size(), 1'b0, 1'b0, 1'b0);
  ps_awg_dma_in.last <= 1'b1;
  do @(posedge ps_clk); while (~ps_awg_dma_in.ok);
  ps_awg_dma_in.valid <= 1'b0;
  ps_awg_dma_in.last <= 1'b0;
  
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
  
  debug.display("finished testing AWG", VERBOSE);
 
  // configure the mux to select the DDS
  for (int channel = 0; channel < CHANNELS; channel++) begin
    ps_channel_mux_config.data[channel*$clog2(2*CHANNELS)+:$clog2(2*CHANNELS)] <= channel + CHANNELS;
  end
  // set phase increment
  for (int channel = 0; channel < CHANNELS; channel++) begin
    ps_dds_phase_inc.data[channel*DDS_PHASE_BITS+:DDS_PHASE_BITS] <= get_phase_inc_from_freq(freqs[channel]);
  end

  ps_dds_phase_inc.valid <= 1'b1;
  ps_channel_mux_config.valid <= 1'b1;
  @(posedge ps_clk);
  ps_dds_phase_inc.valid <= 1'b0;
  ps_channel_mux_config.valid <= 1'b0;

  debug.display("finished configuring DDS", VERBOSE);

  // wait until we get nonzero data, then start adding to dds_received
  while (dac_data_out.data === '0) @(posedge dac_clk);
  repeat (4) @(posedge dac_clk); // extra latency with 0 phase increment but nonzero output
  // nonzero data now
  debug.display("collecting DDS data", VERBOSE);
  repeat (100) begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
        dds_received[channel].push_front(dac_data_out.data[channel][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH]);
      end
    end
    @(posedge dac_clk);
  end
  debug.display("checking DDS data", VERBOSE);
  // check to make sure that data matches what we'd expect
  check_dds_output();
  
  debug.finish();
end

endmodule
