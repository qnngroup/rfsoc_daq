// awg_test.sv - Reed Foster

import sim_util_pkg::*;

`timescale 1ns/1ps

module awg_test ();

sim_util_pkg::debug debug = new(VERBOSE);

parameter int DEPTH = 2048;
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

Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_data_out ();
logic [CHANNELS-1:0] dac_trigger;

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
logic [AXI_MM_WIDTH-1:0] dma_word;
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

task automatic check_dma_words(
  input logic [SAMPLE_WIDTH-1:0] samples_to_send [CHANNELS][$],
  input logic [AXI_MM_WIDTH-1:0] dma_words [$]
);
  // since the task is static and we've declared the queues as inputs, it's
  // safe to pop items frome the queues without worrying about disrupting the
  // state of the calling task/process
  int channel = 0;
  debug.display("checking dma input data", DEBUG);
  debug.display($sformatf("dma_words.size() = %0d", dma_words.size()), DEBUG);
  for (int c = 0; c < CHANNELS; c++) begin
    debug.display($sformatf(
      "samples_to_send[%0d].size() = %0d",
      c,
      samples_to_send[c].size()),
      DEBUG
    );
  end
  while (dma_words.size() > 0) begin
    for (int sample = 0; sample < AXI_MM_WIDTH/SAMPLE_WIDTH; sample++) begin
      if (dma_words[$][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH] !== samples_to_send[channel][0]) begin
        debug.error($sformatf(
          "mismatched sample at dma_words[%0d] for channel %0d, got %x expected %x",
          dma_words.size() - 1,
          channel,
          dma_words[$][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH],
          samples_to_send[channel][0])
        );
      end
      if (samples_to_send[channel].size() == 0) begin
        debug.fatal($sformatf(
          {
            "incorrect dma word alignment of samples",
            "\nwrite_depth should be a multiple of (AXI_MM_WIDTH + ",
            "SAMPLE_WIDTH*PARALLEL_SAMPLES - 1)/(SAMPLE_WIDTH*PARALLEL_SAMPLES)",
            " = %0d/%0d = %0d"
          },
          AXI_MM_WIDTH + SAMPLE_WIDTH*PARALLEL_SAMPLES - 1, SAMPLE_WIDTH*PARALLEL_SAMPLES,
          (SAMPLE_WIDTH*PARALLEL_SAMPLES + AXI_MM_WIDTH - 1)/(SAMPLE_WIDTH*PARALLEL_SAMPLES))
        );
      end
      samples_to_send[channel].pop_front();
    end
    dma_words.pop_back();
    if (samples_to_send[channel].size() == 0) begin
      channel = channel + 1;
    end
  end
  if (channel != CHANNELS) begin
    debug.error("dma_words did not have enough samples");
  end
  debug.display("done checking dma_words", DEBUG);
endtask

task automatic check_output_data(
  input logic [SAMPLE_WIDTH-1:0] samples_to_send [CHANNELS][$],
  input logic [SAMPLE_WIDTH-1:0] samples_received [CHANNELS][$],
  input int trigger_arrivals [CHANNELS][$],
  input logic [1:0] trigger_modes [CHANNELS],
  input logic [$clog2(DEPTH):0] write_depths [CHANNELS],
  input logic [63:0] burst_lengths [CHANNELS]
);
  int sample_count;
  int burst_count;
  for (int channel = 0; channel < CHANNELS; channel++) begin
    sample_count = 0;
    burst_count = 0;
    debug.display($sformatf("checking output for channel %0d", channel), VERBOSE);
    if (samples_received[channel].size()
        != write_depths[channel]*burst_lengths[channel]*PARALLEL_SAMPLES) begin
      debug.error($sformatf(
        {
          "incorrect number of samples received on channel %0d.",
          "\nbased on write_depths*burst_lengths, expected %0d;",
          "\nbased on samples_to_send, expected %0d;",
          "\ngot %0d"
        },
        channel,
        write_depths[channel]*burst_lengths[channel]*PARALLEL_SAMPLES,
        samples_to_send[channel].size(),
        samples_received[channel].size())
      );
    end
    while (samples_received[channel].size() > 0) begin
      if (samples_received[channel][$] !== samples_to_send[channel][sample_count]) begin
        debug.error($sformatf(
          "channel %0d: mismatch on sample %0d (burst %0d), sent %x, received %x",
          channel,
          sample_count,
          burst_count,
          samples_to_send[channel][sample_count],
          samples_received[channel][$])
        );
      end
      samples_received[channel].pop_back();
      if (sample_count == write_depths[channel]*PARALLEL_SAMPLES - 1) begin
        burst_count = burst_count + 1;
      end
      sample_count = (sample_count + 1) % (write_depths[channel]*PARALLEL_SAMPLES);
    end
    // check for correct timing of trigger signals
    case (trigger_modes[channel])
      0: begin
        // make sure we didn't get any
        if (trigger_arrivals[channel].size() > 0) begin
          debug.error($sformatf(
            "channel %0d: expected zero triggers, but got %0d triggers",
            channel,
            trigger_arrivals[channel].size())
          );
        end
      end
      1: begin
        // should have exactly one, with value 0
        if (trigger_arrivals[channel].size() !== 1) begin
          debug.error($sformatf(
            "channel %0d: expected exactly one trigger, but got %0d triggers",
            channel,
            trigger_arrivals[channel].size())
          );
        end
        if (trigger_arrivals[channel][0] !== 0) begin
          debug.error($sformatf(
            "channel %0d: wrong trigger timing, got %0d, expected 0",
            channel,
            trigger_arrivals[channel][0])
          );
        end
      end
      2: begin
        // should have burst_lengths[channel], with values k*write_depths[channel]*PARALLEL_SAMPLES for k = 0,1,2,...
        if (trigger_arrivals[channel].size() !== burst_lengths[channel]) begin
          debug.error($sformatf(
            "channel %0d: expected exactly %0d triggers, but got %0d triggers",
            channel,
            burst_lengths[channel],
            trigger_arrivals[channel].size())
          );
        end
        for (int frame = 0; frame < burst_lengths[channel]; frame++) begin
          if (trigger_arrivals[channel][frame] !== frame*write_depths[channel]*PARALLEL_SAMPLES) begin
            debug.error($sformatf(
              "channel %0d: wrong trigger timing, got %0d, expected %0d",
              channel,
              trigger_arrivals[channel][frame],
              frame*write_depths[channel])
            );
          end
        end
      end
    endcase
  end
endtask

task automatic configure_dut(
  input logic [1:0] trigger_modes [CHANNELS],
  input logic [$clog2(DEPTH):0] write_depths [CHANNELS],
  input logic [63:0] burst_lengths [CHANNELS]
);
  bit register_write_success;
  // first update the trigger configuration
  for (int channel = 0; channel < CHANNELS; channel++) begin
    dma_trigger_out_config.data[channel*2+:2] <= trigger_modes[channel];
  end
  dma_trigger_out_config.send_sample_with_timeout(dma_clk, 10, register_write_success);
  if (~register_write_success) begin
    debug.error("failed to update trigger configuration register");
  end

  // then, set the burst lengths
  for (int channel = 0; channel < CHANNELS; channel++) begin
    dma_awg_burst_length.data[channel*64+:64] <= burst_lengths[channel];
  end
  dma_awg_burst_length.send_sample_with_timeout(dma_clk, 10, register_write_success);
  if (~register_write_success) begin
    debug.error("failed to update burst length register");
  end

  // finally, update the write depth, which will put the DUT into a state
  // where it is ready to accept DMA data
  for (int channel = 0; channel < CHANNELS; channel++) begin
    dma_write_depth.data[channel*(1+$clog2(DEPTH))+:(1+$clog2(DEPTH))] <= write_depths[channel];
  end
  dma_write_depth.send_sample_with_timeout(dma_clk, 10, register_write_success);
  if (~register_write_success) begin
    debug.fatal("failed to update write_depth register; cannot proceed with DMA");
  end
endtask

task automatic generate_samples(
  input logic [$clog2(DEPTH):0] write_depths [CHANNELS],
  output logic [SAMPLE_WIDTH-1:0] samples_to_send [CHANNELS][$],
  output logic [AXI_MM_WIDTH-1:0] dma_words [$]
);

  for (int channel = 0; channel < CHANNELS; channel++) begin
    for (int batch = 0; batch < write_depths[channel]; batch++) begin
      for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
        samples_to_send[channel].push_back($urandom_range(1,{SAMPLE_WIDTH{1'b1}}));
      end
    end
  end

  // reform samples into AXI_MM_WIDTH-wide words
  for (int channel = 0; channel < CHANNELS; channel++) begin
    for (int word = 0; word < (write_depths[channel]*PARALLEL_SAMPLES*SAMPLE_WIDTH)/AXI_MM_WIDTH; word++) begin
      dma_word = '0;
      for (int sample = 0; sample < AXI_MM_WIDTH/SAMPLE_WIDTH; sample++) begin
        dma_word = {samples_to_send[channel][word*(AXI_MM_WIDTH/SAMPLE_WIDTH)+sample],
                    dma_word[AXI_MM_WIDTH-1:SAMPLE_WIDTH]};
      end
      dma_words.push_front(dma_word);
    end
  end

  // check to make sure we actually send the right data to the AWG
  check_dma_words(samples_to_send, dma_words);

  for (int i = 0; i < dma_words.size(); i++) begin
    debug.display($sformatf("dma_words[%0d] = %x", i, dma_words[$-i]), DEBUG);
  end
endtask

task automatic do_dac_burst();
  // start outputting DMA data
  dma_awg_start_stop.data <= 2'b10;
  dma_awg_start_stop.valid <= 1'b1;
  while (!dma_awg_start_stop.ok) @(posedge dma_clk);
  dma_awg_start_stop.valid <= 1'b0;
  @(posedge dma_clk);
  
  // wait until we get data that's nonzero (we only send nonzero data so
  // it's easier to check this)
  // there should be a way to get the latency accurately, but it's kind of
  // annoying since the start signal has to cross clock domains
  do begin @(posedge dac_clk); end while (dac_data_out.valid !== '1);
  debug.display("waiting until dac_data_out.data is nonzero", DEBUG);
  while (dac_data_out.data === '0) @(posedge dac_clk);
  // we have nonzero data now, so wait until all channels become inactive
  while (dac_data_out.data !== '0) begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      // save trigger arrival if it happens
      if (dac_trigger[channel] === 1'b1) begin
        trigger_arrivals[channel].push_back(samples_received[channel].size());
      end
      if (samples_received[channel].size() < write_depths[channel]*burst_lengths[channel]*PARALLEL_SAMPLES) begin
        for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
          samples_received[channel].push_front(dac_data_out.data[channel][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH]);
        end
      end else begin
        if (dac_data_out.data[channel] !== '0) begin
          debug.error($sformatf(
            {
              "Got nonzero set of samples (%x) on DAC channel %0d.",
              "\nAfter %0d bursts of depth %0d, samples_received[%0d].size() = %0d"
            },
            dac_data_out.data[channel],
            channel,
            burst_lengths[channel],
            write_depths[channel],
            channel,
            samples_received[channel].size())
          );
        end
      end
    end
    @(posedge dac_clk);
  end
  debug.display("finished receiving data from dac_data_out", DEBUG);
endtask

initial begin
  debug.display("### TESTING ARBITRARY WAVEFORM GENERATOR ###", DEFAULT);
  debug.display("############################################", DEFAULT);
  debug.display("######## TEST TODO LIST ####################", DEFAULT);
  debug.display("############################################", DEFAULT);

  debug.display(" [ ] test with a zero-length frame",                              DEFAULT);
  debug.display(" [ ] test with a max-length frame",                               DEFAULT);
  debug.display(" [ ] test with random-length frame",                              DEFAULT);
  debug.display("                                  ",                              DEFAULT);
  debug.display(" [ ] test with a zero-length burst",                              DEFAULT);
  debug.display(" [ ] test with a random-length burst",                            DEFAULT);
  debug.display("                                    ",                            DEFAULT);
  debug.display(" [x] check that triggers are being produced correctly",           DEFAULT);
  debug.display(" [x] check output values match what was sent",                    DEFAULT);
  debug.display("                                            ",                    DEFAULT);
  debug.display(" [x] check that dma_transfer_error produces the correct output",  DEFAULT);
  debug.display(" [x] check behavior when sending start signal multiple times",    DEFAULT);

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
    write_depths[channel] = 16;
    burst_lengths[channel] = 4;
    trigger_modes[channel] = 2;
  end
 
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
        configure_dut(trigger_modes, write_depths, burst_lengths);

        // generate samples_to_send, use that to generate dma_words and
        // verify that it matches the desired samples_to_send
        generate_samples(write_depths, samples_to_send, dma_words);

        dma_data_in.data <= dma_words.pop_back();
        dma_data_in.send_samples(dma_clk, (dma_words.size() / 4) * 2, rand_valid & 1'b1, 1'b1, 1'b0);
        dma_data_in.last <= 1'b0;
        if (tlast_check == 2) begin
          // send early tlast
          dma_data_in.valid <= 1'b1;
          dma_data_in.last <= 1'b1;
          while (~dma_data_in.ok) @(posedge dma_clk);
        end else begin
          dma_data_in.send_samples(dma_clk, dma_words.size(), rand_valid & 1'b1, 1'b0, 1'b0);
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

        // check that the correct transfer error was reported
        dma_transfer_error.ready <= 1'b1;
        while (~dma_transfer_error.ok) @(posedge dma_clk);
        if (dma_transfer_error.data !== tlast_check) begin
          debug.error($sformatf(
            "expected transfer error code %0d, got error code %0d",
            tlast_check,
            dma_transfer_error.data)
          );
        end
        @(posedge dma_clk);
        // check that transfer_error is no longer valid (valid should reset after being read)
        if (dma_transfer_error.valid) begin
          debug.error("read out dma_transfer_error, but it didn't reset");
        end
        dma_transfer_error.ready <= 1'b0;
        
        if (start_repeat_count == 0) begin
          // need to send stop signal to return to the IDLE state
          dma_awg_start_stop.data <= 2'b01;
          dma_awg_start_stop.valid <= 1'b1;
          while (!dma_awg_start_stop.ok) @(posedge dma_clk);
          dma_awg_start_stop.valid <= 1'b0;
          @(posedge dma_clk);
        end else begin
          for (int i = 0; i < start_repeat_count; i++) begin
            do_dac_burst();
            if (tlast_check == 0) begin
              check_output_data(
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

always @(posedge dma_clk) begin
  if (dut_i.dma_write_enable & (~dut_i.dma_write_done[dut_i.dma_write_channel])) begin
    debug.display($sformatf("writing to buffer[%0d][%0d] <= %x", dut_i.dma_write_channel, dut_i.dma_write_address, dut_i.dma_write_data_reg), DEBUG);
  end
end

endmodule
