// sample_buffer_bank_test.sv - Reed Foster
// test for the individual banks

import sim_util_pkg::*;

`timescale 1ns / 1ps
module sample_buffer_bank_test ();

sim_util_pkg::debug debug = new(DEFAULT); // printing, error tracking

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
int last_received [$];

// send data to DUT and save data that was sent/received
always @(posedge clk) begin
  if (reset) begin
    sample_count <= 0;
    data_in.data <= '0;
  end else begin
    // send data
    if (data_in.ok) begin
      sample_count <= sample_count + 1;
      data_in.data <= $urandom_range(1<<16);
    end
    // save data that was sent/received
    if (data_in.ok) begin
      data_sent.push_front(data_in.data);
    end
    if (data_out.ok) begin
      data_received.push_front(data_out.data);
      if (data_out.last) begin
        last_received.push_front(data_received.size());
      end
    end
  end
end


// check that the DUT correctly saved everything
task check_results();
  // check last is the right size
  if (last_received.size() !== 1) begin
    debug.error($sformatf("expected exactly one tlast event, got %0d", last_received.size()));
  end else begin
    if (last_received[$] != data_sent.size() + 2) begin
      debug.error($sformatf("expected last on sample %0d, got it on %0d", data_sent.size() + 2, last_received[$]));
    end
  end
  while (last_received.size() > 0) last_received.pop_back();
  // pop first sample received since it is intended to be overwritten in
  // multibank buffer
  data_received.pop_back();
  debug.display($sformatf("data_sent.size() = %0d", data_sent.size()), VERBOSE);
  debug.display($sformatf("data_received.size() = %0d", data_received.size()), VERBOSE);
  if ((data_sent.size() + 1) != data_received.size()) begin
    debug.error($sformatf(
      "mismatch in amount of sent/received data (sent %0d, received %0d)",
      data_sent.size() + 1,
      data_received.size())
    );
  end
  if (data_received[$] != data_sent.size()) begin
    debug.error($sformatf(
      "incorrect sample count reported by buffer (sent %0d, reported %0d)",
      data_sent.size(),
      data_received[$])
    );
  end
  data_received.pop_back(); // remove sample count
  while (data_sent.size() > 0 && data_received.size() > 0) begin
    // data from channel 0 can be reordered with data from channel 2
    if (data_sent[$] != data_received[$]) begin
      debug.error($sformatf(
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
  debug.display("### TESTING SAMPLE_BUFFER_BANK ###", DEFAULT);
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
  data_in.send_samples(clk, 32, 1'b1, 1'b1);
  data_in.send_samples(clk, 64, 1'b0, 1'b1);
  data_in.send_samples(clk, 32, 1'b1, 1'b1);
  repeat (50) @(posedge clk);
  stop <= 1'b1;
  @(posedge clk);
  stop <= 1'b0;
  data_out.do_readout(clk, 1'b1, 100000);
  debug.display("checking results for test with a few samples", VERBOSE);
  check_results();
  // do more tests

  // test with one sample
  // start
  start <= 1'b1;
  @(posedge clk);
  start <= 1'b0;
  repeat (100) @(posedge clk);
  // send samples
  data_in.send_samples(clk, 1, 1'b0, 1'b1);
  repeat (50) @(posedge clk);
  stop <= 1'b1;
  @(posedge clk);
  stop <= 1'b0;
  data_out.do_readout(clk, 1'b1, 1000);
  debug.display("checking results for test with one sample", VERBOSE);
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
  debug.display("checking results for test with no samples", VERBOSE);
  check_results();

  // fill up buffer
  // start
  start <= 1'b1;
  @(posedge clk);
  start <= 1'b0;
  repeat (100) @(posedge clk);
  // send samples
  data_in.send_samples(clk, 256, 1'b1, 1'b1);
  data_in.send_samples(clk, 512, 1'b0, 1'b1);
  data_in.send_samples(clk, 256, 1'b1, 1'b1);
  repeat (50) @(posedge clk);
  stop <= 1'b1;
  @(posedge clk);
  stop <= 1'b0;
  data_out.do_readout(clk, 1'b1, 100000);
  debug.display("checking results for test with 1024 samples (full buffer)", VERBOSE);
  check_results();
  repeat (500) @(posedge clk);
  debug.finish();
end

endmodule
