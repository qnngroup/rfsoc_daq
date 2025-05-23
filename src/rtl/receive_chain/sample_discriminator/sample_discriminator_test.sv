// sample_discriminator_test.sv - Reed Foster
// test sample_discriminator with various delays, digital/analog triggering,
// various thresholds for the analog trigger, enable/disable of the
// discriminator.
//
// for each test:
// update configuration registers, wait a few cycles to synchronize, then
// reset the analog hysteresis and sample_count (with adc_reset_state)

`timescale 1ns / 1ps
module sample_discriminator_test();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT); // printing, error tracking

logic adc_reset;
logic adc_clk = 0;
localparam int ADC_CLK_RATE_HZ = 512_000_000;
always #(0.5s/ADC_CLK_RATE_HZ) adc_clk = ~adc_clk;

logic ps_reset;
logic ps_clk = 0;
localparam int PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_data_in ();
Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_samples_out ();
Realtime_Parallel_If #(.DWIDTH(buffer_pkg::TSTAMP_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_timestamps_out ();
logic adc_reset_state;
logic [tx_pkg::CHANNELS-1:0] adc_digital_trigger_in;

localparam int MAX_DELAY_CYCLES = 128;
localparam int TIMER_BITS = $clog2(MAX_DELAY_CYCLES);
typedef logic [TIMER_BITS-1:0] delay_t;
Axis_If #(.DWIDTH(2*rx_pkg::CHANNELS*rx_pkg::SAMPLE_WIDTH)) ps_thresholds ();
Axis_If #(.DWIDTH(3*rx_pkg::CHANNELS*TIMER_BITS)) ps_delays ();
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS))) ps_trigger_select ();
Axis_If #(.DWIDTH(rx_pkg::CHANNELS)) ps_bypass ();

// right now the way this is implemented is a little janky, but it gets the
// job done. TODO fix so we don't have this global variable being passed
// around all over the place
logic [rx_pkg::CHANNELS-1:0][$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS)-1:0] trigger_sources;

sample_discriminator_tb #(
  .MAX_DELAY_CYCLES(MAX_DELAY_CYCLES)
) tb_i (
  .adc_clk,
  .adc_reset,
  .adc_data_in,
  .adc_samples_out,
  .adc_timestamps_out,
  .adc_digital_trigger_in,
  .ps_clk,
  .ps_thresholds,
  .ps_delays,
  .ps_trigger_select,
  .ps_bypass,
  .trigger_sources
);

sample_discriminator #(
  .MAX_DELAY_CYCLES(MAX_DELAY_CYCLES)
) dut_i (
  .adc_clk,
  .adc_reset,
  .adc_data_in,
  .adc_samples_out,
  .adc_timestamps_out,
  .adc_reset_state,
  .adc_digital_trigger_in,
  .ps_clk,
  .ps_reset,
  .ps_thresholds,
  .ps_delays,
  .ps_trigger_select,
  .ps_bypass
);

logic [rx_pkg::CHANNELS-1:0][rx_pkg::SAMPLE_WIDTH-1:0] low_thresholds, high_thresholds;
logic [rx_pkg::CHANNELS-1:0][TIMER_BITS-1:0] start_delays, stop_delays, digital_delays;

int max_delay;
logic [TIMER_BITS-1:0] start_delay_nsamp, stop_delay_nsamp, digital_delay_nsamp;
rx_pkg::sample_t min_samp, max_samp;
logic [rx_pkg::CHANNELS-1:0] bypassed_channel_mask;

int initial_q_length;

enum {NO_BYPASS, ALL_BYPASS, MIX_BYPASS} bypass_mode;
enum {ANALOG_ONLY, DIGITAL_ONLY, MIX_SOURCE} source_mode;
enum {ZERO_DELAY, SHORT_DELAY, FULL_DELAY} delay_mode;

initial begin
  debug.display("### TESTING SAMPLE DISCRIMINATOR ###", sim_util_pkg::DEFAULT);

  bypass_mode = bypass_mode.first;
  source_mode = source_mode.first;
  delay_mode = delay_mode.first;

  do begin: bypass
    do begin: source
      for (int decimation = 1; decimation < 8; decimation++) begin
        do begin: delay
          // mid-test reset
          tb_i.init();
          ps_reset <= 1'b1;
          adc_reset <= 1'b1;
          adc_reset_state <= 1'b0;
          tb_i.adc_send_samples_decimation <= decimation;

          debug.display($sformatf("testing with bypass_mode = %0p, source_mode = %0p, decimation = %0d, delay_mode = %0p", bypass_mode, source_mode, decimation, delay_mode), sim_util_pkg::VERBOSE);

          // deassert reset
          repeat (10) @(posedge ps_clk);
          ps_reset <= 1'b0;
          @(posedge adc_clk);
          adc_reset <= 1'b0;

          repeat (100) @(posedge adc_clk);
          min_samp = rx_pkg::MIN_SAMP;
          max_samp = rx_pkg::MAX_SAMP;
          tb_i.set_input_range(.min(min_samp), .max(max_samp));

          repeat (100) @(posedge adc_clk);
          ///////////////////////
          // configure DUT
          ///////////////////////
          // set which channels are bypassed
          for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
            case (bypass_mode)
              NO_BYPASS: bypassed_channel_mask[channel] = 1'b0;
              ALL_BYPASS: bypassed_channel_mask[channel] = 1'b1;
              MIX_BYPASS: bypassed_channel_mask[channel] = $urandom_range(0, 1);
            endcase
          end
          tb_i.set_bypassed_channels(debug, bypassed_channel_mask);
          // set thresholds
          @(posedge ps_clk);
          for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
            high_thresholds[channel] = rx_pkg::sample_t'($urandom_range(
              int'(rx_pkg::MIN_SAMP),
              int'(rx_pkg::MAX_SAMP))
            );
            low_thresholds[channel] = rx_pkg::sample_t'($urandom_range(
              int'(rx_pkg::MIN_SAMP),
              int'(rx_pkg::sample_t'(high_thresholds[channel])))
            );
          end
          tb_i.set_thresholds(debug, low_thresholds, high_thresholds);
          // set delays
          for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
            case (delay_mode)
              ZERO_DELAY: max_delay = 0;
              SHORT_DELAY: max_delay = 4;
              FULL_DELAY: max_delay = MAX_DELAY_CYCLES/decimation - 1;
            endcase
            if (max_delay >= MAX_DELAY_CYCLES/decimation) begin
              max_delay = MAX_DELAY_CYCLES/decimation - 1;
            end
            if (bypassed_channel_mask[channel] === 1'b1) begin
              max_delay = 0; // don't use any delay
            end
            digital_delay_nsamp = $urandom_range(0, max_delay);
            start_delay_nsamp = $urandom_range(0, max_delay);
            stop_delay_nsamp = $urandom_range(0, max_delay);
            digital_delays[channel] = digital_delay_nsamp*decimation;
            stop_delays[channel] = stop_delay_nsamp*decimation;
            start_delays[channel] = start_delay_nsamp*decimation;
            debug.display($sformatf(
              "digital_delays[%0d] = %0d, start_delays[%0d] = %0d, stop_delays[%0d] = %0d, start+stop = %0d",
              channel, digital_delays[channel],
              channel, start_delays[channel],
              channel, stop_delays[channel],
              int'(stop_delays[channel]) + int'(start_delays[channel])),
              sim_util_pkg::VERBOSE
            );
          end
          tb_i.set_delays(debug, start_delays, stop_delays, digital_delays);
          // set trigger sources
          for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
            case (source_mode)
              ANALOG_ONLY: trigger_sources[channel] = $urandom_range(0, rx_pkg::CHANNELS - 1);
              DIGITAL_ONLY: trigger_sources[channel] = $urandom_range(rx_pkg::CHANNELS, rx_pkg::CHANNELS + tx_pkg::CHANNELS - 1);
              MIX_SOURCE: trigger_sources[channel] = $urandom_range(0, rx_pkg::CHANNELS + tx_pkg::CHANNELS - 1);
            endcase
          end
          tb_i.set_trigger_sources(debug, trigger_sources);

          // wait for delays/thresholds to synchronize before sending data
          repeat (10) @(posedge ps_clk);
          @(posedge adc_clk);
          tb_i.enable_send();
          // wait some time so that we get good data
          repeat (4+MAX_DELAY_CYCLES) @(posedge adc_clk);
          // send a reset so we have valid data in the pipeline and we don't miss
          // any pre-trigger samples
          adc_reset_state <= 1'b1;
          // wait until we're aligned with a valid input
          debug.display("waiting for adc_reset_state to take effect", sim_util_pkg::DEBUG);
          do @(posedge adc_clk); while (~adc_data_in.valid);
          // wait until data_out.valid goes low to make sure we flush the pipeline
          do @(posedge adc_clk); while (adc_samples_out.valid & (~bypassed_channel_mask));
          adc_reset_state <= 1'b0;
          @(posedge adc_clk);
          debug.display("clearing input data", sim_util_pkg::DEBUG);
          // clear input data (but keep start_delays/decimation samples)
          for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
            initial_q_length = start_delays[channel]/decimation;
            while (tb_i.adc_data_in_tx_i.data_q[channel].size() > initial_q_length) begin 
              tb_i.adc_data_in_tx_i.data_q[channel].pop_back();
            end
            if (tb_i.adc_data_in_tx_i.data_q[channel].size() != initial_q_length) begin
              debug.error($sformatf(
                "didn't get enough samples before start, needed at least %0d, got %0d",
                initial_q_length,
                tb_i.adc_data_in_tx_i.data_q[channel].size())
              );
            end
          end
          // clear any output data from the DUT
          tb_i.adc_timestamps_out_rx_i.clear_queues();
          tb_i.adc_samples_out_rx_i.clear_queues();
          tb_i.clear_trigger_q();

          debug.display("finished configuring DUT, sending data", sim_util_pkg::DEBUG);

          // send data and randomize input signal level
          repeat (4) begin
            repeat (10*decimation) @(posedge adc_clk); // send some data
            // randomize ensuring that min_samp < max_samp
            // could use a constraint class, but it's simple enough like this
            max_samp = $urandom_range(int'(rx_pkg::MIN_SAMP) + 1, int'(rx_pkg::MAX_SAMP));
            min_samp = $urandom_range(int'(rx_pkg::MIN_SAMP), int'(max_samp) - 1);
            tb_i.set_input_range(.min(min_samp), .max(max_samp));
            if (source_mode != ANALOG_ONLY) begin
              repeat ($urandom_range(0, 5*decimation)) @(posedge adc_clk);
              tb_i.send_digital_trigger($urandom_range(0, {tx_pkg::CHANNELS{1'b1}}));
              repeat (2+2*MAX_DELAY_CYCLES) @(posedge adc_clk);
            end
          end
          // stop acquisition and check output
          tb_i.disable_send();
          // make sure we get all the output data before checking the output
          repeat (2+2*MAX_DELAY_CYCLES) @(posedge adc_clk);
          // print debug information:
          // sent and received data, received timestamps
          for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
            debug.display($sformatf("sent_data[%0d] = ", channel), sim_util_pkg::DEBUG);
            tb_i.print_data(debug, tb_i.adc_data_in_tx_i.data_q[channel]);
          end
          for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
            debug.display($sformatf("received_data[%0d] = ", channel), sim_util_pkg::DEBUG);
            tb_i.print_data(debug, tb_i.adc_samples_out_rx_i.data_q[channel]);
          end
          for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
            debug.display($sformatf("sent_data[%0d] = ", channel), sim_util_pkg::DEBUG);
            for (int i = tb_i.adc_data_in_tx_i.data_q[channel].size() - 1; i >= 0; i--) begin
              debug.display($sformatf("%x", tb_i.adc_data_in_tx_i.data_q[channel][i]), sim_util_pkg::DEBUG);
            end
          end
          for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
            debug.display($sformatf("received_data[%0d] = ", channel), sim_util_pkg::DEBUG);
            for (int i = tb_i.adc_samples_out_rx_i.data_q[channel].size() - 1; i >= 0; i--) begin
              debug.display($sformatf("%x", tb_i.adc_samples_out_rx_i.data_q[channel][i]), sim_util_pkg::DEBUG);
            end
          end
          for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
            debug.display($sformatf(
              "received_timestamps[%0d] = %0p",
              channel,
              tb_i.adc_timestamps_out_rx_i.data_q[channel]),
              sim_util_pkg::DEBUG
            );
          end
          for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
            debug.display($sformatf(
              "trigger_sample_count_q[%0d] = %0p",
              channel,
              tb_i.trigger_sample_count_q[channel]),
              sim_util_pkg::DEBUG
            );
          end
          // actually check results
          tb_i.check_results(
            debug,
            low_thresholds, high_thresholds,
            start_delays, stop_delays, digital_delays,
            trigger_sources,
            bypassed_channel_mask
          );

          tb_i.clear_queues();
          delay_mode = delay_mode.next;
        end while (delay_mode != delay_mode.first);
      end
      source_mode = source_mode.next;
    end while (source_mode != source_mode.first);
    bypass_mode = bypass_mode.next;
  end while (bypass_mode != bypass_mode.first);

  debug.finish();
end

endmodule
