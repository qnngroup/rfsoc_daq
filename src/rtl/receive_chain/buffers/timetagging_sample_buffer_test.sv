
`timescale 1ns/1ps
module timetagging_sample_buffer_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT);

localparam int BUFFER_READ_LATENCY = 4;
localparam int AXI_MM_WIDTH = 128;

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
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) ps_readout_data ();
// status
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*$clog2(buffer_pkg::SAMPLE_BUFFER_DEPTH))) ps_samples_write_depth ();
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*$clog2(buffer_pkg::TSTAMP_BUFFER_DEPTH))) ps_timestamps_write_depth ();
// configuration
Axis_If #(.DWIDTH(3)) ps_capture_arm_start_stop ();
Axis_If #(.DWIDTH(buffer_pkg::BANKING_MODE_WIDTH)) ps_capture_banking_mode ();
Axis_If #(.DWIDTH(1)) ps_capture_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_readout_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_readout_start ();

timetagging_sample_buffer #(
  .BUFFER_READ_LATENCY(BUFFFER_READ_LATENCY),
  .AXI_MM_WIDTH(AXI_MM_WIDTH)
) dut_i (
  .adc_clk,
  .adc_reset,
  .adc_samples_in,
  .adc_timestamps_in,
  .adc_digital_trigger_in,
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

timetagging_sample_buffer_tb #(
  .AXI_MM_WIDTH(AXI_MM_WIDTH)
) tb_i (
  .adc_clk,
  .adc_reset,
  .adc_samples_in,
  .adc_timestamps_in,
  .adc_digital_trigger_in,
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

enum {CAPTURE_RESET, CAPTURE_NO_RESET} capture_reset;
enum {READOUT_RESET, READOUT_NO_RESET} readout_reset;
enum {SW_START, HW_START} start_mode;
enum {MANUAL_STOP, FULL} stop_mode;
enum {ONLY_TIMESTAMPS, ONLY_SAMPLES, BOTH} input_mode;

initial begin
  debug.display("### TESTING SEGMENTED BUFFER TOPLEVEL ###", sim_util_pkg::DEFAULT);

  capture_reset = capture_reset.first;
  readout_reset = readout_reset.first;
  start_mode = start_mode.first;
  stop_mode = stop_mode.first;
  input_mode = input_mode.first;

  do begin: capture_reset
    do begin: readout_reset
      do begin: start_mode
        do begin: samples_cnt
          do begin: input_mode
            // mid-test reset
            adc_reset <= 1'b1;
            ps_reset <= 1'b1;

            adc_digital_trigger <= 1'b0;

            tb_i.init ();

            case (input_mode)
              ONLY_TIMESTAMPS:
                tb_i.adc_samples_enabled(1'b0);
                tb_i.adc_timestamps_enabled(1'b1);
              ONLY_SAMPLES:
                tb_i.adc_samples_enabled(1'b1);
                tb_i.adc_timestamps_enabled(1'b0);
              BOTH:
                tb_i.adc_samples_enabled(1'b1);
                tb_i.adc_timestamps_enabled(1'b1);
            endcase
            repeat (10) @(posedge ps_clk);
            ps_reset <= 1'b0;
            @(posedge adc_clk);
            adc_reset <= 1'b0;
            // send data
            // first arm or start
            for (int capture_iter = 0; capture_iter < ((capture_reset == CAPTURE_RESET) ? 2 : 1); capture_iter++) begin
              case (start_mode)
                SW_START:
                  // sending both arm and start will cause a software start
                  tb_i.capture_arm_start_stop(debug, 1'b1, 1'b1, 1'b0);
                HW_START:
                  // sending just arm but no start will arm the buffer and wait for
                  // a hardware start
                  tb_i.capture_arm_start_stop(debug, 1'b1, 1'b0, 1'b0);
                  // send hw start from trigger signal
                  repeat ($urandom_range(10, 20)) @(posedge adc_clk);
                  adc_digital_trigger <= 1'b1;
                  @(posedge adc_clk);
                  adc_digital_trigger <= 1'b0;
              endcase
              // receive data
              case (stop_mode)
                MANUAL_STOP:
                  repeat (100) @(posedge ps_clk);
                  // send stop
                  tb_i.capture_arm_start_stop(debug, 1'b0, 1'b0, 1'b1);
                FULL:
                  // should probably have a timeout
                  do @(posedge adc_clk); while (dut_i.adc_capture_full === '0);
              endcase
              // reset the capture
              if ((capture_reset == CAPTURE_RESET) && (capture_iter == 0)) begin
                // send reset signal
                tb_i.reset_capture(debug);
                @(posedge ps_clk);
                tb_i.clear_sent_data();
                tb_i.clear_write_depth();
              end
            end
            // do readout
            repeat (20) @(posedge ps_clk);
            for (int readout_iter = 0; readout_iter < ((readout_reset == READOUT_RESET) ? 2 : 1); readout_iter++) begin
              tb_i.start_readout(debug)
              repeat (BUFFER_DEPTH*rx_pkg::CHANNELS) begin
                do @(posedge ps_clk); while (~ps_readout_data.ok);
              end
              if ((readout_reset == READOUT_RESET) && (readout_iter == 0)) begin
                tb_i.reset_readout(debug);
                tb_i.clear_received_data();
              end
            end

            // clear queues
            tb_i.clear_write_depth();
            tb_i.clear_received_data();
            tb_i.clear_sent_data();
            //
            input_mode = input_mode.next;
          end while (input_mode != input_mode.first);
          stop_mode = stop_mode.next;
        end while (stop_mode != stop_mode.first);
        start_mode = start_mode.next;
      end while (start_mode != start_mode.first);
      readout_reset = readout_reset.next;
    end while (readout_reset != readout_reset.first);
    capture_reset = capture_reset.next;
  end while (capture_reset != capture_reset.first);

  debug.finish();
end

endmodule
