// buffer_pkg.sv - Reed Foster
// package with class for verification of buffer_core and buffer

package buffer_pkg;
  class util #(
    parameter int CHANNELS = 8,
    parameter int BUFFER_DEPTH = 64,
    parameter int DATA_WIDTH = 16
  );

    typedef virtual Axis_If #(.DWIDTH(3))     arm_start_stop_if;
    typedef virtual Axis_If #(.DWIDTH(1))     reset_if;

    arm_start_stop_if v_arm_start_stop;
    reset_if v_capture_reset;
    reset_if v_readout_reset;

    function new (
      input arm_start_stop_if arm_start_stop,
      input reset_if capture_reset,
      input reset_if readout_reset
    );
      v_arm_start_stop = arm_start_stop;
      v_capture_reset = capture_reset;
      v_readout_reset = readout_reset;
    endfunction

    /////////////////////////////////////////////////////////////////
    // tasks for interacting with the DUT/test
    /////////////////////////////////////////////////////////////////
    //
    // clear samples_sent queues (used at the end of each trial, or when
    // a capture is manually restarted)
    task automatic clear_samples_sent (
      inout logic [DATA_WIDTH-1:0] samples_sent [CHANNELS][$]
    );
      for (int channel = 0; channel < CHANNELS; channel++) begin
        while (samples_sent[channel].size() > 0) samples_sent[channel].pop_back();
      end
    endtask

    task automatic capture_arm_start_stop(
      inout sim_util_pkg::debug debug,
      ref ps_clk,
      input logic [2:0] arm_start_stop
    );
      logic valid_arm_start_stop = 0;
      logic success;
      case (arm_start_stop)
        1: begin
          debug.display("sending stop to capture", sim_util_pkg::DEBUG);
          valid_arm_start_stop = 1;
        end
        2: begin
          debug.display("sending sw_start to capture", sim_util_pkg::DEBUG);
          valid_arm_start_stop = 1;
        end
        4: begin
          debug.display("sending arm to capture", sim_util_pkg::DEBUG);
          valid_arm_start_stop = 1;
        end
        default: debug.error($sformatf("invalid arm_start_stop value %0d", arm_start_stop));
      endcase
      if (valid_arm_start_stop) begin
        v_arm_start_stop.send_sample_with_timeout(ps_clk, arm_start_stop, 10, success);
        if (~success) begin
          debug.error("failed to start capture");
        end
      end
    endtask
    
    task automatic reset_capture(
      inout sim_util_pkg::debug debug,
      ref ps_clk,
      inout logic [DATA_WIDTH-1:0] samples_sent [CHANNELS][$]
    );
      logic success;
      debug.display("resetting capture", sim_util_pkg::DEBUG);
      v_capture_reset.send_sample_with_timeout(ps_clk, 1'b1, 10, success);
      if (~success) begin
        debug.error("failed to reset capture");
      end
      // delete all saved samples
      this.clear_samples_sent(samples_sent);
    endtask

    task automatic reset_readout(
      inout sim_util_pkg::debug debug,
      ref ps_clk,
      inout logic [DATA_WIDTH-1:0] samples_received [$]
    );
      logic success;
      debug.display("resetting readout", sim_util_pkg::DEBUG);
      v_readout_reset.send_sample_with_timeout(ps_clk, 1'b1, 10, success);
      if (~success) begin
        debug.error("failed to reset readout");
      end
      // delete all saved samples
      while (samples_received.size() > 0) samples_received.pop_back();
    endtask

    /////////////////////////////////////////////////////////////////
    // tasks for verifying DUT output
    /////////////////////////////////////////////////////////////////
    // make sure that the reported write_depth (i.e. how many samples the DUT
    // stored in each buffer bank) is maximal for at least one of the channels
    task automatic check_write_depth_full (
      inout sim_util_pkg::debug debug,
      input [CHANNELS-1:0][$clog2(BUFFER_DEPTH):0] write_depth [$],
      input int active_channels,
      output bit success
    );
      success = 0;
      for (int channel = 0; channel < active_channels; channel++) begin
        if (write_depth[$][CHANNELS-1-channel][$clog2(BUFFER_DEPTH)]) begin
          success = 1;
        end
      end
      if (~success) begin
        debug.error($sformatf(
          "write_depth = %x does not indicate that any buffer filled up for active_channels = %0d",
          write_depth[$],
          active_channels)
        );
      end
    endtask

    // make sure that the correct number of transfers occurred on the
    // write_depth interface
    task automatic check_write_depth_num_packets (
      inout sim_util_pkg::debug debug,
      input [CHANNELS-1:0][$clog2(BUFFER_DEPTH):0] write_depth [$],
      input int expected_packets,
      output bit success
    );
      // check write_depth queue is empty
      if (write_depth.size() !== expected_packets) begin
        debug.error($sformatf(
          "write_depth.size() = %0d, expected %0d transactions",
          write_depth.size(),
          expected_packets)
        );
        success = 0;
      end else begin
        success = 1;
      end
    endtask

    // check that the correct number of samples match between the output and
    // input
    task automatic check_output(
      inout sim_util_pkg::debug debug,
      inout logic [DATA_WIDTH-1:0] samples_sent [CHANNELS][$],
      inout logic [DATA_WIDTH-1:0] samples_received [$],
      inout [CHANNELS-1:0][$clog2(BUFFER_DEPTH):0] write_depth [$],
      input int active_channels
    );
      logic [CHANNELS-1:0][31:0] total_write_depth = '0;
      int sample_index;
      // check_output(samples_sent, samples_received, write_depth, 1 << banking_mode);
      // check that the correct number of samples match based on the write depth
      for (int channel = 0; channel < active_channels; channel++) begin
        for (int bank = channel; bank < CHANNELS; bank += active_channels) begin
          if (write_depth[$][bank][$clog2(BUFFER_DEPTH)]) begin
            total_write_depth[channel] += BUFFER_DEPTH;
          end else begin
            total_write_depth[channel] += write_depth[$][bank];
          end
        end
        // remove extra samples until we get something that matches the DMA data
        // since we aren't sure exactly when the DUT started saving data
        while ((samples_sent[channel].size() > 0) && (samples_sent[channel][$] !== samples_received[$-channel*BUFFER_DEPTH])) begin
          samples_sent[channel].pop_back();
        end
        if (total_write_depth[channel] > samples_sent[channel].size()) begin
          debug.error($sformatf(
            "channel %0d: DUT reported write depth = %0d, but only %0d samples were sent to DUT",
            channel,
            total_write_depth[channel],
            samples_sent[channel].size())
          );
        end
      end
      for (int bank = 0; bank < CHANNELS; bank++) begin
        for (int sample = 0; sample < BUFFER_DEPTH; sample++) begin
          sample_index = (bank / active_channels) * BUFFER_DEPTH + sample;
          if (sample_index < total_write_depth[bank % active_channels]) begin
            if (samples_sent[bank % active_channels][$] !== samples_received[$]) begin
              debug.error($sformatf(
                "channel %0d, bank %0d: sample mismatch: expected %x got %x",
                bank % active_channels,
                bank,
                samples_sent[bank % active_channels][$],
                samples_received[$])
              );
            end
            samples_sent[bank % active_channels].pop_back();
          end
          samples_received.pop_back();
        end
      end
      // clear queues
      this.clear_samples_sent(samples_sent);
      while (samples_received.size() > 0) samples_received.pop_back();
      while (write_depth.size() > 0) write_depth.pop_back();
    endtask
    
  endclass

endpackage
