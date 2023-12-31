// sparse_sample_buffer_pkg.sv - Reed Foster
// package with a class for parsing the sparse sample buffer output


package sparse_sample_buffer_pkg;

  class util #(
    parameter int AXI_MM_WIDTH = 128,
    parameter int TIMESTAMP_WIDTH = 64,
    parameter int DATA_WIDTH = 256,
    parameter int CHANNELS = 8
  );

    task automatic parse_buffer_output (
      inout logic [AXI_MM_WIDTH-1:0] buffer_output [$],
      output logic [TIMESTAMP_WIDTH-1:0] timestamps [CHANNELS][$],
      output logic [DATA_WIDTH-1:0] samples [CHANNELS][$]
    );
      logic [AXI_MM_WIDTH-1:0] dma_word;
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
  endclass

endpackage
