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

sim_util_pkg::debug #(.VERBOSITY(DEFAULT)) dbg = new; // printing, error tracking

logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

logic reset;

localparam int BUFFER_DEPTH = 1024;
localparam int N_CHANNELS = 8;
localparam int PARALLEL_SAMPLES = 1;
localparam int SAMPLE_WIDTH = 16;

logic start, stop;
logic [2:0] banking_mode;

assign config_in.data = {banking_mode, start, stop};

Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(N_CHANNELS)) data_in ();
Axis_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH)) data_out ();
Axis_If #(.DWIDTH(2+$clog2($clog2(N_CHANNELS)+1))) config_in ();

sample_buffer #(
  .N_CHANNELS(N_CHANNELS),
  .BUFFER_DEPTH(BUFFER_DEPTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH)
) dut_i (
  .clk,
  .reset,
  .data_in,
  .data_out,
  .config_in
);

int sample_count [N_CHANNELS];
logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] data_sent [N_CHANNELS][$];
logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] data_received [$];

// send data to DUT and save sent/received data
always @(posedge clk) begin
  for (int i = 0; i < N_CHANNELS; i++) begin
    if (reset) begin
      sample_count[i] <= 0;
      data_in.data[i] <= '0;
    end else begin
      if (data_in.ok[i]) begin
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
  end
end

