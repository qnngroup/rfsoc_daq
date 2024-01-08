// dac_prescaler_multichannel_test.sv - Reed Foster
// Check that output signal is scaled by the correct amount in steady-state by
// comparing the sent/expected values with the received values. The comparison
// is done at the end of the test by comparing values stored in sytemverilog
// queues.

import sim_util_pkg::*;

`timescale 1ns / 1ps
module dac_prescaler_multichannel_test ();

logic reset;
logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

localparam int SAMPLE_WIDTH = 16;
localparam int PARALLEL_SAMPLES = 16;
localparam int SCALE_WIDTH = 18;
localparam int SAMPLE_FRAC_BITS = 16;
localparam int SCALE_FRAC_BITS = 16;
localparam int CHANNELS = 2;

// signed int types for samples and scale factors
typedef logic signed [SAMPLE_WIDTH-1:0] int_t;
typedef logic signed [SCALE_WIDTH-1:0] sc_int_t;

sim_util_pkg::math #(int_t) math; // abs, max functions on signed sample type
sim_util_pkg::debug debug = new(DEFAULT); // printing, error tracking

Axis_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) data_out_if();
Axis_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) data_in_if();
Axis_If #(.DWIDTH(SCALE_WIDTH*CHANNELS)) scale_factor_if();

logic [CHANNELS-1:0][SCALE_WIDTH-1:0] scale_factor;
assign scale_factor_if.data = scale_factor;
assign scale_factor_if.valid = 1'b1;

real d_in;
real scale;

int_t sent_data [CHANNELS][$];
int_t sent_scale [CHANNELS][$];
int_t expected [CHANNELS][$];
int_t received [CHANNELS][$];

always @(posedge clk) begin
  if (reset) begin
    data_in_if.data <= '0;
  end else begin
    // save data/scale_factor we send, as well as what should be outputted based on the
    // scale factor and sent data
    for (int channel = 0; channel < CHANNELS; channel++) begin
      if (data_in_if.ok[channel]) begin
        for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
          data_in_if.data[channel][i*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= $urandom_range({SAMPLE_WIDTH{1'b1}});
          d_in = real'(int_t'(data_in_if.data[channel][i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
          scale = real'(sc_int_t'(scale_factor[channel]));
          sent_data[channel].push_front(int_t'(data_in_if.data[channel][i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
          sent_scale[channel].push_front(sc_int_t'(scale_factor[channel]));
          expected[channel].push_front(int_t'(d_in/(2.0**SAMPLE_FRAC_BITS) * scale/(2.0**SCALE_FRAC_BITS) * 2.0**SAMPLE_FRAC_BITS));
        end
      end
      // save data we got
      if (data_out_if.ok[channel]) begin
        for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
          received[channel].push_front(int_t'(data_out_if.data[channel][i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
        end
      end
    end
  end
end

task check_results();
  for (int channel = 0; channel < CHANNELS; channel++) begin
    debug.display($sformatf("received[%0d].size() = %0d", channel, received[channel].size()), VERBOSE);
    debug.display($sformatf("expected[%0d].size() = %0d", channel, expected[channel].size()), VERBOSE);
    if (received[channel].size() != expected[channel].size()) begin
      debug.error("mismatched sizes; got a different number of samples than expected");
    end
    // check the values match
    // casting to uint_t seems to perform a rounding operation, so the test data may be slightly too large
    while (received[channel].size() > 0 && expected[channel].size() > 0) begin
      debug.display($sformatf(
        "processing data, scale = %x, sent_data = %x, expected = %x, received = %x",
        sent_scale[channel][$],
        sent_data[channel][$],
        expected[channel][$],
        received[channel][$]),
        DEBUG
      );
      if (math.abs(expected[channel][$] - received[channel][$]) > 1) begin
        debug.error($sformatf(
          "channel %0d mismatch: got %x, expected %x",
          channel,
          received[channel][$],
          expected[channel][$])
        );
      end
      received[channel].pop_back();
      expected[channel].pop_back();
      sent_scale[channel].pop_back();
      sent_data[channel].pop_back();
    end
  end
endtask

dac_prescaler_multichannel #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SCALE_WIDTH(SCALE_WIDTH),
  .SAMPLE_FRAC_BITS(SAMPLE_FRAC_BITS),
  .SCALE_FRAC_BITS(SCALE_FRAC_BITS),
  .CHANNELS(CHANNELS)
) dut_i (
  .clk,
  .reset,
  .data_out(data_out_if),
  .data_in(data_in_if),
  .scale_factor(scale_factor_if)
);

initial begin
  debug.display("### RUNNING TEST FOR DAC_PRESCALER_MULTICHANNEL ###", DEFAULT);
  reset <= 1'b1;
  data_in_if.data <= '0;
  data_in_if.valid <= '0;
  data_out_if.ready <= '0;
  repeat (500) @(posedge clk);
  reset <= 1'b0;
  for (int channel = 0; channel < CHANNELS; channel++) begin
    scale_factor[channel] <= 1 << SCALE_FRAC_BITS;
  end
  repeat(5) @(posedge clk);
  
  // apply backpressure and toggle input data valid
  debug.display("testing with backpressure and random data valid", VERBOSE);
  for (int i = 0; i < 5; i++) begin
    data_in_if.valid <= '0;
    data_out_if.ready <= '1;
    for (int channel = 0; channel < CHANNELS; channel++) begin
      if (i == 0) begin
        scale_factor[channel] <= 1 << SCALE_FRAC_BITS;
      end else begin
        scale_factor[channel] <= $urandom_range(18'h3ffff);
      end
    end
    repeat (5) @(posedge clk);
    repeat (40) begin
      data_in_if.valid <= $urandom_range(0, {CHANNELS{1'b1}});
      data_out_if.ready <= $urandom_range(0, {CHANNELS{1'b1}});
      @(posedge clk);
    end
  end
  // stop sending data and finish reading out anything that is in the pipeline
  data_in_if.valid <= '0;
  data_out_if.ready <= '1;
  repeat (10) @(posedge clk);
  check_results();

  debug.finish();
end

endmodule
