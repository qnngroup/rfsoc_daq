// dac_prescaler_test.sv - Reed Foster
// Check that output signal is scaled by the correct amount in steady-state by
// comparing the sent/expected values with the received values. The comparison
// is done at the end of the test by comparing values stored in sytemverilog
// queues.
// ***NOTE***
// Does not verify correct transient behavior when the scale factor is changed
// (since the scale factor change is not intended to be varied dynamically)
// This would be relatively straightforward to implement if the input were
// constrained to be continuous (i.e. valid = 1 always), but for discontinous
// valid input data, tracking when the scale factor changes is a little tricky

`timescale 1ns / 1ps
module dac_prescaler_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT); // printing, error tracking

logic reset;
logic clk = 0;
localparam int CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

localparam int SAMPLE_WIDTH = 16;
localparam int PARALLEL_SAMPLES = 4;
localparam int CHANNELS = 2;
localparam int SCALE_WIDTH = 18;
localparam int OFFSET_WIDTH = 14;
localparam int SCALE_INT_BITS = 2;

localparam int SCALE_FRAC_BITS = SCALE_WIDTH - SCALE_INT_BITS;

// signed int types for samples and scale factors
typedef logic signed [SAMPLE_WIDTH-1:0] int_t;
typedef logic signed [SCALE_WIDTH-1:0] sc_int_t;
typedef logic signed [OFFSET_WIDTH-1:0] os_int_t;

sim_util_pkg::math #(int_t) math; // abs, max functions on signed sample type
typedef logic [SAMPLE_WIDTH*PARALLEL_SAMPLES-1:0] batch_t;
sim_util_pkg::queue #(.T(int_t), .T2(batch_t)) data_q_util = new;

Realtime_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) data_out_if();
Realtime_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) data_in_if();
Axis_If #(.DWIDTH((SCALE_WIDTH+OFFSET_WIDTH)*CHANNELS)) scale_offset_if();

sc_int_t scale_factor [CHANNELS];
os_int_t offset_amount [CHANNELS];
always_comb begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    scale_offset_if.data[channel*(SCALE_WIDTH+OFFSET_WIDTH)+:(SCALE_WIDTH+OFFSET_WIDTH)] = {scale_factor[channel], offset_amount[channel]};
  end
end
assign scale_offset_if.valid = 1'b1;

logic send_data;
realtime_parallel_driver #(
  .DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) driver_i (
  .clk,
  .reset,
  .valid_rand(1'b1),
  .valid_en({CHANNELS{send_data}}),
  .intf(data_in_if)
);

realtime_parallel_receiver #(
  .DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) receiver_i (
  .clk,
  .intf(data_out_if)
);

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

dac_prescaler #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS),
  .SCALE_WIDTH(SCALE_WIDTH),
  .OFFSET_WIDTH(OFFSET_WIDTH),
  .SCALE_INT_BITS(SCALE_INT_BITS)
) dut_i (
  .clk,
  .reset,
  .data_out(data_out_if),
  .data_in(data_in_if),
  .scale_offset(scale_offset_if)
);

int_t expected_q [$];
int_t received_q [$];

initial begin
  debug.display("### RUNNING TEST FOR DAC_PRESCALER ###", sim_util_pkg::DEFAULT);
  reset <= 1'b1;
  repeat (500) @(posedge clk);
  reset <= 1'b0;
  repeat(5) @(posedge clk);

  repeat (50) begin
    // send_data = 0 -> don't send any data while we're changing scale factor
    for (int channel = 0; channel < CHANNELS; channel++) begin
      scale_factor[channel] <= sc_int_t'($urandom_range(32'h3ffff));
      offset_amount[channel] <= os_int_t'($urandom_range(32'h3fff));
    end
    repeat (5) @(posedge clk);
    send_data <= 1'b1;
    repeat (1000) @(posedge clk);
    send_data <= 1'b0;
    repeat (10) @(posedge clk);
    for (int channel = 0; channel < CHANNELS; channel++) begin
      debug.display($sformatf("ch %0d: checking data", channel), sim_util_pkg::VERBOSE);
      sent_to_expected(driver_i.data_q[channel], expected_q, real'(scale_factor[channel]), real'(offset_amount[channel]));
      data_q_util.samples_from_batches(receiver_i.data_q[channel], received_q, SAMPLE_WIDTH, PARALLEL_SAMPLES);
      data_q_util.compare_threshold(debug, received_q, expected_q, 1);
      while (expected_q.size() > 0) expected_q.pop_back();
      while (received_q.size() > 0) received_q.pop_back();
    end
    driver_i.clear_queues();
    receiver_i.clear_queues();
  end

  debug.finish();
end

endmodule
