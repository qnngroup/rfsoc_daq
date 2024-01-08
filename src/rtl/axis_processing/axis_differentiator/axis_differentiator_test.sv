// axis_differentiator_test.sv - Reed Foster
// tests that the output of the axis differentiator module is correct by
// comparing with a behavioral model (implemented with real subtraction in
// systemverilog)

import sim_util_pkg::*;

`timescale 1ns / 1ps
module axis_differentiator_test ();

localparam int SAMPLE_WIDTH = 16;
localparam int PARALLEL_SAMPLES = 2;

typedef logic signed [SAMPLE_WIDTH-1:0] int_t; // type for signed samples (needed to check subtraction is working properly)
sim_util_pkg::math #(int_t) math; // abs, max functions on int_t
sim_util_pkg::debug debug = new(DEFAULT); // printing, error tracking

logic reset;
logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) data_out_if();
Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) data_in_if();

// Save sent, expected, and actual data in queues to be processed at the end
// of the test. Using a queue eliminates the need to account for latency in
// the test (assuming that all of the data that is sent to the module can be
// read out without sending new data; i.e. data_in.valid can be held low for
// a few cycles to empty the processing pipeline)
real d_in;
int_t received[$];
int_t expected[$];
int_t sent[$]; // only really used for debugging purposes

always @(posedge clk) begin
  if (reset) begin
    data_in_if.data <= '0;
  end else begin
    // send data
    if (data_in_if.ok) begin
      for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
        data_in_if.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= $urandom_range({SAMPLE_WIDTH{1'b1}});
        sent.push_front(int_t'(data_in_if.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
        if (sent.size() > 1) begin
          // if we've sent more than one sample, then just compute the
          // difference of the currently-being-sent sample with the
          // previously-sent sample
          expected.push_front((sent[0] - sent[1]) / 2);
        end else begin
          // if this is the first sample, then the module will default to just
          // sending that sample (i.e. it assumes the previous sample was zero)
          expected.push_front(sent[0] / 2);
        end
      end
    end
    // receive data
    if (data_out_if.ok) begin
      for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
        received.push_front(int_t'(data_out_if.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
      end
    end
  end
end

task check_results();
  debug.display($sformatf("received.size() = %0d", received.size()), VERBOSE);
  debug.display($sformatf("expected.size() = %0d", expected.size()), VERBOSE);
  if (received.size() != expected.size()) begin
    debug.error("mismatched sizes; got a different number of samples than expected");
  end
  // check the values match, like with axis_x2_test, the rounding during
  // type-casting could lead to an off-by-one error, so just make sure that
  // we're within 1 LSB of the expected result
  while (received.size() > 0 && expected.size() > 0) begin
    if (math.abs(expected[$] - received[$]) > 1) begin
      debug.error($sformatf("mismatch: got %x, expected %x", received[$], expected[$]));
    end
    received.pop_back();
    expected.pop_back();
  end
endtask

axis_differentiator #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES)
) dut_i (
  .clk,
  .reset,
  .data_in(data_in_if),
  .data_out(data_out_if)
);

initial begin
  debug.display("### TESTING AXIS DIFFERENTIATOR ###", DEFAULT);
  reset <= 1'b1;
  data_in_if.valid <= 1'b0;
  data_out_if.ready <= 1'b1;
  repeat (100) @(posedge clk);
  reset <= 1'b0;
  // randomize ready and valid signals
  repeat (2000) begin
    @(posedge clk);
    data_in_if.valid <= $urandom() & 1'b1;
    data_out_if.ready <= $urandom() & 1'b1;
  end
  @(posedge clk);
  data_out_if.ready <= 1'b1;
  data_in_if.valid <= 1'b0;
  repeat (10) @(posedge clk);
  check_results();
  debug.finish();
end
endmodule
