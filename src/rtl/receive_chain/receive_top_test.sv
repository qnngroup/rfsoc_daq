// receive_top_test.sv - Reed Foster
// verifies data from ADC is saved correctly

import sim_util_pkg::*;
import sample_discriminator_pkg::*;

`timescale 1ns / 1ps
module receive_top_test ();

sim_util_pkg::debug debug = new(DEFAULT); // printing, error tracking

logic adc_reset;
logic adc_clk = 0;
localparam ADC_CLK_RATE_HZ = 256_000_000;
always #(0.5s/ADC_CLK_RATE_HZ) adc_clk = ~adc_clk;

logic ps_reset;
logic ps_clk = 0;
localparam PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;


// DUT parameters
localparam int CHANNELS = 8;
localparam int TSTAMP_BUFFER_DEPTH = 128;
localparam int DATA_BUFFER_DEPTH = 1024;
localparam int AXI_MM_WIDTH = 128;
localparam int PARALLEL_SAMPLES = 4;
localparam int SAMPLE_WIDTH = 16;
localparam int APPROX_CLOCK_WIDTH = 48;

// derived parameters
localparam int SAMPLE_INDEX_WIDTH = $clog2(DATA_BUFFER_DEPTH*CHANNELS);
localparam int TIMESTAMP_WIDTH = SAMPLE_WIDTH * ((SAMPLE_INDEX_WIDTH + APPROX_CLOCK_WIDTH + (SAMPLE_WIDTH - 1)) / SAMPLE_WIDTH);
localparam int MUX_SELECT_BITS = $clog2(2*CHANNELS);

typedef logic signed [SAMPLE_WIDTH-1:0] int_t; // type for signed samples (needed to check subtraction is working properly)

// util for functions any_above_high and all_below_low for comparing data to thresholds
sample_discriminator_pkg::util #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES)
) disc_util;
// util for parsing timestamp/sample data from buffer output
sparse_sample_buffer_pkg::util #(
  .AXI_MM_WIDTH(AXI_MM_WIDTH),
  .TIMESTAMP_WIDTH(TIMESTAMP_WIDTH),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) buf_util;

// DUT data interfaces
Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) adc_data_in ();
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) adc_dma_out ();
// DUT configuration interfaces
Axis_If #(.DWIDTH(CHANNELS*SAMPLE_WIDTH*2)) ps_sample_discriminator_config ();
Axis_If #(.DWIDTH($clog2($clog2(CHANNELS)+1))) ps_buffer_config ();
Axis_If #(.DWIDTH(2)) ps_buffer_start_stop ();
Axis_If #(.DWIDTH(CHANNELS*MUX_SELECT_BITS)) ps_channel_mux_config ();
Axis_If #(.DWIDTH(32)) ps_buffer_timestamp_width ();

// configuration signals
logic ps_capture_start, ps_capture_stop, adc_trigger_in;
logic [$clog2($clog2(CHANNELS)+1)-1:0] ps_banking_mode;
logic [CHANNELS-1:0][SAMPLE_WIDTH-1:0] threshold_high, threshold_low;

always_comb begin
  for (int i = 0; i < CHANNELS; i++) begin
    ps_sample_discriminator_config.data[2*SAMPLE_WIDTH*i+:2*SAMPLE_WIDTH] = {threshold_high[i], threshold_low[i]};
  end
end

assign ps_buffer_config.data = ps_banking_mode;
assign ps_buffer_start_stop.data = {ps_capture_start, ps_capture_stop};

// allow the data to be manually updated when we change the range so the first sample for a new range isn't stale
// this simplifies the testing
logic update_input_data;
logic [CHANNELS-1:0][SAMPLE_WIDTH-1:0] data_range_low, data_range_high;
// queues of raw data sent to / received from the DUT
logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] raw_samples [CHANNELS][$];
logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] differentiated_samples [CHANNELS][$];
logic [AXI_MM_WIDTH-1:0] data_received [$];
logic [CHANNELS-1:0][TIMESTAMP_WIDTH-SAMPLE_INDEX_WIDTH-1:0] timer; // track the sent sample count between trials

receive_top #(
  .CHANNELS(CHANNELS),
  .TSTAMP_BUFFER_DEPTH(TSTAMP_BUFFER_DEPTH),
  .DATA_BUFFER_DEPTH(DATA_BUFFER_DEPTH),
  .AXI_MM_WIDTH(AXI_MM_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .APPROX_CLOCK_WIDTH(APPROX_CLOCK_WIDTH)
) dut_i (
  .ps_clk,
  .ps_reset,
  .ps_sample_discriminator_config,
  .ps_buffer_config,
  .ps_buffer_start_stop,
  .ps_channel_mux_config,
  .ps_buffer_timestamp_width,
  .adc_clk,
  .adc_reset,
  .adc_data_in,
  .adc_dma_out,
  .adc_trigger_in
);

// temp parallel register for calculating expected output of differentiator
logic [SAMPLE_WIDTH*PARALLEL_SAMPLES-1:0] diff_temp;
logic [CHANNELS-1:0][SAMPLE_WIDTH-1:0] prev_samples; // keep track of final sample in previous clock cycle for differentiator

// send data to DUT and save sent/received data
always @(posedge adc_clk) begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    if (adc_reset) begin
      adc_data_in.data[channel] <= '0;
      prev_samples = '0;
    end else begin
      if (adc_data_in.valid[channel]) begin
        // save data that was sent
        raw_samples[channel].push_front(adc_data_in.data[channel]);
        for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
          if (sample == 0) begin
            diff_temp[SAMPLE_WIDTH-1:0] = (
              int_t'(raw_samples[channel][0][SAMPLE_WIDTH-1:0])
              - int_t'(prev_samples[channel])
              ) >>> 1;
          end else begin
            diff_temp[sample*SAMPLE_WIDTH+:SAMPLE_WIDTH] = (
              int_t'(raw_samples[channel][0][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH])
              - int_t'(raw_samples[channel][0][(sample-1)*SAMPLE_WIDTH+:SAMPLE_WIDTH])
              ) >>> 1;
          end
        end
        prev_samples[channel] = raw_samples[channel][0][(PARALLEL_SAMPLES-1)*SAMPLE_WIDTH+:SAMPLE_WIDTH];
        differentiated_samples[channel].push_front(diff_temp);
      end
      if (adc_data_in.valid[channel] || update_input_data) begin
        // send new data
        for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
          adc_data_in.data[channel][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= $urandom_range(data_range_low[channel], data_range_high[channel]);
        end
      end
    end
  end
  // save all data in the same buffer and postprocess it later
  if (adc_dma_out.ok) begin
    data_received.push_front(adc_dma_out.data);
  end
end

task set_banking_mode(input int mode);
  ps_banking_mode <= mode;
  ps_buffer_config.valid <= 1'b1;
  do @(posedge ps_clk); while (~ps_buffer_config.ok);
  ps_buffer_config.valid <= 1'b0;
endtask

task start_acq(input bit use_axis);
  if (use_axis) begin
    ps_capture_stop <= 1'b0;
    ps_capture_start <= 1'b1;
    ps_buffer_start_stop.valid <= 1'b1;
    do @(posedge ps_clk); while (~ps_buffer_start_stop.ok);
    ps_capture_start <= 1'b0;
    ps_buffer_start_stop.valid <= 1'b0;
  end else begin
    adc_trigger_in <= 1'b1;
    @(posedge adc_clk);
    adc_trigger_in <= 1'b0;
  end
endtask

task stop_acq();
  ps_capture_stop <= 1'b1;
  ps_capture_start <= 1'b0;
  ps_buffer_start_stop.valid <= 1'b1;
  do @(posedge ps_clk); while (~ps_buffer_start_stop.ok);
  ps_capture_stop <= 1'b0;
  ps_buffer_start_stop.valid <= 1'b0;
endtask

task check_results(
  inout logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] expected [CHANNELS][$],
  input int ps_banking_mode,
  input logic [CHANNELS-1:0][SAMPLE_WIDTH-1:0] threshold_high,
  input logic [CHANNELS-1:0][SAMPLE_WIDTH-1:0] threshold_low,
  inout logic [CHANNELS-1:0][TIMESTAMP_WIDTH-SAMPLE_INDEX_WIDTH-1:0] timer
);
  // checks that:
  // - timestamps line up with when samples were sent
  // - all inputs > threshold_high were saved and all inputs < threshold_low
  //    were not
  // - all samples < threshold_high that were saved arrived in sequence after
  //    a sample > threshold_high

  // data structures for organizing DMA output
  logic [TIMESTAMP_WIDTH-1:0] timestamps [CHANNELS][$];
  logic [SAMPLE_WIDTH*PARALLEL_SAMPLES-1:0] samples [CHANNELS][$];

  // first report the size of the buffers
  for (int i = 0; i < CHANNELS; i++) begin
    debug.display($sformatf("expected[%0d].size() = %0d", i, expected[i].size()), VERBOSE);
  end
  debug.display($sformatf("data_received.size() = %0d", data_received.size()), VERBOSE);

  ///////////////////////////////////////////////////////////////////
  // organize DMA output into data structures for easier analysis
  ///////////////////////////////////////////////////////////////////
  buf_util.parse_buffer_output(data_received, timestamps, samples);
  debug.display("parsed data_received:", VERBOSE);
  for (int i = 0; i < CHANNELS; i++) begin
    debug.display($sformatf("timestamps[%0d].size() = %0d", i, timestamps[i].size()), VERBOSE);
    debug.display($sformatf("samples[%0d].size() = %0d", i, samples[i].size()), VERBOSE);
  end

  //////////////////////////////////////
  // process data "like normal"
  //////////////////////////////////////
  buf_util.check_timestamps_and_data(
    debug,
    ps_banking_mode,
    threshold_high,
    threshold_low,
    timer,
    timestamps,
    samples,
    expected
  );

endtask

initial begin
  debug.display("### RUNNING TEST FOR RECEIVE_TOP ###", DEFAULT);
  adc_reset <= 1'b1;
  ps_reset <= 1'b1;
  ps_capture_start <= 1'b0;
  ps_capture_stop <= 1'b0;
  adc_trigger_in <= 1'b0;
  ps_banking_mode <= '0; // adc_reset banking mode (only enable channel 0 to start)
  timer <= '0; // adc_reset timer for all samples
  adc_data_in.valid <= '0;
  adc_dma_out.ready <= 1'b0;
  ps_sample_discriminator_config.valid <= 1'b0;
  ps_buffer_config.valid <= 1'b0;
  ps_buffer_start_stop.valid <= 1'b0;
  ps_channel_mux_config.valid <= 1'b0;
  repeat (100) @(posedge ps_clk);
  adc_reset <= 1'b0;
  @(posedge ps_clk);
  ps_reset <= 1'b0;
  repeat (100) @(posedge adc_clk);
  // do test
  for (int mux_select_mode = 0; mux_select_mode < 2; mux_select_mode++) begin
    // change mux to select either raw data or output of differentiator
    for (int channel = 0; channel < CHANNELS; channel++) begin
      ps_channel_mux_config.data[channel*MUX_SELECT_BITS+:MUX_SELECT_BITS] <= channel + mux_select_mode*CHANNELS;
    end
    // write the new config
    ps_channel_mux_config.valid <= 1'b1;
    do @(posedge ps_clk); while (~ps_channel_mux_config.ok);
    ps_channel_mux_config.valid <= 1'b0;
    for (int start_type = 0; start_type < 2; start_type++) begin
      for (int in_valid_rand = 0; in_valid_rand < 2; in_valid_rand++) begin
        for (int bank_mode = 0; bank_mode < 4; bank_mode++) begin
          @(posedge ps_clk);
          set_banking_mode(bank_mode);
          for (int amplitude_mode = 0; amplitude_mode < 5; amplitude_mode++) begin
            repeat (10) @(posedge ps_clk);
            unique case (amplitude_mode)
              0: begin
                // save everything
                for (int channel = 0; channel < CHANNELS; channel++) begin
                  data_range_low[channel] <= 16'h03c0;
                  data_range_high[channel] <= 16'h04ff;
                  threshold_low[channel] <= 16'h0000;
                  threshold_high[channel] <= 16'h0100;
                end
              end
              1: begin
                // send stuff straddling the threshold with strong hysteresis
                for (int channel = 0; channel < CHANNELS; channel++) begin
                  data_range_low[channel] <= 16'h00ff;
                  data_range_high[channel] <= 16'h04ff;
                  threshold_low[channel] <= 16'h01c0;
                  threshold_high[channel] <= 16'h0400;
                end
              end
              2: begin
                // send stuff below the threshold
                for (int channel = 0; channel < CHANNELS; channel++) begin
                  data_range_low[channel] <= 16'h0000;
                  data_range_high[channel] <= 16'h01ff;
                  threshold_low[channel] <= 16'h0200;
                  threshold_high[channel] <= 16'h0200;
                end
              end
              3: begin
                // send stuff straddling the threshold with weak hysteresis
                for (int channel = 0; channel < CHANNELS; channel++) begin
                  data_range_low[channel] <= 16'h0000;
                  data_range_high[channel] <= 16'h04ff;
                  threshold_low[channel] <= 16'h03c0;
                  threshold_high[channel] <= 16'h0400;
                end
              end
              4: begin
                // send stuff that mostly gets filtered out
                for (int channel = 0; channel < CHANNELS; channel++) begin
                  data_range_low[channel] <= 16'h0000;
                  data_range_high[channel] <= 16'h04ff;
                  threshold_low[channel] <= 16'h03c0;
                  threshold_high[channel] <= 16'h0400;
                end
              end
            endcase
            // write the new threshold to the sample discriminator and update the input data
            ps_sample_discriminator_config.valid <= 1'b1;
            do @(posedge ps_clk); while (~ps_sample_discriminator_config.ok);
            ps_sample_discriminator_config.valid <= 1'b0;
            @(posedge adc_clk);
            update_input_data <= 1'b1;
            @(posedge adc_clk);
            update_input_data <= 1'b0;

            if (start_type == 0) begin
              repeat (10) @(posedge adc_clk);
            end else begin
              repeat (3) @(posedge ps_clk);
            end
            start_acq(start_type & 1'b1);
            
            // wait for latency of CDC (PS->RFADC) for configuration registers
            repeat (20) @(posedge ps_clk);

            // send a random number of samples, with in_valid_rand setting
            // whether or not valid should be continously high or randomly
            // toggled. the final arguments specify valid is reset and the ready signal is ignored
            adc_data_in.send_samples(adc_clk, $urandom_range(50,500), in_valid_rand & 1'b1, 1'b1, 1'b1);
            repeat (10) @(posedge adc_clk);
            @(posedge ps_clk);
            stop_acq();
            // readout over DMA interface with randomly toggling ready signal.
            // wait for last timeout is 100k clock cycles
            adc_dma_out.do_readout(adc_clk, 1'b1, 100000);
            debug.display($sformatf("checking results amplitude_mode = %0d", amplitude_mode), VERBOSE);
            debug.display($sformatf("banking mode                    = %0d", bank_mode), VERBOSE);
            debug.display($sformatf("samples sent with rand_valid    = %0d", in_valid_rand), VERBOSE);
            debug.display($sformatf("mux_select_mode                 = %0d", mux_select_mode), VERBOSE);
            if (mux_select_mode == 0) begin
              // check with raw_samples
              check_results(raw_samples, bank_mode, threshold_high, threshold_low, timer);
              for (int channel = 0; channel < CHANNELS; channel++) begin
                while (differentiated_samples[channel].size() > 0) differentiated_samples[channel].pop_back();
              end
            end else begin
              // check with differentiated_samples
              check_results(differentiated_samples, bank_mode, threshold_high, threshold_low, timer);
              for (int channel = 0; channel < CHANNELS; channel++) begin
                while (raw_samples[channel].size() > 0) raw_samples[channel].pop_back();
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
