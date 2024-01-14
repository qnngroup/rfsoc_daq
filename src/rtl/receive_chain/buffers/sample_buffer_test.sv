// sample_buffer_test.sv - Reed Foster
// Verifies correct operation of the banked sample buffer for a variety of
// configurations by comparing the data sent to the buffer with the data
// received from the buffer at the end of each subtest. These data are
// tracked with systemverilog queues.
// Properties to ensure/check:
// - verifies for each banking mode that the buffer correctly stores all of the
//   data sent to it, and that it sends out the data in the correct format
// - covers various cases of filling up single banks, multiple banks, or
//   completely filling the buffer
// - covers input data being sparse in time (i.e. low sample rate data) by
//   toggling the input valid signal
// - tests readout with continuous and toggling ready signal to verify
//   backpressure handling logicimport sim_util_pkg::*;

import sim_util_pkg::*;

`timescale 1ns / 1ps
module sample_buffer_test ();

sim_util_pkg::debug debug = new(DEFAULT); // printing, error tracking

logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

logic reset;

localparam int BUFFER_DEPTH = 1024;
localparam int CHANNELS = 8;
localparam int PARALLEL_SAMPLES = 1;
localparam int SAMPLE_WIDTH = 16;

logic start, stop;
logic start_aux;
logic [2:0] banking_mode;

Realtime_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) data_in ();
Axis_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH)) data_out ();
Axis_If #(.DWIDTH($clog2($clog2(CHANNELS)+1))) config_in ();
Axis_If #(.DWIDTH(2)) start_stop ();

assign config_in.data = banking_mode;
assign start_stop.data = {start, stop};

sample_buffer #(
  .CHANNELS(CHANNELS),
  .BUFFER_DEPTH(BUFFER_DEPTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH)
) dut_i (
  .clk,
  .reset,
  .data_in,
  .data_out,
  .config_in,
  .start_stop,
  .start_aux,
  .stop_aux(0),
  .capture_started(),
  .buffer_full()
);

int sample_count [CHANNELS];
logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] data_sent [CHANNELS][$];
logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] data_received [$];
int last_received [$];

// send data to DUT and save sent/received data
always @(posedge clk) begin
  for (int i = 0; i < CHANNELS; i++) begin
    if (reset) begin
      sample_count[i] <= 0;
      data_in.data[i] <= '0;
    end else begin
      if (data_in.valid[i]) begin
        // send new data
        sample_count[i] <= sample_count[i] + 1;
        for (int j = 0; j < PARALLEL_SAMPLES; j++) begin
          data_in.data[i][j*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= $urandom_range({SAMPLE_WIDTH{1'b1}});
        end
        // save data that was sent
        data_sent[i].push_front(data_in.data[i]);
      end
    end
  end
  // save all data in the same buffer and postprocess it later
  if (data_out.ok) begin
    data_received.push_front(data_out.data);
    if (data_out.last) begin
      last_received.push_front(data_received.size());
    end
  end
end

task check_results(
  input int banking_mode,
  input bit missing_ok,
  input int expected_last
);
  logic [SAMPLE_WIDTH*PARALLEL_SAMPLES:0] temp_sample;
  int current_channel, n_samples;
  for (int i = 0; i < CHANNELS; i++) begin
    debug.display($sformatf(
      "data_sent[%0d].size() = %0d",
      i,
      data_sent[i].size()),
      VERBOSE
    );
  end
  debug.display($sformatf(
    "data_received.size() = %0d",
    data_received.size()),
    VERBOSE
  );
  // check last
  if (last_received.size() != 1) begin
    debug.error($sformatf("expected a single tlast event, got %0d", last_received.size()));
  end else begin
    if ((last_received[$] != expected_last) & (~missing_ok)) begin
      // if we have some samples missing, last won't be exactly equal to
      // num_samples + 2
      debug.error($sformatf(
        "expected to receive tlast event on the %0d sample, got it on the %0d sample",
        expected_last,
        last_received[$])
      );
    end
  end
  while (last_received.size() > 0) last_received.pop_back();
  while (data_received.size() > 0) begin
    current_channel = data_received.pop_back();
    n_samples = data_received.pop_back();
    debug.display($sformatf(
      "processing new bank with %0d samples from channel %0d",
      n_samples,
      current_channel),
      VERBOSE
    );
    for (int i = 0; i < n_samples; i++) begin
      if (data_sent[current_channel][$] != data_received[$]) begin
        debug.error($sformatf(
          "data mismatch error (channel = %0d, sample = %0d, received %x, sent %x)",
          current_channel,
          i,
          data_received[$],
          data_sent[current_channel][$])
        );
      end
      data_sent[current_channel].pop_back();
      data_received.pop_back();
    end
  end
  for (int i = 0; i < (1 << banking_mode); i++) begin
    // make sure there are no remaining samples in data_sent queues
    // corresponding to channels which are enabled as per banking_mode
    // caveat: if one of the channels filled up, then it's okay for there to
    // be missing samples in the other channels
    if ((data_sent[i].size() > 0) & (!missing_ok)) begin
      debug.error($sformatf(
        "leftover samples in data_sent[%0d]: %0d",
        i,
        data_sent[i].size())
      );
    end
    while (data_sent[i].size() > 0) data_sent[i].pop_back();
  end
  for (int i = (1 << banking_mode); i < CHANNELS; i++) begin
    // flush out any remaining samples in data_sent queue
    debug.display($sformatf(
      "removing %0d samples from data_sent[%0d]",
      data_sent[i].size(),
      i),
      VERBOSE
    );
    while (data_sent[i].size() > 0) data_sent[i].pop_back();
  end
endtask

task set_banking_mode(input int mode);
  banking_mode <= mode;
  config_in.valid <= 1'b1;
  while (~config_in.ok) @(posedge clk);
  config_in.valid <= 1'b0;
endtask

task start_acq(input bit use_axis);
  if (use_axis) begin
    stop <= 1'b0;
    start <= 1'b1;
    start_stop.valid <= 1'b1;
    @(posedge clk);
    start <= 1'b0;
    start_stop.valid <= 1'b0;
  end else begin
    start_aux <= 1'b1;
    @(posedge clk);
    start_aux <= 1'b0;
  end
endtask

task stop_acq();
  stop <= 1'b1;
  start <= 1'b0;
  start_stop.valid <= 1'b1;
  @(posedge clk);
  stop <= 1'b0;
  start_stop.valid <= 1'b0;
endtask

int samples_to_send;

initial begin
  debug.display("### TESTING SAMPLE_BUFFER ###", DEFAULT);
  reset <= 1'b1;
  start <= 1'b0;
  stop <= 1'b0;
  start_aux <= '0;
  banking_mode <= '0; // only enable channel 0
  data_in.valid <= '0;
  config_in.valid <= '0;
  start_stop.valid <= '0;
  repeat (100) @(posedge clk);
  reset <= 1'b0;
  repeat (50) @(posedge clk);
  for (int start_type = 0; start_type < 2; start_type++) begin
    for (int in_valid_rand = 0; in_valid_rand < 2; in_valid_rand++) begin
      for (int bank_mode = 0; bank_mode < 4; bank_mode++) begin
        for (int samp_count = 0; samp_count < 3; samp_count++) begin
          set_banking_mode(bank_mode);
          unique case (samp_count)
            0: samples_to_send = $urandom_range(4, 10); // a few samples
            1: samples_to_send = ((BUFFER_DEPTH - $urandom_range(2,10)) / (1 << bank_mode))*CHANNELS;
            2: samples_to_send = (BUFFER_DEPTH / (1 << bank_mode))*CHANNELS; // fill all buffers
          endcase
          start_acq(start_type & 1'b1);
          data_in.send_samples(clk, samples_to_send, in_valid_rand & 1'b1, 1'b1);
          repeat (10) @(posedge clk);
          stop_acq();
          data_out.do_readout(clk, 1'b1, 100000);
          debug.display($sformatf("checking results n_samples    = %d", samples_to_send), VERBOSE);
          debug.display($sformatf("banking mode                  = %d", bank_mode), VERBOSE);
          debug.display($sformatf("samples sent with rand_valid  = %d", in_valid_rand), VERBOSE);
          debug.display($sformatf("acquisition started with mode = %d", start_type), VERBOSE);
          // The second argument of check_results is if it's okay for there to
          // be missing samples that weren't stored.
          // When data_in.valid is randomly toggled on and off and enough samples
          // are sent to fill up all the banks, one of the banks will likely
          // fill up before the others are done, triggering a stop condition for
          // the other banks before they are full.
          // This results in "missing" samples that aren't saved
          check_results(bank_mode, (samp_count == 2) & (in_valid_rand == 1), samples_to_send*(1 << bank_mode) + 2*CHANNELS);
        end
      end
    end
  end
  debug.finish();
end

endmodule
