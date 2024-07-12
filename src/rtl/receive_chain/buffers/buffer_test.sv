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

sim_util_pkg::debug debug = new(sim_util_pkg::DEBUG);

localparam int BUFFER_DEPTH = 64;
localparam int READ_LATENCY = 4;

logic adc_reset;
logic adc_clk = 0;
localparam int ADC_CLK_RATE_HZ = 512_000_000;
always #(0.5s/ADC_CLK_RATE_HZ) adc_clk = ~adc_clk;

logic ps_reset;
logic ps_clk = 0;
localparam int PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_data ();
logic adc_capture_hw_start, adc_capture_hw_stop; // DUT input
logic adc_capture_full; // DUT output

// data input
Axis_If #(.DWIDTH(rx_pkg::DATA_WIDTH)) ps_readout_data ();
// configuration inputs
Axis_If #(.DWIDTH(1)) ps_capture_arm ();
Axis_If #(.DWIDTH($clog2($clog2(rx_pkg::CHANNELS+1)))) ps_capture_banking_mode ();
Axis_If #(.DWIDTH(1)) ps_capture_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_readout_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_readout_start ();
// output
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*($clog2(BUFFER_DEPTH)+1))) ps_capture_write_depth();

// utilities for driving configuration inputs and checking DUT response
buffer_tb #(
  .BUFFER_DEPTH(BUFFER_DEPTH)
) tb_i (
  .adc_clk,
  .adc_reset,
  .adc_data,
  .ps_clk,
  .ps_capture_arm,
  .ps_capture_banking_mode,
  .ps_capture_sw_reset,
  .ps_readout_sw_reset,
  .ps_readout_start,
  .ps_capture_write_depth,
  .ps_readout_data
);

buffer #(
  .BUFFER_DEPTH(BUFFER_DEPTH),
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
  .ps_capture_arm,
  .ps_capture_banking_mode,
  .ps_capture_sw_reset,
  .ps_readout_sw_reset,
  .ps_readout_start,
  .ps_capture_write_depth
);

enum {HW_TRIGGER_WITH_ARM, HW_TRIGGER_NO_ARM} trigger_mode;
enum {CAPTURE_NO_RESET, CAPTURE_ARM_RESET, CAPTURE_ACTIVE_RESET, CAPTURE_HOLD_RESET} capture_reset_mode;
enum {READOUT_NO_RESET, READOUT_RESET} readout_reset_mode;

