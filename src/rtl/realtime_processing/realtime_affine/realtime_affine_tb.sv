// realtime_affine_tb.sv
// testbench to interface with realtime_affine module

`timescale 1ns / 1ps
module realtime_affine_tb #(
  parameter int SAMPLE_WIDTH = 16,
  parameter int PARALLEL_SAMPLES = 16,
  parameter int CHANNELS = 8,
  parameter int SCALE_WIDTH = 18,
  parameter int OFFSET_WIDTH = 14,
  parameter int SCALE_INT_BITS = 2
) (
  input logic data_clk, data_reset,
  Realtime_Parallel_If.Slave data_out,
  Realtime_Parallel_If.Master data_in,
  input logic config_clk, config_reset,
  Axis_If.Master config_scale_offset // {CHANNELS{2Q16 scale, 0Q14 offset}}
);

localparam int CONFIG_WIDTH = CHANNELS*(SCALE_WIDTH+OFFSET_WIDTH);
localparam int SCALE_FRAC_BITS = SCALE_WIDTH - SCALE_INT_BITS;

// signed int types for samples and scale factors
typedef logic signed [SAMPLE_WIDTH-1:0] int_t;
typedef logic signed [SCALE_WIDTH-1:0] sc_int_t;
typedef logic signed [OFFSET_WIDTH-1:0] os_int_t;

typedef logic [SAMPLE_WIDTH*PARALLEL_SAMPLES-1:0] batch_t;

sim_util_pkg::math #(int_t) math; // abs, max functions on signed sample type
sim_util_pkg::queue #(.T(int_t), .T2(batch_t)) data_q_util = new;

sc_int_t scale_factor [CHANNELS];
os_int_t offset_amount [CHANNELS];

axis_driver #(
  .DWIDTH(CONFIG_WIDTH)
) config_driver_i (
  .clk(config_clk),
  .intf(config_scale_offset)
);

logic data_enable;
realtime_parallel_driver #(
  .DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) driver_i (
  .clk(data_clk),
  .reset(data_reset),
  .valid_rand('1),
  .valid_en({CHANNELS{data_enable}}),
  .intf(data_in)
);

realtime_parallel_receiver #(
  .DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) receiver_i (
  .clk(data_clk),
  .intf(data_out)
);

task automatic init ();
  data_enable <= 1'b0;
  config_driver_i.init();
endtask

task automatic clear_queues ();
  driver_i.clear_queues();
  receiver_i.clear_queues();
endtask

task automatic send_data ();
  repeat (5) @(posedge data_clk);
  data_enable <= 1'b1;
  repeat (1000) @(posedge data_clk);
  data_enable <= 1'b0;
  repeat (10) @(posedge data_clk);
endtask

task automatic update_scale_offset (
  sim_util_pkg::debug debug
);
  logic [CONFIG_WIDTH-1:0] config_data;
  logic success;
  for (int channel = 0; channel < CHANNELS; channel++) begin
    scale_factor[channel] = sc_int_t'($urandom_range(32'h3ffff));
    offset_amount[channel] = os_int_t'($urandom_range(32'h3fff));
  end
  for (int channel = 0; channel < CHANNELS; channel++) begin
    config_data[channel*(SCALE_WIDTH+OFFSET_WIDTH)+:(SCALE_WIDTH+OFFSET_WIDTH)] = {scale_factor[channel], offset_amount[channel]};
  end
    config_driver_i.send_sample_with_timeout(10, config_data, success);
    if (~success) begin
      debug.error("failed to set scale/offset");
    end
endtask

task automatic sent_to_expected (
  inout batch_t sent [$],
  inout int_t expected [$],
  input real scale,
  input real offset
);
  real d_in;
  int_t sent_split [$];
  data_q_util.samples_from_batches(sent, sent_split, SAMPLE_WIDTH, PARALLEL_SAMPLES);
  while (sent_split.size() > 0) begin
    d_in = real'(sent_split.pop_back());
    expected.push_front(int_t'((d_in/(2.0**SAMPLE_WIDTH) * scale/(2.0**SCALE_FRAC_BITS) + offset/(2.0**OFFSET_WIDTH))* 2.0**SAMPLE_WIDTH));
  end
endtask

task automatic check_output (
  sim_util_pkg::debug debug
);
  int_t expected_q [$];
  int_t received_q [$];
  for (int channel = 0; channel < CHANNELS; channel++) begin
    debug.display($sformatf("ch %0d: checking data", channel), sim_util_pkg::VERBOSE);
    sent_to_expected(driver_i.data_q[channel], expected_q, real'(scale_factor[channel]), real'(offset_amount[channel]));
    data_q_util.samples_from_batches(receiver_i.data_q[channel], received_q, SAMPLE_WIDTH, PARALLEL_SAMPLES);
    data_q_util.compare_threshold(debug, received_q, expected_q, 1);
    while (expected_q.size() > 0) expected_q.pop_back();
    while (received_q.size() > 0) received_q.pop_back();
  end
endtask

endmodule
