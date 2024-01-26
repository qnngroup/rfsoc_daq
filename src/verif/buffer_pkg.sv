// buffer_pkg.sv - Reed Foster
// package with class for verification of buffer_core and buffer

package buffer_pkg;
  class util #(
    parameter int CHANNELS = 8,
    parameter int BUFFER_DEPTH = 64,
    parameter int DATA_WIDTH = 16
  );

    task automatic check_write_depth (
      inout sim_util_pkg::debug debug,
      input int expected_depths [CHANNELS],
      input logic [CHANNELS-1:0][$clog2(BUFFER_DEPTH):0] write_depths,
      input int active_channels
    );
      
      int total_write_depth;
    
      // make sure the write depths match up with the number of samples sent
      for (int channel = 0; channel < active_channels; channel++) begin
        total_write_depth = 0;
        for (int bank = channel; bank < CHANNELS; bank += active_channels) begin
          if (write_depths[bank][$clog2(BUFFER_DEPTH)]) begin
            // if MSB of write_depths is set, then bank is full
            // this behavior is identical to just adding write_depth[bank] when
            // BUFFER_DEPTH is a power of 2; however this is not always the case
            total_write_depth += BUFFER_DEPTH;
          end else begin
            total_write_depth += write_depths[bank];
          end
        end
        debug.display($sformatf(
          "channel %0d: sent %0d samples",
          channel,
          expected_depths[channel]),
          sim_util_pkg::DEBUG
        );
        if (expected_depths[channel] !== total_write_depth) begin
          debug.error($sformatf(
            "channel %0d: sent %0d samples, but %0d were written",
            channel,
            expected_depths[channel],
            total_write_depth)
          );
        end
      end
    
    endtask
    
    task automatic check_results (
      inout sim_util_pkg::debug debug,
      inout logic [DATA_WIDTH-1:0] samples_sent [CHANNELS][$],
      inout logic [DATA_WIDTH-1:0] samples_received [$],
      input int last_received,
      input int active_channels
    );
     
      // keep track of what sample we're on across multiple banks
      int sample_index;
    
      // make sure we got tlast at the right time
      if (last_received !== CHANNELS*BUFFER_DEPTH) begin
        debug.error($sformatf(
          "expected tlast event on cycle %0d, got it on %0d",
          CHANNELS*BUFFER_DEPTH,
          last_received)
        );
      end
    
      // make sure samples_received is the right size
      if (samples_received.size() !== CHANNELS*BUFFER_DEPTH) begin
        debug.error($sformatf(
          "expected to receive %0d samples, but got %0d",
          CHANNELS*BUFFER_DEPTH,
          samples_received.size())
        );
      end
    
      // check that the right data was received
      for (int bank = 0; bank < CHANNELS; bank++) begin
        for (int sample = 0; sample < BUFFER_DEPTH; sample++) begin
          // get the index of the sample within the currently-selected channel
          // banks are assigned to channels accordingly:
          // active_channels = 1: [0, 0, 0, 0, 0, 0, 0, 0, ... ]
          // active_channels = 2: [0, 1, 0, 1, 0, 1, 0, 1, ... ]
          // active_channels = 4: [0, 1, 2, 3, 0, 1, 2, 3, ... ]
          // active_channels = 8: [0, 1, 2, 3, 4, 5, 6, 7, ... ]
          // (bank % active_channels) gives the channel assigned to the current bank
          // (bank / active_channels) gives the bank offset for banks associated
          // with the channel assigned to the current bank
          //  i.e. if we're on bank 5:
          //    active_channels = 8, it would be the 0th bank for channel 5
          //    active_channels = 4, it would be the 1st bank for channel 1
          //    active_channels = 2, it would be the 2nd bank for channel 1
          //    active_channels = 1, it would be the 5th bank for channel 0
          sample_index = (bank / active_channels) * BUFFER_DEPTH + sample;
          if (sample_index < samples_sent[bank % active_channels].size()) begin
            if (samples_sent[bank % active_channels][$-sample_index] !== samples_received[$]) begin
              debug.error($sformatf(
                "channel %0d, bank %0d: sample mismatch, expected %x got %x",
                bank % active_channels,
                bank,
                samples_sent[bank % active_channels][$-sample_index],
                samples_received[$])
              );
            end
          end
          samples_received.pop_back();
        end
      end
    
      // clean up extra samples
      for (int channel = 0; channel < CHANNELS; channel++) begin
        while (samples_sent[channel].size() > 0) samples_sent[channel].pop_back();
      end
      while (samples_received.size() > 0) samples_received.pop_back(); 
    
    endtask

  endclass

endpackage
