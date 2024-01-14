// awg_pkg.sv - Reed Foster
// utilities for testing AWG module

import sim_util_pkg::*;

package awg_pkg;

  class util #(
    parameter int DEPTH = 256,
    parameter int AXI_MM_WIDTH = 128,
    parameter int PARALLEL_SAMPLES = 16,
    parameter int SAMPLE_WIDTH = 16,
    parameter int CHANNELS = 8
  );

    // https://verificationacademy.com/forums/t/typedef-interface/34464
    // https://www.reddit.com/r/Verilog/comments/1158h4w/trouble_with_parameterized_virtual_interfaces/

    typedef virtual Axis_If #(.DWIDTH((1+$clog2(DEPTH))*CHANNELS)) write_depth_if;
    typedef virtual Axis_If #(.DWIDTH(2*CHANNELS))                 trig_cfg_if;
    typedef virtual Axis_If #(.DWIDTH(64*CHANNELS))                burst_len_if;
    typedef virtual Axis_If #(.DWIDTH(2))                          start_stop_if;
    typedef virtual Axis_If #(.DWIDTH(2))                          transfer_error_if;
    typedef virtual Realtime_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) data_out_if;

    write_depth_if    v_dma_write_depth;
    trig_cfg_if       v_dma_trigger_out_config;
    burst_len_if      v_dma_awg_burst_length;
    start_stop_if     v_dma_awg_start_stop;
    transfer_error_if v_dma_transfer_error;
    data_out_if       v_dac_data_out;

    function new (
      input write_depth_if    dma_write_depth,
      input trig_cfg_if       dma_trigger_out_config,
      input burst_len_if      dma_awg_burst_length,
      input start_stop_if     dma_awg_start_stop,
      input transfer_error_if dma_transfer_error,
      input data_out_if       dac_data_out
    );
      v_dma_write_depth         = dma_write_depth;
      v_dma_trigger_out_config  = dma_trigger_out_config;
      v_dma_awg_burst_length    = dma_awg_burst_length;
      v_dma_awg_start_stop      = dma_awg_start_stop;
      v_dma_transfer_error      = dma_transfer_error;
      v_dac_data_out            = dac_data_out;
    endfunction

    task automatic check_dma_words(
      inout sim_util_pkg::debug debug,
      input logic [SAMPLE_WIDTH-1:0] samples_to_send [CHANNELS][$],
      input logic [AXI_MM_WIDTH-1:0] dma_words [$]
    );
      // since the task is static and we've declared the queues as inputs, it's
      // safe to pop items frome the queues without worrying about disrupting the
      // state of the calling task/process
      int channel = 0;
      debug.display("checking dma input data", sim_util_pkg::DEBUG);
      debug.display($sformatf("dma_words.size() = %0d", dma_words.size()), sim_util_pkg::DEBUG);
      for (int c = 0; c < CHANNELS; c++) begin
        debug.display($sformatf(
          "samples_to_send[%0d].size() = %0d",
          c,
          samples_to_send[c].size()),
          sim_util_pkg::DEBUG
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
      debug.display("done checking dma_words", sim_util_pkg::DEBUG);
    endtask

    task automatic check_output_data(
      inout sim_util_pkg::debug debug,
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
        debug.display($sformatf("checking output for channel %0d", channel), sim_util_pkg::VERBOSE);
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
      inout sim_util_pkg::debug debug,
      ref logic dma_clk,
      input logic [1:0] trigger_modes [CHANNELS],
      input logic [$clog2(DEPTH):0] write_depths [CHANNELS],
      input logic [63:0] burst_lengths [CHANNELS]
    );
      bit register_write_success;
      // first update the trigger configuration
      for (int channel = 0; channel < CHANNELS; channel++) begin
        v_dma_trigger_out_config.data[channel*2+:2] <= trigger_modes[channel];
      end
      v_dma_trigger_out_config.send_sample_with_timeout(dma_clk, 10, register_write_success);
      if (~register_write_success) begin
        debug.error("failed to update trigger configuration register");
      end
    
      // then, set the burst lengths
      for (int channel = 0; channel < CHANNELS; channel++) begin
        v_dma_awg_burst_length.data[channel*64+:64] <= burst_lengths[channel];
      end
      v_dma_awg_burst_length.send_sample_with_timeout(dma_clk, 10, register_write_success);
      if (~register_write_success) begin
        debug.error("failed to update burst length register");
      end
    
      // finally, update the write depth, which will put the DUT into a state
      // where it is ready to accept DMA data
      for (int channel = 0; channel < CHANNELS; channel++) begin
        v_dma_write_depth.data[channel*(1+$clog2(DEPTH))+:(1+$clog2(DEPTH))] <= write_depths[channel];
      end
      v_dma_write_depth.send_sample_with_timeout(dma_clk, 10, register_write_success);
      if (~register_write_success) begin
        debug.fatal("failed to update write_depth register; cannot proceed with DMA");
      end
    endtask
    
    task automatic generate_samples(
      inout sim_util_pkg::debug debug,
      input logic [$clog2(DEPTH):0] write_depths [CHANNELS],
      inout logic [SAMPLE_WIDTH-1:0] samples_to_send [CHANNELS][$],
      inout logic [AXI_MM_WIDTH-1:0] dma_words [$]
    );
      logic [AXI_MM_WIDTH-1:0] dma_word;
    
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
      check_dma_words(debug, samples_to_send, dma_words);
    
      for (int i = 0; i < dma_words.size(); i++) begin
        debug.display($sformatf("dma_words[%0d] = %x", i, dma_words[$-i]), sim_util_pkg::DEBUG);
      end
    endtask

    task automatic check_transfer_error(
      inout sim_util_pkg::debug debug,
      ref logic dma_clk,
      input int tlast_check
    );
      // check that the correct transfer error was reported
      v_dma_transfer_error.ready <= 1'b1;
      while (~v_dma_transfer_error.ok) @(posedge dma_clk);
      if (v_dma_transfer_error.data !== tlast_check) begin
        debug.error($sformatf(
          "expected transfer error code %0d, got error code %0d",
          tlast_check,
          v_dma_transfer_error.data)
        );
      end
      @(posedge dma_clk);
      // check that transfer_error is no longer valid (valid should reset after being read)
      if (v_dma_transfer_error.valid) begin
        debug.error("read out dma_transfer_error, but it didn't reset");
      end
      v_dma_transfer_error.ready <= 1'b0;
    endtask
    
    task automatic do_dac_burst(
      inout sim_util_pkg::debug debug,
      ref logic dac_clk,
      ref logic dma_clk,
      ref logic [CHANNELS-1:0] dac_trigger,
      output int trigger_arrivals [CHANNELS][$],
      inout [SAMPLE_WIDTH-1:0] samples_received [CHANNELS][$],
      input logic [$clog2(DEPTH):0] write_depths [CHANNELS],
      input logic [63:0] burst_lengths [CHANNELS]
    );
      debug.display("running DAC burst", sim_util_pkg::DEBUG);
      // start outputting DMA data
      v_dma_awg_start_stop.data <= 2'b10;
      v_dma_awg_start_stop.valid <= 1'b1;
      while (!v_dma_awg_start_stop.ok) @(posedge dma_clk);
      v_dma_awg_start_stop.valid <= 1'b0;
      @(posedge dma_clk);
      debug.display("sent start command, waiting for DAC data to be valid", sim_util_pkg::DEBUG);
      
      // wait until we get data that's nonzero (we only send nonzero data so
      // it's easier to check this)
      // there should be a way to get the latency accurately, but it's kind of
      // annoying since the start signal has to cross clock domains
      do begin @(posedge dac_clk); end while (v_dac_data_out.valid !== '1);
      debug.display("waiting until dac_data_out.data is nonzero", sim_util_pkg::DEBUG);
      while (v_dac_data_out.data === '0) @(posedge dac_clk);
      // we have nonzero data now, so wait until all channels become inactive
      while (v_dac_data_out.data !== '0) begin
        for (int channel = 0; channel < CHANNELS; channel++) begin
          // save trigger arrival if it happens
          if (dac_trigger[channel] === 1'b1) begin
            debug.display($sformatf(
              "got trigger on channel %0d for time %0d",
              channel,
              samples_received[channel].size()),
              sim_util_pkg::DEBUG
            );
            trigger_arrivals[channel].push_back(samples_received[channel].size());
          end
          if (samples_received[channel].size() < write_depths[channel]*burst_lengths[channel]*PARALLEL_SAMPLES) begin
            for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
              samples_received[channel].push_front(v_dac_data_out.data[channel][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH]);
            end
          end else begin
            if (v_dac_data_out.data[channel] !== '0) begin
              debug.error($sformatf(
                {
                  "Got nonzero set of samples (%x) on DAC channel %0d.",
                  "\nAfter %0d bursts of depth %0d, samples_received[%0d].size() = %0d"
                },
                v_dac_data_out.data[channel],
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
      debug.display("finished receiving data from dac_data_out", sim_util_pkg::DEBUG);
    endtask

  endclass

endpackage