task check_results(input int banking_mode, input bit missing_ok);
  logic [SAMPLE_WIDTH*PARALLEL_SAMPLES:0] temp_sample;
  int current_channel, n_samples;
  for (int i = 0; i < N_CHANNELS; i++) begin
    dbg.display($sformatf(
      "data_sent[%0d].size() = %0d",
      i,
      data_sent[i].size()),
      VERBOSE
    );
  end
  dbg.display($sformatf(
    "data_received.size() = %0d",
    data_received.size()),
    VERBOSE
  );
  while (data_received.size() > 0) begin
    current_channel = data_received.pop_back();
    n_samples = data_received.pop_back();
    dbg.display($sformatf(
      "processing new bank with %0d samples from channel %0d",
      n_samples,
      current_channel),
      VERBOSE
    );
    for (int i = 0; i < n_samples; i++) begin
      if (data_sent[current_channel][$] != data_received[$]) begin
        dbg.error($sformatf(
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
      dbg.error($sformatf(
        "leftover samples in data_sent[%0d]: %0d",
        i,
        data_sent[i].size())
      );
    end
    while (data_sent[i].size() > 0) data_sent[i].pop_back();
  end
  for (int i = (1 << banking_mode); i < N_CHANNELS; i++) begin
    // flush out any remaining samples in data_sent queue
    dbg.display($sformatf(
      "removing %0d samples from data_sent[%0d]",
      data_sent[i].size(),
      i),
      VERBOSE
    );
    while (data_sent[i].size() > 0) data_sent[i].pop_back();
  end
endtask

task start_acq_with_banking_mode(input int mode);
  start <= 1'b1;
  banking_mode <= mode;
  config_in.valid <= 1'b1;
  @(posedge clk);
  start <= 1'b0;
  config_in.valid <= 1'b0;
endtask

task stop_acq();
  stop <= 1'b1;
  start <= 1'b0;
  config_in.valid <= 1'b1;
  @(posedge clk);
  config_in.valid <= 1'b0;
  start <= 1'b0;
  stop <= 1'b0;
endtask

int samples_to_send;

initial begin
  dbg.display("### testing sample_buffer ###", DEFAULT);
  reset <= 1'b1;
  start <= 1'b0;
  stop <= 1'b0;
  banking_mode <= '0; // only enable channel 0
  data_in.valid <= '0;
  repeat (100) @(posedge clk);
  reset <= 1'b0;
  repeat (50) @(posedge clk);

  for (int in_valid_rand = 0; in_valid_rand < 2; in_valid_rand++) begin
    for (int bank_mode = 0; bank_mode < 4; bank_mode++) begin
      for (int samp_count = 0; samp_count < 3; samp_count++) begin
        start_acq_with_banking_mode(bank_mode);
        unique case (samp_count)
          0: samples_to_send = $urandom_range(4, 10); // a few samples
          1: samples_to_send = ((BUFFER_DEPTH - $urandom_range(2,10)) / (1 << bank_mode))*N_CHANNELS;
          2: samples_to_send = (BUFFER_DEPTH / (1 << bank_mode))*N_CHANNELS; // fill all buffers
        endcase
        data_in.send_samples(clk, samples_to_send, in_valid_rand & 1'b1, 1'b1, 1'b1);
        repeat (10) @(posedge clk);
        stop_acq();
        data_out.do_readout(clk, 1'b1, 100000);
        dbg.display($sformatf("checking results n_samples   = %d", samples_to_send), VERBOSE);
        dbg.display($sformatf("banking mode                 = %d", bank_mode), VERBOSE);
        dbg.display($sformatf("samples sent with rand_valid = %d", in_valid_rand), VERBOSE);
        // The second argument of check_results is if it's okay for there to
        // be missing samples that weren't stored.
        // When data_in.valid is randomly toggled on and off and enough samples
        // are sent to fill up all the banks, one of the banks will likely
        // fill up before the others are done, triggering a stop condition for
        // the other banks before they are full.
        // This results in "missing" samples that aren't saved
        check_results(bank_mode, (samp_count == 2) & (in_valid_rand == 1));
      end
    end
  end

  dbg.finish();
end

endmodule

// test for the individual banks
`timescale 1ns / 1ps
module sample_buffer_bank_test ();

sim_util_pkg::debug #(.VERBOSITY(DEFAULT)) dbg = new; // printing, error tracking

logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

logic reset;

logic start, stop;
logic full;

Axis_If #(.DWIDTH(16)) data_in ();
Axis_If #(.DWIDTH(16)) data_out ();

sample_buffer_bank #(
  .BUFFER_DEPTH(1024),
  .PARALLEL_SAMPLES(2),
  .SAMPLE_WIDTH(16)
) dut_i (
  .clk,
  .reset,
  .data_in,
  .data_out,
  .start,
  .stop,
  .full
);

int sample_count;
logic [15:0] data_sent [$];
logic [15:0] data_received [$];

// send data to DUT and save data that was sent/received
always @(posedge clk) begin
  if (reset) begin
    sample_count <= 0;
    data_in.data <= '0;
  end else begin
    // send data
    if (data_in.valid && data_in.ready) begin
      sample_count <= sample_count + 1;
      data_in.data <= $urandom_range(1<<16);
    end
    // save data that was sent/received
    if (data_in.valid) begin
      data_sent.push_front(data_in.data);
    end
    if (data_out.valid && data_out.ready) begin
      data_received.push_front(data_out.data);
    end
  end
end


// check that the DUT correctly saved everything
task check_results();
  // pop first sample received since it is intended to be overwritten in
  // multibank buffer
  data_received.pop_back();
  dbg.display($sformatf("data_sent.size() = %0d", data_sent.size()), VERBOSE);
  dbg.display($sformatf("data_received.size() = %0d", data_received.size()), VERBOSE);
  if ((data_sent.size() + 1) != data_received.size()) begin
    dbg.error($sformatf(
      "mismatch in amount of sent/received data (sent %0d, received %0d)",
      data_sent.size() + 1,
      data_received.size())
    );
  end
  if (data_received[$] != data_sent.size()) begin
    dbg.error($sformatf(
      "incorrect sample count reported by buffer (sent %0d, reported %0d)",
      data_sent.size(),
      data_received[$])
    );
  end
  data_received.pop_back(); // remove sample count
  while (data_sent.size() > 0 && data_received.size() > 0) begin
    // data from channel 0 can be reordered with data from channel 2
    if (data_sent[$] != data_received[$]) begin
      dbg.error($sformatf(
        "data mismatch error (received %x, sent %x)",
        data_received[$],
        data_sent[$])
      );
    end
    data_sent.pop_back();
    data_received.pop_back();
  end
endtask

initial begin
  dbg.display("### testing sample_buffer_bank ###", DEFAULT);
  reset <= 1'b1;
  start <= 1'b0;
  stop <= 1'b0;
  data_in.valid <= '0;
  repeat (100) @(posedge clk);
  reset <= 1'b0;
  repeat (50) @(posedge clk);
  // start
  start <= 1'b1;
  @(posedge clk);
  start <= 1'b0;
  repeat (100) @(posedge clk);
  // send samples
  data_in.send_samples(clk, 32, 1'b1, 1'b1, 1'b0);
  data_in.send_samples(clk, 64, 1'b0, 1'b1, 1'b0);
  data_in.send_samples(clk, 32, 1'b1, 1'b1, 1'b0);
  repeat (50) @(posedge clk);
  stop <= 1'b1;
  @(posedge clk);
  stop <= 1'b0;
  data_out.do_readout(clk, 1'b1, 100000);
  dbg.display("checking results for test with a few samples", VERBOSE);
  check_results();
  // do more tests

  // test with one sample
  // start
  start <= 1'b1;
  @(posedge clk);
  start <= 1'b0;
  repeat (100) @(posedge clk);
  // send samples
  data_in.send_samples(clk, 1, 1'b0, 1'b1, 1'b0);
  repeat (50) @(posedge clk);
  stop <= 1'b1;
  @(posedge clk);
  stop <= 1'b0;
  data_out.do_readout(clk, 1'b1, 1000);
  dbg.display("checking results for test with one sample", VERBOSE);
  check_results();

  // test with no samples
  // start
  start <= 1'b1;
  @(posedge clk);
  start <= 1'b0;
  repeat (100) @(posedge clk);
  // don't send samples
  repeat (50) @(posedge clk);
  stop <= 1'b1;
  @(posedge clk);
  stop <= 1'b0;
  data_out.do_readout(clk, 1'b1, 1000);
  dbg.display("checking results for test with no samples", VERBOSE);
  check_results();

  // fill up buffer
  // start
  start <= 1'b1;
  @(posedge clk);
  start <= 1'b0;
  repeat (100) @(posedge clk);
  // send samples
  data_in.send_samples(clk, 256, 1'b1, 1'b1, 1'b0);
  data_in.send_samples(clk, 512, 1'b0, 1'b1, 1'b0);
  data_in.send_samples(clk, 256, 1'b1, 1'b1, 1'b0);
  repeat (50) @(posedge clk);
  stop <= 1'b1;
  @(posedge clk);
  stop <= 1'b0;
  data_out.do_readout(clk, 1'b1, 100000);
  dbg.display("checking results for test with 1024 samples (full buffer)", VERBOSE);
  check_results();
  repeat (500) @(posedge clk);
  dbg.finish();
end

endmodule
