// realtime_differentiator_tb.sv - Reed Foster
// computes first-order finite difference to approximate time derivative of
// input signal

`timescale 1ns/1ps
module realtime_differentiator_tb #(
  parameter int SAMPLE_WIDTH = 16,
  parameter int PARALLEL_SAMPLES = 2,
  parameter int CHANNELS = 8
) (
  input wire clk, reset,
  Realtime_Parallel_If.Master data_in,
  Realtime_Parallel_If.Slave data_out
);

typedef logic signed [SAMPLE_WIDTH-1:0] sample_t; // type for signed samples (needed to check subtraction is working properly)
typedef logic [SAMPLE_WIDTH*PARALLEL_SAMPLES-1:0] batch_t;
sim_util_pkg::math #(.T(sample_t)) math; // abs, max functions on sample_t
sim_util_pkg::queue #(.T(sample_t), .T2(batch_t)) data_q_util = new;
sim_util_pkg::queue #(.T(int)) last_q_util = new;

logic data_enable;
realtime_parallel_driver #(
  .DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) driver_i (
  .clk,
  .reset,
  .valid_rand('1),
  .valid_en({CHANNELS{data_enable}}),
  .intf(data_in)
);

realtime_parallel_receiver #(
  .DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) receiver_i (
  .clk,
  .intf(data_out)
);

task automatic init ();
  data_enable <= 1'b0;
endtask

task automatic clear_queues ();
  driver_i.clear_queues();
  receiver_i.clear_queues();
endtask

task automatic send_data ();
  repeat (5) @(posedge clk);
  data_enable <= 1'b1;
  repeat (1000) @(posedge clk);
  data_enable <= 1'b0;
  repeat (10) @(posedge clk);
endtask

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

task automatic check_output (
  inout sim_util_pkg::debug debug
);
  sample_t expected_q [$];
  sample_t received_q [$];
  for (int channel = 0; channel < CHANNELS; channel++) begin
    debug.display($sformatf("ch %0d: checking data", channel), sim_util_pkg::VERBOSE);
    sent_to_expected(driver_i.data_q[channel], expected_q);
    data_q_util.samples_from_batches(receiver_i.data_q[channel], received_q, SAMPLE_WIDTH, PARALLEL_SAMPLES);
    // trim trailing samples from expected since we probably didn't get the
    // last few samples
    while ((expected_q.size() > received_q.size()) && (expected_q.size() > 0)) begin
      expected_q.pop_front();
    end
    data_q_util.compare_threshold(debug, received_q, expected_q, 1);
    while (expected_q.size() > 0) expected_q.pop_back();
    while (received_q.size() > 0) received_q.pop_back();
  end
endtask


endmodule
