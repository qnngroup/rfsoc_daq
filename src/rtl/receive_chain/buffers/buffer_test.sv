// buffer_test.sv - Reed Foster
// Test for sample buffer
//
// Things to check:
//  - check capture_write_depth is correct at a variety of times between starting capture and performing DMA
//  - test sw_resets
//    - make sure capture_sw_reset can be triggered at any time
//    - make sure that dma_reset can only be triggered during an active DMA transfer
//  - test hw_start/hw_stop work correctly
//    - when asserted at the expected time, start/stop work as expected
//    - when asserted at the incorrect time, start/stop have no effect
//  - test that we get a adc_capture_full signal when the buffers are full
//  - test that write_depth is outputted only once per capture
//    - also check that the correct number of samples were saved
//  - test that all the data we sent was saved and read out
//    - data sent between capture start and stop (from full or sw_stop)

`timescale 1ns/1ps
module buffer_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT);

localparam int CHANNELS = 4;
localparam int BUFFER_DEPTH = 64;
localparam int DATA_WIDTH = 16;
localparam int READ_LATENCY = 4;

logic adc_reset;
logic adc_clk = 0;
localparam ADC_CLK_RATE_HZ = 512_000_000;
always #(0.5s/ADC_CLK_RATE_HZ) adc_clk = ~adc_clk;

logic ps_reset;
logic ps_clk = 0;
localparam PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

Realtime_Parallel_If #(.DWIDTH(DATA_WIDTH), .CHANNELS(CHANNELS)) adc_data ();
logic adc_capture_hw_start, adc_capture_hw_stop; // DUT input
logic adc_capture_full; // DUT output

Axis_If #(.DWIDTH(DATA_WIDTH)) ps_readout_data ();
Axis_If #(.DWIDTH(3)) ps_capture_arm_start_stop ();
Axis_If #(.DWIDTH($clog2($clog2(CHANNELS+1)))) ps_capture_banking_mode ();
Axis_If #(.DWIDTH(1)) ps_capture_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_readout_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_readout_start ();
Axis_If #(.DWIDTH(CHANNELS*($clog2(BUFFER_DEPTH)+1))) ps_capture_write_depth();

buffer_pkg::util #(
  .CHANNELS(CHANNELS),
  .BUFFER_DEPTH(BUFFER_DEPTH),
  .DATA_WIDTH(DATA_WIDTH)
) buffer_util = new(
  ps_capture_arm_start_stop,
  ps_capture_sw_reset,
  ps_readout_sw_reset
);

buffer #(
  .CHANNELS(CHANNELS),
  .BUFFER_DEPTH(BUFFER_DEPTH),
  .DATA_WIDTH(DATA_WIDTH),
  .READ_LATENCY(READ_LATENCY)
) dut_i (
  .adc_clk,
  .adc_reset,
  .adc_data,
  .adc_capture_hw_start,
  .adc_capture_hw_stop,
  .adc_capture_full,
  .ps_clk,
  .ps_reset,
  .ps_readout_data,
  .ps_capture_arm_start_stop,
  .ps_capture_banking_mode,
  .ps_capture_sw_reset,
  .ps_readout_sw_reset,
  .ps_readout_start,
  .ps_capture_write_depth
);

// randomly accept write_depth data
logic [CHANNELS-1:0][$clog2(BUFFER_DEPTH):0] write_depth [$];
always @(posedge ps_clk) begin
  if (ps_reset) begin
    ps_capture_write_depth.ready <= 1'b0;
  end else begin
    ps_capture_write_depth.ready <= $urandom_range(0, 1);
    if (ps_capture_write_depth.ok) begin
      write_depth.push_front(ps_capture_write_depth.data);
    end
  end
end

// randomly accept DMA data
logic [DATA_WIDTH-1:0] samples_received [$];
int dma_last_received [$];
always @(posedge ps_clk) begin
  if (ps_reset) begin
    ps_readout_data.ready <= 1'b0;
  end else begin
    ps_readout_data.ready <= $urandom_range(0, 1);
    if (ps_readout_data.ok) begin
      samples_received.push_front(ps_readout_data.data);
      if (ps_readout_data.last) begin
        dma_last_received.push_front(samples_received.size());
      end
    end
  end
end

// always save samples that may have been sent
// we'll throw away samples in samples_sent until the first sample matches
// what was received
logic [DATA_WIDTH-1:0] samples_sent [CHANNELS][$];
always @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_data.valid <= '0;
  end else begin
    adc_data.valid <= $urandom_range(0, {CHANNELS{1'b1}});
    for (int channel = 0; channel < CHANNELS; channel++) begin
      if (adc_data.valid[channel]) begin
        samples_sent[channel].push_front(adc_data.data[channel]);
        adc_data.data[channel] <= $urandom_range(0, {DATA_WIDTH{1'b1}});
      end
    end
  end
end

logic success;

initial begin
  debug.display("### TESTING BUFFER TOPLEVEL WITH FSM ###", sim_util_pkg::DEFAULT);

  // reset
  adc_reset <= 1'b1;
  ps_reset <= 1'b1;

  adc_capture_hw_start <= 1'b0;
  adc_capture_hw_stop <= 1'b0;

  ps_capture_arm_start_stop.valid <= 1'b0;
  ps_capture_banking_mode.valid <= 1'b0;
  ps_capture_sw_reset.valid <= 1'b0;
  ps_readout_sw_reset.valid <= 1'b0;
  ps_readout_start.valid <= 1'b0;

  // unused; don't really need to assign these, but this way there's no
  // X values in simulation
  ps_capture_arm_start_stop.last <= 1'b0;
  ps_capture_banking_mode.last <= 1'b0;
  ps_capture_sw_reset.last <= 1'b0;
  ps_readout_sw_reset.last <= 1'b0;
  ps_readout_start.last <= 1'b0;

  repeat (100) @(posedge ps_clk);
  ps_reset <= 1'b0;
  @(posedge adc_clk);
  adc_reset <= 1'b0;

  for (int readout_reset_mode = 0; readout_reset_mode < 2; readout_reset_mode++) begin
    for (int capture_reset_mode = 0; capture_reset_mode < 4; capture_reset_mode++) begin
      for (int save_until_full = 0; save_until_full < 2; save_until_full++) begin
        for (int stop_mode = 0; stop_mode < 2; stop_mode++) begin
          for (int trigger_mode = 0; trigger_mode < 3; trigger_mode++) begin
            // sw, hw w/ arm, hw w/out arm
            for (int banking_mode = 0; banking_mode <= $clog2(CHANNELS); banking_mode++) begin
              debug.display($sformatf(
                "testing for banking_mode = %0d",
                banking_mode),
                sim_util_pkg::VERBOSE
              );
              case (trigger_mode)
                0: debug.display("testing sw trigger", sim_util_pkg::VERBOSE);
                1: debug.display("testing hw trigger with arm", sim_util_pkg::VERBOSE);
                2: debug.display("testing hw trigger without arm", sim_util_pkg::VERBOSE);
              endcase
              case (stop_mode)
                0: debug.display("testing sw stop", sim_util_pkg::VERBOSE);
                1: debug.display("testing hw stop", sim_util_pkg::VERBOSE);
              endcase
              case (capture_reset_mode)
                0: debug.display("testing without capture reset", sim_util_pkg::VERBOSE);
                1: debug.display("testing with capture reset after arming", sim_util_pkg::VERBOSE);
                2: debug.display("testing with capture reset during sample saving", sim_util_pkg::VERBOSE);
                3: debug.display("testing with capture reset during sample hold", sim_util_pkg::VERBOSE);
              endcase
              case (readout_reset_mode)
                0: debug.display("testing without readout reset", sim_util_pkg::VERBOSE);
                1: debug.display("testing with readout reset", sim_util_pkg::VERBOSE);
              endcase
              @(posedge ps_clk);
              debug.display($sformatf("writing banking_mode = %0d", banking_mode), sim_util_pkg::DEBUG);
              ps_capture_banking_mode.send_sample_with_timeout(ps_clk, banking_mode, 10, success);
              if (~success) begin
                debug.error("failed to write banking_mode");
              end
              for (int reset_during_hold = 0; reset_during_hold < ((capture_reset_mode == 3) ? 2 : 1); reset_during_hold++) begin
                for (int reset_during_save = 0; reset_during_save < ((capture_reset_mode == 2) ? 2 : 1); reset_during_save++) begin
                  for (int reset_during_arm = 0; reset_during_arm < ((capture_reset_mode == 1) ? 2 : 1); reset_during_arm++) begin
                    if (trigger_mode == 1) begin
                      // arm if we're testing hw trigger_mode with arm
                      @(posedge ps_clk);
                      buffer_util.capture_arm_start_stop(debug, ps_clk, 3'b100);
                      // wait to make sure DUT is armed (since there is a CDC delay)
                      repeat (10) @(posedge ps_clk);
                      if ((capture_reset_mode == 1) && (reset_during_arm == 0)) begin
                        buffer_util.reset_capture(debug, ps_clk, samples_sent);
                      end
                    end
                  end
                  // start capture
                  if (trigger_mode == 0) begin
                    // software trigger_mode
                    repeat (10) @(posedge ps_clk);
                    buffer_util.capture_arm_start_stop(debug, ps_clk, 3'b010);
                  end else begin
                    // hardware trigger_mode
                    @(posedge adc_clk);
                    adc_capture_hw_start <= 1'b1;
                    @(posedge adc_clk);
                    adc_capture_hw_start <= 1'b0;
                  end
                  if ((capture_reset_mode == 2) && (reset_during_save == 0)) begin
                    // save some samples first
                    repeat ($urandom_range(40, 60)) @(posedge adc_clk);
                    // send reset
                    @(posedge ps_clk);
                    buffer_util.reset_capture(debug, ps_clk, samples_sent);
                  end else begin
                    if (save_until_full && (trigger_mode != 2)) begin
                      // don't ever send stop signal, just wait until buffers fill up
                      // don't do this if trigger_mode == 2, because then we would be waiting forever
                      debug.display("waiting until adc_capture_full", sim_util_pkg::DEBUG);
                      do @(posedge adc_clk); while (~adc_capture_full);
                    end else begin
                      // stop capture after a few samples
                      repeat ($urandom_range(40, 60)) @(posedge adc_clk);
                      if (stop_mode == 0) begin
                        // software stop
                        @(posedge ps_clk);
                        buffer_util.capture_arm_start_stop(debug, ps_clk, 3'b001);
                      end else begin
                        // hardware stop
                        @(posedge adc_clk);
                        adc_capture_hw_stop <= 1'b1;
                        @(posedge adc_clk);
                        adc_capture_hw_stop <= 1'b0;
                      end
                    end
                  end
                  // wait a few cycles so that write_depth gets sent out
                  // before we continue to the next loop
                  repeat (10) @(posedge ps_clk);
                end
                if ((capture_reset_mode == 3) && (reset_during_hold == 0)) begin
                  // send reset
                  repeat (10) @(posedge ps_clk);
                  buffer_util.reset_capture(debug, ps_clk, samples_sent);
                  // also clear write_depth, since we would have two transactions
                  while (write_depth.size() > 0) write_depth.pop_back();
                end
              end
              // done saving data
              // wait a few cycles before doing readout
              repeat (20) @(posedge ps_clk);
              // first, check that write_depth only had a single transfer
              debug.display("checking number of write_depth transfers", sim_util_pkg::DEBUG);
              buffer_util.check_write_depth_num_packets(debug, write_depth, (trigger_mode == 2) ? 0 : 1, success);
              if (trigger_mode != 2) begin
                // if trigger_mode == 2, then we didn't actually save any data, so don't attempt to read out
                if (success && save_until_full) begin
                  // if we sent data until capture_full went high, check that write_depth filled up
                  debug.display("checking write_depth indicates at least one of the channels filled up", sim_util_pkg::DEBUG);
                  buffer_util.check_write_depth_full(debug, write_depth, 1 << banking_mode, success);
                end
                for (int reset_during_readout = 0; reset_during_readout < ((readout_reset_mode == 1) ? 2 : 1); reset_during_readout++) begin
                  // start readout
                  repeat (10) @(posedge ps_clk);
                  debug.display("starting readout", sim_util_pkg::DEBUG);
                  ps_readout_start.send_sample_with_timeout(ps_clk, 1'b1, 10, success);
                  if (~success) begin
                    debug.error("failed to start readout");
                  end
                  repeat (BUFFER_DEPTH*CHANNELS/2) begin
                    do @(posedge ps_clk); while (~ps_readout_data.ok);
                  end
                  if ((readout_reset_mode == 1) && (reset_during_readout == 0)) begin
                    // send reset
                    buffer_util.reset_readout(debug, ps_clk, samples_received);
                  end else begin
                    // finish readout
                    debug.display("waiting for readout to finish", sim_util_pkg::DEBUG);
                    do @(posedge ps_clk); while (~(ps_readout_data.ok & ps_readout_data.last));
                  end
                end
                // check data we read out is correct
                debug.display("checking output data", sim_util_pkg::DEBUG);
                buffer_util.check_output(debug, samples_sent, samples_received, write_depth, 1 << banking_mode);
              end else begin
                repeat (10) @(posedge ps_clk);
                debug.display("attempting starting readout (expecting failure since we didn't save any data)", sim_util_pkg::DEBUG);
                ps_readout_start.send_sample_with_timeout(ps_clk, 1'b1, 10, success);
                if (success) begin
                  debug.error("started readout, but shouldn't have been able to");
                end
                // clear queues
                buffer_util.clear_samples_sent(samples_sent);
                while (samples_received.size() > 0) samples_received.pop_back();
                while (write_depth.size() > 0) write_depth.pop_back();
              end
            end
          end
        end
      end
    end
  end
  debug.finish();
end

endmodule
