// timetagging_sample_buffer_test.sv - Reed Foster
// verifies combined timestamps+data sample buffer is working correctly with
// randomly-generated timestamp and data streams

`timescale 1ns/1ps
module timetagging_sample_buffer_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT);

localparam int BUFFER_READ_LATENCY = 4;

logic adc_reset;
logic adc_clk = 0;
localparam int ADC_CLK_RATE_HZ = 512_000_000;
always #(0.5s/ADC_CLK_RATE_HZ) adc_clk = ~adc_clk;

logic ps_reset;
logic ps_clk = 0;
localparam int PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

// data in
Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_samples_in ();
Realtime_Parallel_If #(.DWIDTH(buffer_pkg::TSTAMP_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_timestamps_in ();

// realtime
logic adc_digital_trigger;
logic adc_discriminator_reset;

// data out
Axis_If #(.DWIDTH(rx_pkg::AXI_MM_WIDTH)) ps_readout_data ();
// status
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*($clog2(buffer_pkg::SAMPLE_BUFFER_DEPTH)+1))) ps_samples_write_depth ();
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*($clog2(buffer_pkg::TSTAMP_BUFFER_DEPTH)+1))) ps_timestamps_write_depth ();
// configuration
Axis_If #(.DWIDTH(3)) ps_capture_arm_start_stop ();
Axis_If #(.DWIDTH(buffer_pkg::BANKING_MODE_WIDTH)) ps_capture_banking_mode ();
Axis_If #(.DWIDTH(1)) ps_capture_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_readout_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_readout_start ();

timetagging_sample_buffer #(
  .BUFFER_READ_LATENCY(BUFFER_READ_LATENCY)
) dut_i (
  .adc_clk,
  .adc_reset,
  .adc_samples_in,
  .adc_timestamps_in,
  .adc_digital_trigger,
  .adc_discriminator_reset,
  .ps_clk,
  .ps_reset,
  .ps_readout_data,
  .ps_samples_write_depth,
  .ps_timestamps_write_depth,
  .ps_capture_arm_start_stop,
  .ps_capture_banking_mode,
  .ps_capture_sw_reset,
  .ps_readout_sw_reset,
  .ps_readout_start
);

timetagging_sample_buffer_tb tb_i (
  .adc_clk,
  .adc_reset,
  .adc_samples_in,
  .adc_timestamps_in,
  .adc_digital_trigger,
  .adc_discriminator_reset,
  .ps_clk,
  .ps_reset,
  .ps_readout_data,
  .ps_samples_write_depth,
  .ps_timestamps_write_depth,
  .ps_capture_arm_start_stop,
  .ps_capture_banking_mode,
  .ps_capture_sw_reset,
  .ps_readout_sw_reset,
  .ps_readout_start
);

enum {CAPTURE_NO_RESET, CAPTURE_RESET} capture_reset;
//enum {READOUT_NO_RESET, READOUT_TSTAMP_RESET, READOUT_SAMPLE_RESET} readout_reset;
//enum {READOUT_TSTAMP_RESET, READOUT_SAMPLE_RESET, READOUT_NO_RESET} readout_reset;
enum {READOUT_SAMPLE_RESET, READOUT_TSTAMP_RESET, READOUT_NO_RESET} readout_reset;
enum {SW_START, HW_START} start_mode;
enum {MANUAL_STOP, FULL} stop_mode;
enum {ONLY_TIMESTAMPS, ONLY_SAMPLES, BOTH} input_mode;

int readout_q_size;
always_comb begin
  readout_q_size = tb_i.ps_readout_data_rx_i.data_q.size();
end

int timeout;
int readout_reset_delay;

initial begin
  debug.display("### TESTING SEGMENTED BUFFER TOPLEVEL ###", sim_util_pkg::DEFAULT);

  capture_reset = capture_reset.first;
  readout_reset = readout_reset.first;
  start_mode = start_mode.first;
  stop_mode = stop_mode.first;
  input_mode = input_mode.first;

  do begin: readout_reset_loop
    do begin: capture_reset_loop
      do begin: start_mode_loop
        do begin: stop_mode_loop
          do begin: input_mode_loop
            for (int banking_mode = 0; banking_mode < $clog2(rx_pkg::CHANNELS + 1); banking_mode++) begin
              debug.display("testing with configuration:", sim_util_pkg::VERBOSE);
              debug.display($sformatf("banking_mode = %0d", banking_mode), sim_util_pkg::VERBOSE);
              debug.display($sformatf("input_mode = %0p", input_mode), sim_util_pkg::VERBOSE);
              debug.display($sformatf("stop_mode = %0p", stop_mode), sim_util_pkg::VERBOSE);
              debug.display($sformatf("start_mode = %0p", start_mode), sim_util_pkg::VERBOSE);
              debug.display($sformatf("capture_reset = %0p", capture_reset), sim_util_pkg::VERBOSE);
              debug.display($sformatf("readout_reset = %0p", readout_reset), sim_util_pkg::VERBOSE);
              // mid-test reset
              // wait a few cycles to make sure any transactions completed
              @(posedge ps_clk);
              ps_reset <= 1'b1;
              @(posedge adc_clk);
              adc_reset <= 1'b1;

              adc_digital_trigger <= 1'b0;

              tb_i.init ();
              // configure stimulus
              case (input_mode)
                ONLY_TIMESTAMPS: begin
                  tb_i.adc_samples_enabled(1'b0);
                  tb_i.adc_timestamps_enabled(1'b1);
                end
                ONLY_SAMPLES: begin
                  tb_i.adc_samples_enabled(1'b1);
                  tb_i.adc_timestamps_enabled(1'b0);
                end
                BOTH: begin
                  tb_i.adc_samples_enabled(1'b1);
                  tb_i.adc_timestamps_enabled(1'b1);
                end
              endcase
              repeat (10) @(posedge ps_clk);
              ps_reset <= 1'b0;
              @(posedge adc_clk);
              adc_reset <= 1'b0;
              // wait a few cycles to come out of reset
              repeat (5) @(posedge ps_clk);
              // set banking mode
              tb_i.set_banking_mode(debug, banking_mode);
              // send data
              // first arm or start
              for (int capture_iter = 0; capture_iter < ((capture_reset == CAPTURE_RESET) ? 2 : 1); capture_iter++) begin
                case (start_mode)
                  SW_START: begin
                    // sending both arm and start will cause a software start
                    tb_i.capture_arm_start_stop(debug, 1'b1, 1'b1, 1'b0);
                  end
                  HW_START: begin
                    // sending just arm but no start will arm the buffer and wait for
                    // a hardware start
                    tb_i.capture_arm_start_stop(debug, 1'b1, 1'b0, 1'b0);
                    // make sure we wait a bit for the arm signal to get CDC'd
                    repeat (20) @(posedge ps_clk);
                    // send hw start from trigger signal
                    repeat ($urandom_range(10, 20)) @(posedge adc_clk);
                    adc_digital_trigger <= 1'b1;
                    @(posedge adc_clk);
                    adc_digital_trigger <= 1'b0;
                  end
                endcase
                repeat (10) @(posedge ps_clk);
                // receive data
                case (stop_mode)
                  MANUAL_STOP: begin
                    // assume TSTAMP_BUFFER_DEPTH < SAMPLE_BUFFER_DEPTH
                    repeat ($urandom_range(1, buffer_pkg::TSTAMP_BUFFER_DEPTH/2)) begin
                      do begin
                        @(posedge adc_clk);
                      end while ((adc_samples_in.valid === '0) & (adc_timestamps_in.valid === '0));
                    end
                    // send stop
                    @(posedge ps_clk);
                    tb_i.capture_arm_start_stop(debug, 1'b0, 1'b0, 1'b1);
                  end
                  FULL: begin
                    timeout = 0;
                    // extra wait since it will take some time for the start
                    // signal to get properly CDC'd
                    while ((timeout < 10 + 2*(rx_pkg::CHANNELS>>banking_mode)*(buffer_pkg::SAMPLE_BUFFER_DEPTH+buffer_pkg::TSTAMP_BUFFER_DEPTH)) & (dut_i.adc_capture_full === 2'b00)) begin
                      do begin
                        @(posedge adc_clk);
                      end while ((adc_samples_in.valid === '0) & (adc_timestamps_in.valid === '0));
                      timeout++;
                    end
                    if (dut_i.adc_capture_full == 2'b00) begin
                      debug.error("did not fill up either buffer with samples");
                    end
                  end
                endcase
                // reset the capture
                if ((capture_reset == CAPTURE_RESET) && (capture_iter == 0)) begin
                  // send reset signal
                  tb_i.reset_capture(debug);
                  repeat (40) @(posedge ps_clk);
                  tb_i.clear_sent_data();
                  tb_i.clear_write_depth();
                end
              end
              // do readout
              repeat (20) @(posedge ps_clk);
              for (int readout_iter = 0; readout_iter < ((readout_reset != READOUT_NO_RESET) ? 2 : 1); readout_iter++) begin
                tb_i.start_readout(debug);
                // only do part of readout
                if (readout_reset != READOUT_NO_RESET) begin
                  if (readout_reset == READOUT_TSTAMP_RESET) begin
                    readout_reset_delay = (buffer_pkg::TSTAMP_BUFFER_DEPTH*buffer_pkg::TSTAMP_WIDTH)/(rx_pkg::AXI_MM_WIDTH*2);
                  end else begin
                    readout_reset_delay = (buffer_pkg::TSTAMP_BUFFER_DEPTH*buffer_pkg::TSTAMP_WIDTH
                                            + buffer_pkg::SAMPLE_BUFFER_DEPTH*rx_pkg::DATA_WIDTH/2)/rx_pkg::AXI_MM_WIDTH;
                  end
                  repeat (readout_reset_delay) begin
                    do @(posedge ps_clk); while (~ps_readout_data.ok);
                  end
                  if (readout_iter == 0) begin
                    tb_i.reset_readout(debug);
                    // wait to make sure we don't accidentally save
                    // the tailend of the cancelled readout
                    do @(posedge ps_clk); while (~((dut_i.timestamp_buffer_i.ps_readout_valid_pipe === 0) && (dut_i.sample_buffer_i.ps_readout_valid_pipe === 0)));
                    repeat (10) @(posedge ps_clk)
                    tb_i.clear_received_data();
                  end
                end
                if ((readout_reset == READOUT_NO_RESET) | (readout_iter != 0)) begin
                  // wait for last signal only if we haven't just reset the
                  // readout FSM
                  do @(posedge ps_clk); while (~(ps_readout_data.ok & ps_readout_data.last));
                end else begin
                  // wait a few cycles before retrying readout
                  repeat (20) @(posedge ps_clk);
                end
              end
              // wait a few cycles
              repeat (5) @(posedge ps_clk);

              // check output
              tb_i.check_write_depth_num_packets(debug);
              tb_i.check_output(debug, 1 << banking_mode);

              // clear queues
              tb_i.clear_write_depth();
              tb_i.clear_received_data();
              tb_i.clear_sent_data();
            end
            //
            input_mode = input_mode.next;
          end while (input_mode != input_mode.first);
          stop_mode = stop_mode.next;
        end while (stop_mode != stop_mode.first);
        start_mode = start_mode.next;
      end while (start_mode != start_mode.first);
      capture_reset = capture_reset.next;
    end while (capture_reset != capture_reset.first);
    readout_reset = readout_reset.next;
  end while (readout_reset != readout_reset.first);

  debug.finish();
end

endmodule
