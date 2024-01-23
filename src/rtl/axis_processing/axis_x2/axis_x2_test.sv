// axis_x2_test.sv - Reed Foster
// Check that output axi-stream interface is producing a stream of samples that
// are the squares of the input axi-stream samples
// Saves all expected/received samples in queues and compares the input/output
// at the end of the test to verify operation. Computes expected quantities
// using systemverilog multiplication with reals and typecasting.

`timescale 1ns / 1ps
module axis_x2_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT); // printing, error tracking

logic reset;
logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

localparam int SAMPLE_WIDTH = 16;
localparam int PARALLEL_SAMPLES = 2;
localparam int SAMPLE_FRAC_BITS = 14;
localparam int SAMPLE_INT_BITS = SAMPLE_WIDTH - SAMPLE_FRAC_BITS;

typedef logic signed [SAMPLE_WIDTH-1:0] sample_t;
sim_util_pkg::math #(sample_t) math; // abs, max functions on signed sample type

Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) data_out_if();
Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) data_in_if();

real d_in;
sample_t received[$];
sample_t expected[$];
int last_expected[$];
int last_received[$];

always @(posedge clk) begin
  if (reset) begin
    data_in_if.data <= '0;
  end else begin
    // send data
    if (data_in_if.ok) begin
      for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
        data_in_if.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= $urandom_range({SAMPLE_WIDTH{1'b1}});
        d_in = real'(sample_t'(data_in_if.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
        expected.push_front(sample_t'(((d_in/(2.0**SAMPLE_FRAC_BITS))**2) * 2.0**(SAMPLE_WIDTH - 2*SAMPLE_INT_BITS)));
      end
      if (data_in_if.last) begin
        last_expected.push_front(expected.size());
      end
    end
    // receive data
    if (data_out_if.ok) begin
      for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
        received.push_front(sample_t'(data_out_if.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
      end
      if (data_out_if.last) begin
        last_received.push_front(received.size());
      end
    end
  end
end

task check_results();
  debug.display($sformatf("received.size() = %0d", received.size()), sim_util_pkg::VERBOSE);
  debug.display($sformatf("expected.size() = %0d", expected.size()), sim_util_pkg::VERBOSE);
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
  debug.display($sformatf("last_received.size() = %0d", last_received.size()), sim_util_pkg::VERBOSE);
  debug.display($sformatf("last_expected.size() = %0d", last_expected.size()), sim_util_pkg::VERBOSE);
  if (last_expected.size() != last_received.size()) begin
    debug.error($sformatf(
      "mismatched number of last signals: got %0d, expected %0d",
      last_received.size(),
      last_expected.size())
    );
  end
  while (last_expected.size() > 0) begin
    if (last_expected[$] !== last_received[$]) begin
      debug.error($sformatf("last mismatch: got %0d, expected %0d", last_received[$], last_expected[$]));
    end
    last_expected.pop_back();
    last_received.pop_back();
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
  debug.display("### TESTING AXIS X^2 ###", sim_util_pkg::DEFAULT);
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
