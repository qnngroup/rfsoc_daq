// axis_x2_test.sv - Reed Foster
// Check that output axi-stream interface is producing a stream of samples that
// are the squares of the input axi-stream samples
// Saves all expected/received samples in queues and compares the input/output
// at the end of the test to verify operation. Computes expected quantities
// using systemverilog multiplication with reals and typecasting.

import sim_util_pkg::*;

`timescale 1ns / 1ps
module axis_x2_test ();

typedef logic signed [SAMPLE_WIDTH-1:0] int_t;
sim_util_pkg::math #(int_t) math; // abs, max functions on signed sample type
sim_util_pkg::debug debug = new(DEFAULT); // printing, error tracking

logic reset;
logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

localparam int SAMPLE_WIDTH = 16;
localparam int PARALLEL_SAMPLES = 2;
localparam int SAMPLE_FRAC_BITS = 14;
localparam int SAMPLE_INT_BITS = SAMPLE_WIDTH - SAMPLE_FRAC_BITS;

Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) data_out_if();
Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) data_in_if();

real d_in;
int_t received[$];
int_t expected[$];

always @(posedge clk) begin
  if (reset) begin
    data_in_if.data <= '0;
  end else begin
    // send data
    if (data_in_if.ok) begin
      for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
        data_in_if.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= $urandom_range({SAMPLE_WIDTH{1'b1}});
        d_in = real'(int_t'(data_in_if.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
        expected.push_front(int_t'(((d_in/(2.0**SAMPLE_FRAC_BITS))**2) * 2.0**(SAMPLE_WIDTH - 2*SAMPLE_INT_BITS)));
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
  // check the values match
  // casting to uint_t seems to perform a rounding operation, so just make
  // sure we're within 1 LSB of the expected result
  while (received.size() > 0 && expected.size() > 0) begin
    if (math.abs(expected[$] - received[$]) > 1) begin
      debug.error($sformatf(
        "mismatch: got %x, expected %x",
        received[$],
        expected[$])
      );
    end
    received.pop_back();
    expected.pop_back();
  end
endtask

axis_x2 #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_FRAC_BITS(SAMPLE_FRAC_BITS)
) dut_i (
  .clk,
  .reset,
  .data_in(data_in_if),
  .data_out(data_out_if)
);

initial begin
  debug.display("### TESTING AXIS X^2 ###", DEFAULT);
  reset <= 1'b1;
  data_in_if.valid <= 1'b0;
  data_out_if.ready <= 1'b1;
  repeat (100) @(posedge clk);
  reset <= 1'b0;
  // randomly toggle input valid and output ready
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
