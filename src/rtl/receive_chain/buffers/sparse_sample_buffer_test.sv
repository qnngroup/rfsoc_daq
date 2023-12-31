// sparse_sample_buffer_test.sv - Reed Foster
// Check that the combined banked sample_buffer and sample_discriminator work
// correctly, saving the correct data and outputting it in the correct format
// (i.e. timestamps first, then data, and for each bank, outputting the
// corresponding channel index and sample quantity stored in that bank)

import sim_util_pkg::*;
import sample_discriminator_pkg::*;

`timescale 1ns / 1ps
module sparse_sample_buffer_test ();

sim_util_pkg::math #(int) math; // abs, max functions on integers
sim_util_pkg::debug #(.VERBOSITY(DEFAULT)) debug = new; // printing, error tracking

logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

logic reset;

localparam int CHANNELS = 8;
localparam int TSTAMP_BUFFER_DEPTH = 128;
localparam int DATA_BUFFER_DEPTH = 1024;
localparam int AXI_MM_WIDTH = 128;
localparam int PARALLEL_SAMPLES = 1;
localparam int SAMPLE_WIDTH = 16;
localparam int APPROX_CLOCK_WIDTH = 48;

// derived parameters
localparam int SAMPLE_INDEX_WIDTH = $clog2(DATA_BUFFER_DEPTH*CHANNELS);
localparam int TIMESTAMP_WIDTH = SAMPLE_WIDTH * ((SAMPLE_INDEX_WIDTH + APPROX_CLOCK_WIDTH + (SAMPLE_WIDTH - 1)) / SAMPLE_WIDTH);

localparam int DMA_WORD_PARSE_WIDTH = math.max(2*TIMESTAMP_WIDTH, 2*PARALLEL_SAMPLES*SAMPLE_WIDTH);

// util for functions any_above_high and all_below_low for comparing data to thresholds
sample_discriminator_pkg::util #(.SAMPLE_WIDTH(SAMPLE_WIDTH), .PARALLEL_SAMPLES(PARALLEL_SAMPLES)) disc_util;
sparse_sample_buffer_pkg::util #(.AXI_MM_WIDTH(AXI_MM_WIDTH), .TIMESTAMP_WIDTH(TIMESTAMP_WIDTH), .DATA_WIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) buf_util;

Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) data_in ();
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) data_out ();
Axis_If #(.DWIDTH(2+$clog2($clog2(CHANNELS)+1))) buffer_config_in ();
Axis_If #(.DWIDTH(CHANNELS*SAMPLE_WIDTH*2)) discriminator_config_in();

logic capture_start, capture_stop;
logic [$clog2($clog2(CHANNELS)+1)-1:0] banking_mode;
logic [CHANNELS-1:0][SAMPLE_WIDTH-1:0] threshold_high, threshold_low;

always_comb begin
  for (int i = 0; i < CHANNELS; i++) begin
    discriminator_config_in.data[2*SAMPLE_WIDTH*i+:2*SAMPLE_WIDTH] = {threshold_high[i], threshold_low[i]};
  end
end

assign buffer_config_in.data = {banking_mode, capture_start, capture_stop};

sparse_sample_buffer #(
  .CHANNELS(CHANNELS),
  .TSTAMP_BUFFER_DEPTH(TSTAMP_BUFFER_DEPTH),
  .DATA_BUFFER_DEPTH(DATA_BUFFER_DEPTH),
  .AXI_MM_WIDTH(AXI_MM_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .APPROX_CLOCK_WIDTH(APPROX_CLOCK_WIDTH)
) dut_i (
  .clk,
  .reset,
  .timestamp_width(),
  .data_in,
  .data_out,
  .discriminator_config_in,
  .buffer_config_in
);

logic update_input_data;
logic [CHANNELS-1:0][SAMPLE_WIDTH-1:0] data_range_low, data_range_high;
logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] data_sent [CHANNELS][$];
logic [AXI_MM_WIDTH-1:0] data_received [$];
logic [CHANNELS-1:0][TIMESTAMP_WIDTH-SAMPLE_INDEX_WIDTH-1:0] timer;

// send data to DUT and save sent/received data
always @(posedge clk) begin
  for (int i = 0; i < CHANNELS; i++) begin
    if (reset) begin
      data_in.data[i] <= '0;
    end else begin
      if (data_in.valid[i]) begin
        // save data that was sent
        data_sent[i].push_front(data_in.data[i]);
      end
      if (data_in.valid[i] || update_input_data) begin
        // send new data
        for (int j = 0; j < PARALLEL_SAMPLES; j++) begin
          data_in.data[i][j*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= $urandom_range(data_range_low[i], data_range_high[i]);
        end
      end
    end
  end
  // save all data in the same buffer and postprocess it later
  if (data_out.ok) begin
    data_received.push_front(data_out.data);
  end
end

task check_results(
  input int banking_mode,
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

  // signals for checking correct operation of the DUT
  logic is_high;
  logic [SAMPLE_INDEX_WIDTH-1:0] sample_index;

  // first report the size of the buffers
  for (int i = 0; i < CHANNELS; i++) begin
    debug.display($sformatf("data_sent[%0d].size() = %0d", i, data_sent[i].size()), VERBOSE);
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
      "removing %0d samples from data_sent[%0d]",
      data_sent[channel].size(),
      channel
    ), VERBOSE);
    while (data_sent[channel].size() > 0) begin
      data_sent[channel].pop_back();
      timer[channel] = timer[channel] + 1'b1;
    end
  end

  for (int channel = 0; channel < (1 << banking_mode); channel++) begin
    // report timestamp/sample queue sizes
    debug.display($sformatf(
      "timestamps[%0d].size() = %0d",
      channel,
      timestamps[channel].size()
    ), VERBOSE);
    debug.display($sformatf(
      "samples[%0d].size() = %0d",
      channel,
      samples[channel].size()
    ), VERBOSE);
    if (samples[channel].size() > data_sent[channel].size()) begin
      debug.error($sformatf(
        "too many samples for channel %0d with banking mode %0d: got %0d, expected at most %0d",
        channel,
        banking_mode,
        samples[channel].size(),
        data_sent[channel].size()
      ));
    end
    /////////////////////////////
    // check all the samples
    /////////////////////////////
    // The sample counter and hysteresis tracking of the sample discriminator
    // are reset before each trial. Therefore is_high is reset.
    is_high = 0;
    sample_index = 0; // index of sample in received samples buffer
    while (data_sent[channel].size() > 0) begin
      debug.display($sformatf(
        "processing sample %0d from channel %0d: samp = %0x, timer = %0x",
        data_sent[channel].size(),
        channel,
        data_sent[channel][$],
        timer[channel]
      ), DEBUG);
      if (disc_util.any_above_high(data_sent[channel][$], threshold_high[channel])) begin
        debug.display($sformatf(
          "%x contains a sample greater than %x",
          data_sent[channel][$],
          threshold_high[channel]
        ), DEBUG);
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
      end else if (disc_util.all_below_low(data_sent[channel][$], threshold_low[channel])) begin
        is_high = 1'b0;
      end
      if (is_high) begin
        if (data_sent[channel][$] !== samples[channel][$]) begin
          debug.error($sformatf(
            "mismatched data: got %x, expected %x",
            samples[channel][$],
            data_sent[channel][$]
          ));
        end
        samples[channel].pop_back();
        sample_index = sample_index + 1'b1;
      end
      data_sent[channel].pop_back();
      timer[channel] = timer[channel] + 1'b1;
    end
    // check to make sure we didn't miss any data
    if (timestamps[channel].size() > 0) begin
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
      ), DEBUG);
    end
    if (samples[channel].size() > 0) begin
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
      ), DEBUG);
    end
    // should not be any leftover data_sent samples, since the while loop
    // won't terminate until data_sent[channel] is empty. therefore don't
    // bother checking
  end
  for (int channel = 0; channel < CHANNELS; channel++) begin
    debug.display($sformatf(
      "timer[%0d] = %0d (0x%x)",
      channel,
      timer[channel],
      timer[channel]
    ), DEBUG);
  end

endtask

task start_acq_with_banking_mode(input int mode);
  capture_start <= 1'b1;
  banking_mode <= mode;
  buffer_config_in.valid <= 1'b1;
  @(posedge clk);
  buffer_config_in.valid <= 1'b0;
  capture_start <= 1'b0;
endtask

task stop_acq();
  capture_stop <= 1'b1;
  capture_start <= 1'b0;
  buffer_config_in.valid <= 1'b1;
  @(posedge clk);
  buffer_config_in.valid <= 1'b0;
  capture_start <= 1'b0;
  capture_stop <= 1'b0;
endtask

initial begin
  debug.display("### running test for sparse_sample_buffer ###", DEFAULT);
  reset <= 1'b1;
  capture_start <= 1'b0;
  capture_stop <= 1'b0;
  timer <= '0; // reset timer for all channels
  banking_mode <= '0; // only enable channel 0 to start
  data_out.ready <= '0;
  data_in.valid <= '0;
  repeat (100) @(posedge clk);
  reset <= 1'b0;
  repeat (50) @(posedge clk);

  for (int in_valid_rand = 0; in_valid_rand < 2; in_valid_rand++) begin
    for (int bank_mode = 0; bank_mode < 4; bank_mode++) begin
      for (int amplitude_mode = 0; amplitude_mode < 5; amplitude_mode++) begin
        repeat (10) @(posedge clk);
        unique case (amplitude_mode)
          0: begin
            // save everything
            for (int i = 0; i < CHANNELS; i++) begin
              data_range_low[i] <= 16'h03c0;
              data_range_high[i] <= 16'h04ff;
              threshold_low[i] <= 16'h0000;
              threshold_high[i] <= 16'h0100;
            end
          end
          1: begin
            // send stuff straddling the threshold with strong hysteresis
            for (int i = 0; i < CHANNELS; i++) begin
              data_range_low[i] <= 16'h00ff;
              data_range_high[i] <= 16'h04ff;
              threshold_low[i] <= 16'h01c0;
              threshold_high[i] <= 16'h0400;
            end
          end
          2: begin
            // send stuff below the threshold
            for (int i = 0; i < CHANNELS; i++) begin
              data_range_low[i] <= 16'h0000;
              data_range_high[i] <= 16'h01ff;
              threshold_low[i] <= 16'h0200;
              threshold_high[i] <= 16'h0200;
            end
          end
          3: begin
            // send stuff straddling the threshold with weak hysteresis
            for (int i = 0; i < CHANNELS; i++) begin
              data_range_low[i] <= 16'h0000;
              data_range_high[i] <= 16'h04ff;
              threshold_low[i] <= 16'h03c0;
              threshold_high[i] <= 16'h0400;
            end
          end
          4: begin
            // send stuff that mostly gets filtered out
            for (int i = 0; i < CHANNELS; i++) begin
              data_range_low[i] <= 16'h0000;
              data_range_high[i] <= 16'h04ff;
              threshold_low[i] <= 16'h03c0;
              threshold_high[i] <= 16'h0400;
            end
          end
        endcase
        // write the new threshold to the discriminator and update the input data
        discriminator_config_in.valid <= 1'b1;
        update_input_data <= 1'b1;
        @(posedge clk);
        discriminator_config_in.valid <= 1'b0;
        update_input_data <= 1'b0;

        repeat (10) @(posedge clk);
        start_acq_with_banking_mode(bank_mode);

        data_in.send_samples(clk, $urandom_range(50,500), in_valid_rand & 1'b1, 1'b1, 1'b1);
        repeat (10) @(posedge clk);
        stop_acq();
        data_out.do_readout(clk, 1'b1, 100000);
        debug.display($sformatf("checking results amplitude_mode = %0d", amplitude_mode), VERBOSE);
        debug.display($sformatf("banking mode                    = %0d", bank_mode), VERBOSE);
        debug.display($sformatf("samples sent with rand_valid    = %0d", in_valid_rand), VERBOSE);
        check_results(bank_mode, threshold_high, threshold_low, timer);
      end
    end
  end
  debug.finish();
end

endmodule
