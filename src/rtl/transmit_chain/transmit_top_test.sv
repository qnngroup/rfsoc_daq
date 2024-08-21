// transmit_top_test.sv - Reed Foster
// Basic integration test to make sure that all signal sources and
// configuration registers are working

`timescale 1ns/1ps
module transmit_top_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT);

logic dac_reset;
logic dac_clk = 0;
localparam int DAC_CLK_RATE_HZ = 384_000_000;
always #(0.5s/DAC_CLK_RATE_HZ) dac_clk = ~dac_clk;

logic ps_reset;
logic ps_clk = 0;
localparam int PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

// DDS parameters
localparam int DDS_PHASE_BITS = 32;
localparam int DDS_QUANT_BITS = 20;
// DAC prescaler parameters
localparam int SCALE_WIDTH = 18;
localparam int OFFSET_WIDTH = 14;
localparam int SCALE_INT_BITS = 2;
// AWG parameters
localparam int AWG_DEPTH = 256;
// Triangle parameters
localparam int TRI_PHASE_BITS = 32;

// AWG interfaces
Axis_If #(.DWIDTH(tx_pkg::AXI_MM_WIDTH)) ps_awg_dma_in ();
Axis_If #(.DWIDTH($clog2(AWG_DEPTH)*tx_pkg::CHANNELS)) ps_awg_frame_depth ();
Axis_If #(.DWIDTH(2*tx_pkg::CHANNELS)) ps_awg_trigger_out_config ();
Axis_If #(.DWIDTH(64*tx_pkg::CHANNELS)) ps_awg_burst_length ();
Axis_If #(.DWIDTH(2)) ps_awg_start_stop ();
Axis_If #(.DWIDTH(2)) ps_awg_dma_error ();
// DAC prescaler interface
Axis_If #(.DWIDTH((SCALE_WIDTH+OFFSET_WIDTH)*tx_pkg::CHANNELS)) ps_scale_offset ();
// DDS interface
Axis_If #(.DWIDTH(DDS_PHASE_BITS*tx_pkg::CHANNELS)) ps_dds_phase_inc ();
Axis_If #(.DWIDTH(TRI_PHASE_BITS*tx_pkg::CHANNELS)) ps_tri_phase_inc ();
// Channel mux interface
Axis_If #(.DWIDTH($clog2(3*tx_pkg::CHANNELS)*tx_pkg::CHANNELS)) ps_channel_mux_config ();
// Outputs
Realtime_Parallel_If #(.DWIDTH(tx_pkg::DATA_WIDTH), .CHANNELS(tx_pkg::CHANNELS)) dac_data_out ();
logic [tx_pkg::CHANNELS-1:0] dac_triggers_out;

// pull out awg_trigger/tri_trigger output and match latency of dac_prescaler/mux
// this way the awg_tb and tri_tb can check the triggers are generated
// correctly
logic [5:0][tx_pkg::CHANNELS-1:0] dac_awg_triggers_pipe;
logic [5:0][tx_pkg::CHANNELS-1:0] dac_tri_triggers_pipe;
logic [tx_pkg::CHANNELS-1:0] dac_awg_trigger;
logic [tx_pkg::CHANNELS-1:0] dac_tri_trigger;
assign dac_awg_trigger = dac_awg_triggers_pipe[5];
assign dac_tri_trigger = dac_tri_triggers_pipe[5];
always @(posedge dac_clk) begin
  dac_awg_triggers_pipe <= {dac_awg_triggers_pipe[4:0], dac_triggers_out};
  dac_tri_triggers_pipe <= {dac_tri_triggers_pipe[4:0], dut_i.tri_i.dac_trigger};
end

// AWG testing
logic [tx_pkg::CHANNELS-1:0][$clog2(AWG_DEPTH)-1:0] write_depths;
logic [tx_pkg::CHANNELS-1:0][63:0] burst_lengths;
logic [tx_pkg::CHANNELS-1:0][1:0] trigger_modes;
awg_tb #(
  .DEPTH(AWG_DEPTH)
) awg_tb_i (
  .dma_clk(ps_clk),
  .dma_data_in(ps_awg_dma_in),
  .dma_write_depth(ps_awg_frame_depth),
  .dma_trigger_out_config(ps_awg_trigger_out_config),
  .dma_awg_burst_length(ps_awg_burst_length),
  .dma_awg_start_stop(ps_awg_start_stop),
  .dma_transfer_error(ps_awg_dma_error),
  .dac_clk,
  .dac_trigger(dac_awg_trigger),
  .dac_data_out
);

// DDS testing
int freqs [tx_pkg::CHANNELS] = {
  12_130_000,
  517_036_000,
  1_729_725_000,
  2_759_000,
  127_420,
  8_143_219,
  14_892_357,
  764_987_640
};
dds_tb #(
  .PHASE_BITS(DDS_PHASE_BITS),
  .QUANT_BITS(DDS_QUANT_BITS)
) dds_tb_i (
  .ps_clk,
  .ps_phase_inc(ps_dds_phase_inc),
  .dac_clk,
  .dac_data_out(dac_data_out)
);

// triangle testing
logic [tx_pkg::CHANNELS-1:0][TRI_PHASE_BITS-1:0] tri_phase_increment;
triangle_tb #(
  .PHASE_BITS(TRI_PHASE_BITS),
  .CHANNELS(tx_pkg::CHANNELS),
  .PARALLEL_SAMPLES(tx_pkg::PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(tx_pkg::SAMPLE_WIDTH)
) tri_tb_i (
  .ps_clk,
  .ps_phase_inc(ps_tri_phase_inc),
  .dac_clk,
  .dac_trigger(dac_tri_trigger),
  .dac_data_out
);

transmit_top #(
  .DDS_PHASE_BITS(DDS_PHASE_BITS),
  .DDS_QUANT_BITS(DDS_QUANT_BITS),
  .SCALE_WIDTH(SCALE_WIDTH),
  .OFFSET_WIDTH(OFFSET_WIDTH),
  .SCALE_INT_BITS(SCALE_INT_BITS),
  .AWG_DEPTH(AWG_DEPTH),
  .TRI_PHASE_BITS(TRI_PHASE_BITS)
) dut_i (
  .ps_clk,
  .ps_reset,
  .ps_awg_dma_in,
  .ps_awg_frame_depth,
  .ps_awg_trigger_out_config,
  .ps_awg_burst_length,
  .ps_awg_start_stop,
  .ps_awg_dma_error,
  .ps_scale_offset,
  .ps_dds_phase_inc,
  .ps_tri_phase_inc,
  .ps_channel_mux_config,
  .dac_clk,
  .dac_reset,
  .dac_data_out,
  .dac_triggers_out
);

initial begin
  debug.display("### TESTING TRANSMIT TOPLEVEL ###", sim_util_pkg::DEFAULT);

  dac_reset <= 1'b1;
  ps_reset <= 1'b1;

  // reset all configuration interfaces
  awg_tb_i.init();
  dds_tb_i.init();
  tri_tb_i.init();

  // wait a bit before deasserting reset
  repeat (100) @(posedge ps_clk);

  // deassert resets
  ps_reset <= 1'b0;
  @(posedge dac_clk);
  dac_reset <= 1'b0;

  // configure the mux to select the AWG
  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    ps_channel_mux_config.data[channel*$clog2(3*tx_pkg::CHANNELS)+:$clog2(3*tx_pkg::CHANNELS)] <= $clog2(3*tx_pkg::CHANNELS)'(channel);
  end

  // configure the scale factor to be 1 and offset to be 0
  // by default scale_factor = 0, so if we get the correct output we know this write worked
  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    ps_scale_offset.data[channel*(SCALE_WIDTH+OFFSET_WIDTH)+:SCALE_WIDTH+OFFSET_WIDTH] <= {1'b1, {(SCALE_WIDTH + OFFSET_WIDTH - SCALE_INT_BITS){1'b0}}};
  end

  ps_channel_mux_config.valid <= 1'b1;
  do @(posedge ps_clk); while (~(ps_channel_mux_config.valid & ps_channel_mux_config.ready));
  ps_channel_mux_config.valid <= 1'b0;
  ps_scale_offset.valid <= 1'b1;
  do @(posedge ps_clk); while (~(ps_scale_offset.valid & ps_scale_offset.ready));
  ps_scale_offset.valid <= 1'b0;

  // configure the AWG
  // set frame depth, burst length, and output trigger configuration
  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    write_depths[channel] = 16;
    burst_lengths[channel] = 1;
    trigger_modes[channel] = 1;
  end

  awg_tb_i.configure_dut(
    debug,
    trigger_modes,
    burst_lengths,
    write_depths
  );

  // generate samples_to_send, use that to generate dma_words and
  // verify that it matches the desired samples_to_send
  awg_tb_i.generate_samples(debug, write_depths);

  // send DMA data
  debug.display("sending samples over DMA", sim_util_pkg::DEBUG);
  awg_tb_i.send_dma_data(1'b1, 0); // tlast_check = 0 -> send tlast on the last sample
  debug.display("done sending samples over DMA", sim_util_pkg::DEBUG);

  // wait a few cycles to check for transfer error
  repeat (10) begin
    do @(posedge ps_clk); while (~ps_awg_dma_error.ready);
  end
  awg_tb_i.check_transfer_error(debug, 0); // tlast_check = 0

  // send data
  awg_tb_i.do_dac_burst(debug, write_depths, burst_lengths);
  // check response
  debug.display("done sending AWG data, checking output", sim_util_pkg::VERBOSE);
  awg_tb_i.check_output_data(debug, trigger_modes, write_depths, burst_lengths);
  awg_tb_i.clear_receive_data();
  awg_tb_i.clear_send_data();
  
  debug.display("finished testing AWG", sim_util_pkg::VERBOSE);
 
  // configure the mux to select the DDS
  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    ps_channel_mux_config.data[channel*$clog2(3*tx_pkg::CHANNELS)+:$clog2(3*tx_pkg::CHANNELS)] <= $clog2(3*tx_pkg::CHANNELS)'(channel + tx_pkg::CHANNELS);
  end
  ps_channel_mux_config.valid <= 1'b1;
  do @(posedge ps_clk); while (~(ps_channel_mux_config.valid & ps_channel_mux_config.ready));
  ps_channel_mux_config.valid <= 1'b0;
  
  dds_tb_i.set_phases(debug, freqs);
  debug.display("finished configuring DDS", sim_util_pkg::VERBOSE);
  repeat (10) @(posedge ps_clk);
  @(posedge dac_clk);
  dds_tb_i.clear_queues();

  // wait until we get nonzero data, then start adding to dds_received
  // nonzero data now
  debug.display("collecting DDS data", sim_util_pkg::VERBOSE);
  repeat (5000) @(posedge dac_clk);
  debug.display("checking DDS data", sim_util_pkg::VERBOSE);
  // need slightly bigger error margin than dds_test since we've got more
  // drastic phase quantization here, so it's harder to estimate the initial phase
  dds_tb_i.check_output(debug, 16'h007f);
  debug.display("finished testing DDS", sim_util_pkg::VERBOSE);

  // check triangle wave generator
  // configure the mux to select the triangle wave gen
  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    ps_channel_mux_config.data[channel*$clog2(3*tx_pkg::CHANNELS)+:$clog2(3*tx_pkg::CHANNELS)] <= $clog2(3*tx_pkg::CHANNELS)'(channel + 2*tx_pkg::CHANNELS);
  end
  // set phase increment
  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    tri_phase_increment[channel] = $urandom() >> 8;
  end

  tri_tb_i.set_phases(debug, tri_phase_increment);
  
  ps_channel_mux_config.valid <= 1'b1;
  do @(posedge ps_clk); while (~(ps_channel_mux_config.valid & ps_channel_mux_config.ready));
  ps_channel_mux_config.valid <= 1'b0;

  debug.display("finished configuring triangle wave generator", sim_util_pkg::VERBOSE);
  // wait for a trigger
  while (dac_tri_trigger[0] !== 1'b1) @(posedge dac_clk);
  tri_tb_i.clear_queues();
  repeat (20) begin
    do @(posedge dac_clk); while (dac_tri_trigger[0] !== 1'b1);
  end
  tri_tb_i.check_results(debug, tri_phase_increment);
  debug.display("finished checking triangle wave generator", sim_util_pkg::VERBOSE);

  debug.finish();
end

endmodule
