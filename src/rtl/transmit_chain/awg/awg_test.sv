// awg_test.sv - Reed Foster
// Stress test of arbitrary waveform generator
// Writes a random waveform to the AWG buffer memory and triggers the
// generation of zero or more bursts:
//  - checks output values match what was sent
//  - checks that triggers are being produced correctly
//  - checks that dma_transfer_error produces the correct output when tlast
//      doesn't arrive on the right cycle (also implicitly checks that the
//      module can recover from this event without needing to be reset)
//  - tests behavior when sending start signal multiple times
//  - tests with a max-length frame
//  - tests with random-length frame
//  - tests with a random-length burst

import sim_util_pkg::*;
import awg_pkg::*;

`timescale 1ns/1ps

module awg_test ();

sim_util_pkg::debug debug = new(DEFAULT);

parameter int DEPTH = 256;
parameter int AXI_MM_WIDTH = 128;
parameter int PARALLEL_SAMPLES = 16;
parameter int SAMPLE_WIDTH = 16;
parameter int CHANNELS = 8;

logic dac_reset;
logic dac_clk = 0;
localparam DAC_CLK_RATE_HZ = 384_000_000;
always #(0.5s/DAC_CLK_RATE_HZ) dac_clk = ~dac_clk;

logic dma_reset;
logic dma_clk = 0;
localparam DMA_CLK_RATE_HZ = 100_000_000;
always #(0.5s/DMA_CLK_RATE_HZ) dma_clk = ~dma_clk;

Axis_If #(.DWIDTH(AXI_MM_WIDTH)) dma_data_in ();
Axis_If #(.DWIDTH((1+$clog2(DEPTH))*CHANNELS)) dma_write_depth ();
Axis_If #(.DWIDTH(2*CHANNELS)) dma_trigger_out_config ();
Axis_If #(.DWIDTH(64*CHANNELS)) dma_awg_burst_length ();
Axis_If #(.DWIDTH(2)) dma_awg_start_stop ();
Axis_If #(.DWIDTH(2)) dma_transfer_error ();

Realtime_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_data_out ();
logic [CHANNELS-1:0] dac_trigger;

awg_pkg::util #(
  .DEPTH(DEPTH),
  .AXI_MM_WIDTH(AXI_MM_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .CHANNELS(CHANNELS)
) util = new(
  dma_write_depth,
  dma_trigger_out_config,
  dma_awg_burst_length,
  dma_awg_start_stop,
  dma_transfer_error,
  dac_data_out
);

awg #(
  .DEPTH(DEPTH),
  .AXI_MM_WIDTH(AXI_MM_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .CHANNELS(CHANNELS)
) dut_i (
  .dma_clk,
  .dma_reset,
  .dma_data_in,
  .dma_write_depth,
  .dma_trigger_out_config,
  .dma_awg_burst_length,
  .dma_awg_start_stop,
  .dma_transfer_error,
  .dac_clk,
  .dac_reset,
  .dac_data_out,
  .dac_trigger
);

logic [$clog2(DEPTH):0] write_depths [CHANNELS];
logic [63:0] burst_lengths [CHANNELS];
logic [1:0] trigger_modes [CHANNELS];
logic [SAMPLE_WIDTH-1:0] samples_to_send [CHANNELS][$];
logic [AXI_MM_WIDTH-1:0] dma_words [$];
logic [SAMPLE_WIDTH-1:0] samples_received [CHANNELS][$];
int trigger_arrivals [CHANNELS][$];

always @(posedge dma_clk) begin
  if (dma_data_in.ok) begin
    if (dma_words.size() > 0) begin
      dma_data_in.data <= dma_words.pop_back();
    end else begin
      dma_data_in.data <= '0;
    end
  end
end

initial begin
  debug.display("### TESTING ARBITRARY WAVEFORM GENERATOR ###", DEFAULT);

  dac_reset <= 1'b1;
  dma_reset <= 1'b1;
  dma_data_in.valid <= 1'b0;
  dma_data_in.last <= 1'b0;
  dma_trigger_out_config.valid <= 1'b0;
  dma_awg_burst_length.valid <= 1'b0;
  dma_write_depth.valid <= 1'b0;
  dma_awg_start_stop.valid <= 1'b0;
  dma_transfer_error.ready <= 1'b0;

  repeat (100) @(posedge dma_clk);
  dma_reset <= 1'b0;
  @(posedge dac_clk);
  dac_reset <= 1'b0;

  for (int channel = 0; channel < CHANNELS; channel++) begin
    write_depths[channel] = $urandom_range(1, DEPTH/2);
    burst_lengths[channel] = $urandom_range(1, 4);
    trigger_modes[channel] = $urandom_range(0, 2);
  end
  write_depths[0] = DEPTH; // test max-depth
 
  for (int start_repeat_count = 0; start_repeat_count < 5; start_repeat_count += 1 + 2*start_repeat_count) begin
    for (int rand_valid = 0; rand_valid < 2; rand_valid++) begin
      for (int tlast_check = 0; tlast_check < 3; tlast_check++) begin
        debug.display($sformatf(
          "running test with start_repeat_count = %0d, tlast_check = %0d, rand_valid = %0d",
          start_repeat_count,
          tlast_check,
          rand_valid),
          VERBOSE
        );
        // set registers to configure the DUT
        util.configure_dut(
          debug,
          dma_clk,
          trigger_modes,
          write_depths,
          burst_lengths
        );

        // generate samples_to_send, use that to generate dma_words and
        // verify that it matches the desired samples_to_send
        util.generate_samples(debug, write_depths, samples_to_send, dma_words);

        dma_data_in.data <= dma_words.pop_back();
        dma_data_in.send_samples(dma_clk, (dma_words.size() / 4) * 2, rand_valid & 1'b1, 1'b1);
        dma_data_in.last <= 1'b0;
        if (tlast_check == 2) begin
          // send early tlast
          dma_data_in.valid <= 1'b1;
          dma_data_in.last <= 1'b1;
          while (~dma_data_in.ok) @(posedge dma_clk);
        end else begin
          dma_data_in.send_samples(dma_clk, dma_words.size(), rand_valid & 1'b1, 1'b0);
          dma_data_in.valid <= 1'b1; // may have been reset by rand_valid
          while (~dma_data_in.ok) @(posedge dma_clk);
          // one sample left, update tlast under normal operation
          if (tlast_check == 0) begin
            dma_data_in.last <= 1'b1;
            do @(posedge dma_clk); while (~dma_data_in.ok);
          end else begin
            dma_data_in.last <= 1'b0;
            do @(posedge dma_clk); while (~dma_data_in.ok);
          end
        end
        dma_data_in.valid <= 1'b0;
        dma_data_in.last <= 1'b0;

        debug.display("done sending samples over DMA", DEBUG);

        util.check_transfer_error(debug, dma_clk, tlast_check);
        
        if (start_repeat_count == 0) begin
          // need to send stop signal to return to the IDLE state
          dma_awg_start_stop.data <= 2'b01;
          dma_awg_start_stop.valid <= 1'b1;
          while (!dma_awg_start_stop.ok) @(posedge dma_clk);
          dma_awg_start_stop.valid <= 1'b0;
          @(posedge dma_clk);
        end else begin
          for (int i = 0; i < start_repeat_count; i++) begin
            util.do_dac_burst(
              debug,
              dac_clk,
              dma_clk,
              dac_trigger,
              trigger_arrivals,
              samples_received,
              write_depths,
              burst_lengths
            );
            for (int channel = 0; channel < CHANNELS; channel++) begin
              debug.display($sformatf("trigger_arrivals[%0d].size() = %0d", channel, trigger_arrivals[channel].size()), sim_util_pkg::DEBUG);
            end
            if (tlast_check == 0) begin
              util.check_output_data(
                debug,
                samples_to_send,
                samples_received,
                trigger_arrivals,
                trigger_modes,
                write_depths,
                burst_lengths
              );
            end else begin
              debug.display($sformatf(
                "tlast_check = %0d, so not going to check output data since it will be garbage",
                tlast_check),
                VERBOSE
              );
            end
            // clear receive queues
            for (int channel = 0; channel < CHANNELS; channel++) begin
              while (samples_received[channel].size() > 0) samples_received[channel].pop_back();
              while (trigger_arrivals[channel].size() > 0) trigger_arrivals[channel].pop_back();
            end
          end
        end
        // clear send queues (outside of start_repeat_count loop so that we
        // keep track of the values the DAC is sending each iteration of the
        // loop)
        for (int channel = 0; channel < CHANNELS; channel++) begin
          while (samples_to_send[channel].size() > 0) samples_to_send[channel].pop_back();
        end
        while (dma_words.size() > 0) dma_words.pop_back();
      end
    end
  end
  debug.finish();
end

endmodule
