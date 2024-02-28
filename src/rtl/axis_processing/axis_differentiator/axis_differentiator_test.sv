// axis_differentiator_test.sv - Reed Foster
// tests that the output of the axis differentiator module is correct by
// comparing with a behavioral model (implemented with real subtraction in
// systemverilog)

`timescale 1ns / 1ps
module axis_differentiator_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT); // printing, error tracking

localparam int SAMPLE_WIDTH = 16;
localparam int PARALLEL_SAMPLES = 2;

typedef logic signed [SAMPLE_WIDTH-1:0] sample_t; // type for signed samples (needed to check subtraction is working properly)
typedef logic [SAMPLE_WIDTH*PARALLEL_SAMPLES-1:0] batch_t;
sim_util_pkg::math #(.T(sample_t)) math; // abs, max functions on sample_t
sim_util_pkg::queue #(.T(sample_t), .T2(batch_t)) data_q_util = new;
sim_util_pkg::queue #(.T(int)) last_q_util = new;

logic reset;
logic clk = 0;
localparam int CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) data_out_if();
Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) data_in_if();

axis_driver #(
  .DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)
) driver_i (
  .clk,
  .intf(data_in_if)
);

axis_receiver #(
  .DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)
) receiver_i (
  .clk,
  .ready_rand(1'b1),
  .ready_en(1'b1),
  .intf(data_out_if)
);

task automatic sent_to_expected (
  inout batch_t sent [$],
  inout sample_t expected [$]
);
  sample_t sent_split [$];
  sample_t current, prev;
  data_q_util.samples_from_batches(sent, sent_split, SAMPLE_WIDTH, PARALLEL_SAMPLES);
  prev = 0;
  while (sent_split.size() > 0) begin
    current = sent_split.pop_back();
    expected.push_front((current - prev) / 2);
    prev = current;
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

sample_t expected_q [$];
sample_t received_q [$];

initial begin
  debug.display("### TESTING AXIS DIFFERENTIATOR ###", sim_util_pkg::DEFAULT);
  driver_i.init(); // reset last
  reset <= 1'b1;
  repeat (100) @(posedge clk);
  reset <= 1'b0;
  repeat (10) @(posedge clk);
  repeat (100) begin
    driver_i.send_samples(50, 1'b1, 1'b1);
    if ($urandom_range(0,100) < 20) begin
      driver_i.send_last();
    end
  end
  repeat (10) @(posedge clk);
  debug.display("checking data", sim_util_pkg::VERBOSE);
  sent_to_expected(driver_i.data_q, expected_q);
  data_q_util.samples_from_batches(receiver_i.data_q, received_q, SAMPLE_WIDTH, PARALLEL_SAMPLES);
  data_q_util.compare_threshold(debug, received_q, expected_q, 1);
  debug.display("checking last", sim_util_pkg::VERBOSE);
  last_q_util.compare(debug, receiver_i.last_q, driver_i.last_q);
  debug.finish();
end
endmodule
