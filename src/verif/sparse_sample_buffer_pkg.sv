// sparse_sample_buffer_pkg.sv - Reed Foster
// package with a class for parsing the sparse sample buffer output

import sim_util_pkg::*;
import sample_discriminator_pkg::*;

package sparse_sample_buffer_pkg;

  class util #(
    parameter int AXI_MM_WIDTH = 128,
    parameter int TIMESTAMP_WIDTH = 64,
    parameter int SAMPLE_WIDTH = 16,
    parameter int PARALLEL_SAMPLES = 16,
    parameter int DATA_BUFFER_DEPTH = 1024,
    parameter int CHANNELS = 8
  );

    localparam int SAMPLE_INDEX_WIDTH = $clog2(DATA_BUFFER_DEPTH*CHANNELS);
    localparam int DATA_WIDTH = SAMPLE_WIDTH*PARALLEL_SAMPLES;

    // util for functions any_above_high and all_below_low for comparing data to thresholds
    sample_discriminator_pkg::util #(
      .SAMPLE_WIDTH(SAMPLE_WIDTH),
      .PARALLEL_SAMPLES(PARALLEL_SAMPLES)
    ) disc_util;

    task automatic parse_buffer_output (
      inout logic [AXI_MM_WIDTH-1:0] buffer_output [$],
      output logic [TIMESTAMP_WIDTH-1:0] timestamps [CHANNELS][$],
      output logic [DATA_WIDTH-1:0] samples [CHANNELS][$]
    );
      logic [2*AXI_MM_WIDTH-1:0] dma_word;
      int dma_word_leftover_bits;
      int current_channel, words_remaining;
      int parsed_bank_count;
      int word_width;
      bit need_channel_id, need_word_count;
      bit done_parsing;
      enum {TIMESTAMP, DATA} parse_mode;

      // Since each DMA word is not aligned with the size of the
      // samples/timestamps, break up the DMA output into individual samples and
      // timestamps. Logically, this code converts the DMA output (which is stored
      // as a queue of words that are AXI_MM_WIDTH wide) into a single, very long
      // word, which is then scanned into separate queues corresponding to samples
      // and timestamps. Also parses the information of channel ID and sample
      // count that are outputted at the beginning of each bank's readout cycle
      dma_word_leftover_bits = 0;
      // first, we parse timestamps, then we parse samples
      word_width = TIMESTAMP_WIDTH;
      parse_mode = TIMESTAMP;
      // initialize big long word that contains timestamps or samples
      dma_word = '0;
      need_channel_id = 1'b1;
      need_word_count = 1'b1;
      parsed_bank_count = 0;
      done_parsing = 0;
      while (!done_parsing) begin
        // combine remaining bits with new word
        dma_word = (buffer_output.pop_back() << dma_word_leftover_bits) | dma_word;
        dma_word_leftover_bits = dma_word_leftover_bits + AXI_MM_WIDTH;
        while (dma_word_leftover_bits >= word_width) begin
          // data is always organized as so:
          // [channel_id, tstamp_count, tstamp_0, ..., channel_id, tstamp_count, ...]
          // so first update the channel ID, then update the number of timestamps
          // to add to that channel, then finally collect those timestamps
          if (need_channel_id) begin
            // mask lower bits depending on whether we're parsing timestamps or data
            current_channel = dma_word & ((1'b1 << word_width) - 1);
            need_channel_id = 1'b0;
            need_word_count = 1'b1;
          end else begin
            if (need_word_count) begin
              // mask lower bits depending on whether we're parsing timestamps or data
              words_remaining = dma_word & ((1'b1 << word_width) - 1);
              need_word_count = 1'b0;
            end else begin
              unique case (parse_mode)
                TIMESTAMP: begin
                  // mask lower bits based on timestamp width
                  timestamps[current_channel].push_front(dma_word & ((1'b1 << word_width) - 1));
                end
                DATA: begin
                  // mask lower bits based on data width
                  samples[current_channel].push_front(dma_word & ((1'b1 << word_width) - 1));
                end
              endcase
              words_remaining = words_remaining - 1;
            end
            // check if we have read all the timestamps or data
            if (words_remaining == 0) begin
              need_channel_id = 1'b1;
              parsed_bank_count = parsed_bank_count + 1;
            end
          end
          // check if we're done with all channels
          if (parsed_bank_count == CHANNELS) begin
            // if we're done with all channels, but we were in the timestamp mode,
            // then shift to data mode
            if (parse_mode == TIMESTAMP) begin
              word_width = DATA_WIDTH;
              parse_mode = DATA;
            end else begin
              done_parsing = 1;
            end
            // reset DMA word, the rest of the word is garbage; the data
            // information will come on the next word
            dma_word = '0;
            dma_word_leftover_bits = 0;
            parsed_bank_count = 0;
          end else begin
            dma_word = dma_word >> word_width;
            dma_word_leftover_bits = dma_word_leftover_bits - word_width;
          end
        end
      end

    endtask

    task automatic check_timestamps_and_data (
      inout sim_util_pkg::debug debug,
      input int banking_mode,
      input logic [CHANNELS-1:0][SAMPLE_WIDTH-1:0] threshold_high,
      input logic [CHANNELS-1:0][SAMPLE_WIDTH-1:0] threshold_low,
      inout logic [CHANNELS-1:0][TIMESTAMP_WIDTH-SAMPLE_INDEX_WIDTH-1:0] timer,
      inout logic [TIMESTAMP_WIDTH-1:0] timestamps [CHANNELS][$],
      inout logic [DATA_WIDTH-1:0] samples [CHANNELS][$],
      inout logic [DATA_WIDTH-1:0] expected_samples [CHANNELS][$],
      input bit buffer_filled
    );
      // signals for checking correct operation of the DUT
      logic is_high;
      logic [SAMPLE_INDEX_WIDTH-1:0] sample_index;
     
      // Make sure the correct number of samples and timestamps were received, and
      // that the hysteresis tracking worked correctly (i.e. no samples above the
      // high threshold were missed, and no samples below the low threshold passed
      // through, as well as no missing samples that were above the low threshold
      // and appeared after a sample that was above the high threshold).

      // first check that we didn't get any extra samples or timestamps
      for (int channel = 1 << banking_mode; channel < CHANNELS; channel++) begin
        if (timestamps[channel].size() > 0) begin
          debug.error($sformatf(
            "received too many timestamps for channel %0d with banking mode %0d (got %0d, expected 0)",
            channel,
            banking_mode,
            timestamps[channel].size()
          ));
        end
        while (timestamps[channel].size() > 0) timestamps[channel].pop_back();
        if (samples[channel].size() > 0) begin
          debug.error($sformatf(
            "received too many samples for channel %0d with banking mode %0d (got %0d, expected 0)",
            channel,
            banking_mode,
            samples[channel].size()
          ));
        end
        while (samples[channel].size() > 0) samples[channel].pop_back();
        // clean up data sent
        debug.display($sformatf(
          "removing %0d samples from expected_samples [%0d]",
          expected_samples[channel].size(),
          channel
        ), sim_util_pkg::VERBOSE);
        while (expected_samples[channel].size() > 0) begin
          expected_samples[channel].pop_back();
          timer[channel] = timer[channel] + 1'b1;
        end
      end

      for (int channel = 0; channel < (1 << banking_mode); channel++) begin
        // report timestamp/sample queue sizes
        debug.display($sformatf(
          "timestamps[%0d].size() = %0d",
          channel,
          timestamps[channel].size()
        ), sim_util_pkg::VERBOSE);
        debug.display($sformatf(
          "samples[%0d].size() = %0d",
          channel,
          samples[channel].size()
        ), sim_util_pkg::VERBOSE);
        if (samples[channel].size() > expected_samples[channel].size()) begin
          debug.error($sformatf(
            "too many samples for channel %0d with banking mode %0d: got %0d, expected at most %0d",
            channel,
            banking_mode,
            samples[channel].size(),
            expected_samples[channel].size()
          ));
        end
        /////////////////////////////
        // check all the samples
        /////////////////////////////
        // The sample counter and hysteresis tracking of the sample discriminator
        // are reset before each trial. Therefore is_high is reset.
        is_high = 0;
        sample_index = 0; // index of sample in received samples buffer
        while ((expected_samples[channel].size() > 0) & (buffer_filled ? (samples[channel].size() > 0) : 1'b1)) begin
          debug.display($sformatf(
            "processing sample %0d from channel %0d: samp = %0x, timer = %0x",
            expected_samples[channel].size(),
            channel,
            expected_samples[channel][$],
            timer[channel]
          ), sim_util_pkg::DEBUG);
          if (disc_util.any_above_high(expected_samples[channel][$], threshold_high[channel])) begin
            debug.display($sformatf(
              "%x contains a sample greater than %x",
              expected_samples[channel][$],
              threshold_high[channel]
            ), sim_util_pkg::DEBUG);
            if (!is_high) begin
              // new sample, should get a timestamp
              if (timestamps[channel].size() > 0) begin
                if (timestamps[channel][$] !== {timer[channel], sample_index}) begin
                  debug.error($sformatf(
                    "mismatched timestamp: got %x, expected %x",
                    timestamps[channel][$],
                    {timer[channel], sample_index}
                  ));
                end
                timestamps[channel].pop_back();
              end else begin
                debug.error($sformatf(
                  "expected a timestamp (with value %x), but no more timestamps left",
                  {timer[channel], sample_index}
                ));
              end
            end
            is_high = 1'b1;
          end else if (disc_util.all_below_low(expected_samples[channel][$], threshold_low[channel])) begin
            is_high = 1'b0;
          end
          if (is_high) begin
            if (expected_samples[channel][$] !== samples[channel][$]) begin
              debug.error($sformatf(
                "mismatched data: got %x, expected %x",
                samples[channel][$],
                expected_samples[channel][$]
              ));
            end
            samples[channel].pop_back();
            sample_index = sample_index + 1'b1;
          end
          expected_samples[channel].pop_back();
          timer[channel] = timer[channel] + 1'b1;
        end
        // check to make sure we didn't miss any data
        if ((timestamps[channel].size() > 0) & (~buffer_filled)) begin
          debug.error($sformatf(
            "too many timestamps leftover for channel %0d with banking mode %0d (got %0d, expected 0)",
            channel,
            banking_mode,
            timestamps[channel].size()
          ));
        end
        // flush out remaining timestamps
        while (timestamps[channel].size() > 0) begin
          debug.display($sformatf(
            "extra timestamp %x",
            timestamps[channel].pop_back()
          ), sim_util_pkg::DEBUG);
        end
        if ((samples[channel].size() > 0) && (~buffer_filled)) begin
          debug.error($sformatf(
            "too many samples leftover for channel %0d with banking mode %0d (got %0d, expected 0)",
            channel,
            banking_mode,
            samples[channel].size()
          ));
        end
        // flush out remaining samples
        while (samples[channel].size() > 0) begin
          debug.display($sformatf(
            "extra sample %x",
            samples[channel].pop_back()
          ), sim_util_pkg::DEBUG);
        end
        // should not be any leftover expected_samples samples, since the while loop
        // won't terminate until expected_samples[channel] is empty.
        // however, if buffer_filled is true, then we might have some leftover
        // flush out remaining samples
        if ((~buffer_filled) & (expected_samples[channel].size() > 0)) begin
          debug.error($sformatf(
            "too many expected samples leftover (%0d) for channel %0d, didn't expect any missing samples",
            expected_samples[channel].size(),
            channel)
          );
        end
        while (expected_samples[channel].size() > 0) begin
          debug.display($sformatf(
            "extra sample %x",
            expected_samples[channel].pop_back()),
            sim_util_pkg::DEBUG
          );
          timer[channel] = timer[channel] + 1'b1;
        end
      end
      for (int channel = 0; channel < CHANNELS; channel++) begin
        debug.display($sformatf(
          "timer[%0d] = %0d (0x%x)",
          channel,
          timer[channel],
          timer[channel]
        ), sim_util_pkg::DEBUG);
      end
    endtask
  endclass

endpackage