initial begin
  debug.display("### TESTING BUFFER TOPLEVEL WITH FSM ###", sim_util_pkg::DEFAULT);

  // reset
  adc_reset <= 1'b1;
  ps_reset <= 1'b1;

  adc_capture_hw_start <= 1'b0;
  adc_capture_hw_stop <= 1'b0;

  tb_i.init();

  repeat (100) @(posedge ps_clk);
  ps_reset <= 1'b0;
  @(posedge adc_clk);
  adc_reset <= 1'b0;

  trigger_mode = trigger_mode.first;
  capture_reset_mode = capture_reset_mode.first;
  readout_reset_mode = readout_reset_mode.first;

  do begin: readout_rst
    do begin: capture_rst
      do begin: trigger
        for (int save_until_full = 0; save_until_full < 2; save_until_full++) begin
          // sw, hw w/ arm, hw w/out arm
          for (int banking_mode = 0; banking_mode <= $clog2(rx_pkg::CHANNELS); banking_mode++) begin
            debug.display($sformatf("testing for banking_mode = %0d", banking_mode), sim_util_pkg::VERBOSE);
            debug.display($sformatf("trigger_mode = %0p", trigger_mode), sim_util_pkg::VERBOSE);
            debug.display($sformatf("save_until_full = %0d", save_until_full), sim_util_pkg::VERBOSE);
            debug.display($sformatf("capture_reset_mode = %0p", capture_reset_mode), sim_util_pkg::VERBOSE);
            debug.display($sformatf("readout_reset_mode = %0p", readout_reset_mode), sim_util_pkg::VERBOSE);

            @(posedge ps_clk);
            tb_i.set_banking_mode(debug, banking_mode);
            for (int reset_during_hold = 0; reset_during_hold < ((capture_reset_mode == CAPTURE_HOLD_RESET) ? 2 : 1); reset_during_hold++) begin
              for (int reset_during_save = 0; reset_during_save < ((capture_reset_mode == CAPTURE_ACTIVE_RESET) ? 2 : 1); reset_during_save++) begin
                for (int reset_during_arm = 0; reset_during_arm < ((capture_reset_mode == CAPTURE_ARM_RESET) ? 2 : 1); reset_during_arm++) begin
                  if (trigger_mode == HW_TRIGGER_WITH_ARM) begin
                    // arm if we're testing hw trigger_mode with arm
                    @(posedge ps_clk);
                    tb_i.capture_arm(debug, 1'b1);
                    // wait to make sure DUT is armed (since there is a CDC delay)
                    repeat (10) @(posedge ps_clk);
                    if ((capture_reset_mode == CAPTURE_ARM_RESET) && (reset_during_arm == 0)) begin
                      // send reset after arming but before capture actually
                      // starts
                      tb_i.reset_capture(debug);
                      // clear samples sent
                      tb_i.clear_sent_data();
                    end
                  end
                end
                // start capture
                @(posedge adc_clk);
                adc_capture_hw_start <= 1'b1;
                @(posedge adc_clk);
                adc_capture_hw_start <= 1'b0;
                if ((capture_reset_mode == CAPTURE_ACTIVE_RESET) && (reset_during_save == 0)) begin
                  // save some samples first
                  repeat ($urandom_range(40, 60)) @(posedge adc_clk);
                  // send reset while samples are actively being saved
                  @(posedge ps_clk);
                  tb_i.reset_capture(debug);
                  tb_i.clear_sent_data();
                end else begin
                  if (save_until_full && (trigger_mode != HW_TRIGGER_NO_ARM)) begin
                    // for trigger modes in which we actually triggered
                    // a capture, wait until buffer fills up, without
                    // sending a stop signal
                    // don't do this if trigger_mode == HW_TRIGGER_NO_ARM,
                    // because then we would be waiting forever
                    debug.display("waiting until adc_capture_full", sim_util_pkg::DEBUG);
                    do @(posedge adc_clk); while (~adc_capture_full);
                  end else begin
                    // stop capture after a few samples
                    repeat ($urandom_range(40, 60)) @(posedge adc_clk);
                    // hardware stop
                    @(posedge adc_clk);
                    adc_capture_hw_stop <= 1'b1;
                    @(posedge adc_clk);
                    adc_capture_hw_stop <= 1'b0;
                  end
                end
                // wait a few cycles so that write_depth gets sent out
                // before we continue to the next loop
                repeat (20) @(posedge ps_clk);
              end
              if ((capture_reset_mode == CAPTURE_HOLD_RESET) && (reset_during_hold == 0)) begin
                // send reset after capture is complete but before readout
                repeat (10) @(posedge ps_clk);
                tb_i.reset_capture(debug);
                // wait a clock cycle
                @(posedge ps_clk);
                // clear sent data
                tb_i.clear_sent_data();
                // also clear write_depth, since we would have an extra transaction otherwise
                tb_i.clear_write_depth();
              end
            end
            // done saving data
            // wait a few cycles before doing readout
            repeat (20) @(posedge ps_clk);
            // first, check that write_depth only had a single transfer (for
            // trigger_mode != HW_TRIGGER_NO_ARM)
            // if trigger_mode == HW_TRIGGER_NO_ARM, then we don't expect any packets
            tb_i.check_write_depth_num_packets(debug, (trigger_mode == HW_TRIGGER_NO_ARM) ? 0 : 1);
            if (trigger_mode != HW_TRIGGER_NO_ARM) begin
              // if trigger_mode == 2, then we didn't actually save any data, so don't attempt to read out
              if (save_until_full) begin
                // if we sent data until capture_full went high, check that write_depth filled up
                tb_i.check_write_depth_full(debug, 1 << banking_mode);
              end
              for (int reset_during_readout = 0; reset_during_readout < ((readout_reset_mode == READOUT_RESET) ? 2 : 1); reset_during_readout++) begin
                // start readout
                repeat (10) @(posedge ps_clk);
                tb_i.start_readout(debug, 1'b1);
                repeat (BUFFER_DEPTH*rx_pkg::CHANNELS/2) begin
                  do @(posedge ps_clk); while (~ps_readout_data.ok);
                end
                if ((readout_reset_mode == READOUT_RESET) && (reset_during_readout == 0)) begin
                  // send reset in the middle of readout
                  tb_i.reset_readout(debug);
                  // clear received data
                  tb_i.clear_received_data();
                end else begin
                  // finish readout
                  debug.display("waiting for readout to finish", sim_util_pkg::DEBUG);
                  do @(posedge ps_clk); while (~(ps_readout_data.ok & ps_readout_data.last));
                end
              end
              // extra clock cycle to make sure we get the last sample
              @(posedge ps_clk);
              // check data we read out is correct
              tb_i.check_output(debug, 1 << banking_mode);
            end else begin
              repeat (10) @(posedge ps_clk);
              debug.display("attempting starting readout (expecting failure since we didn't save any data)", sim_util_pkg::DEBUG);
              tb_i.start_readout(debug, 1'b0);
            end
            // clear queues
            tb_i.clear_sent_data();
            tb_i.clear_received_data();
            tb_i.clear_write_depth();
          end
        end
        trigger_mode = trigger_mode.next;
      end while (trigger_mode != trigger_mode.first);
      capture_reset_mode = capture_reset_mode.next;
    end while (capture_reset_mode != capture_reset_mode.first);
    readout_reset_mode = readout_reset_mode.next;
  end while (readout_reset_mode != readout_reset_mode.first);
  debug.finish();
end

endmodule
