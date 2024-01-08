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

import sim_util_pkg::*;

`timescale 1ns / 1ps
module dac_prescaler_test ();

logic reset;
logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

localparam int SAMPLE_WIDTH = 16;
localparam int PARALLEL_SAMPLES = 16;
localparam int SCALE_WIDTH = 18;
localparam int SAMPLE_FRAC_BITS = 16;
localparam int SCALE_FRAC_BITS = 16;

// signed int types for samples and scale factors
typedef logic signed [SAMPLE_WIDTH-1:0] int_t;
typedef logic signed [SCALE_WIDTH-1:0] sc_int_t;

sim_util_pkg::math #(int_t) math; // abs, max functions on signed sample type
sim_util_pkg::debug debug = new(DEFAULT); // printing, error tracking

Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) data_out_if();
Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) data_in_if();
Axis_If #(.DWIDTH(SCALE_WIDTH)) scale_factor_if();

sc_int_t scale_factor;
assign scale_factor_if.data = scale_factor;
assign scale_factor_if.valid = 1'b1;

real d_in;
real scale;

int_t sent_data [$];
int_t sent_scale [$];
int_t expected [$];
int_t received [$];

always @(posedge clk) begin
  if (reset) begin
    data_in_if.data <= '0;
  end else begin
    // save data/scale_factor we send, as well as what should be outputted based on the
    // scale factor and sent data
    if (data_in_if.ok) begin
      for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
        data_in_if.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= $urandom_range({SAMPLE_WIDTH{1'b1}});
        d_in = real'(int_t'(data_in_if.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
        scale = real'(sc_int_t'(scale_factor));
        sent_data.push_front(int_t'(data_in_if.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
        sent_scale.push_front(sc_int_t'(scale_factor));
        expected.push_front(int_t'(d_in/(2.0**SAMPLE_FRAC_BITS) * scale/(2.0**SCALE_FRAC_BITS) * 2.0**SAMPLE_FRAC_BITS));
      end
    end
    // save data we got
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
  // casting to uint_t seems to perform a rounding operation, so the test data may be slightly too large
  while (received.size() > 0 && expected.size() > 0) begin
    debug.display($sformatf(
      "processing data, scale = %x, sent_data = %x, expected = %x, received = %x",
      sent_scale[$],
      sent_data[$],
      expected[$],
      received[$]),
      DEBUG
    );
    if (math.abs(expected[$] - received[$]) > 1) begin
      debug.error($sformatf(
        "mismatch: got %x, expected %x",
        received[$],
        expected[$])
      );
    end
    received.pop_back();
    expected.pop_back();
    sent_scale.pop_back();
    sent_data.pop_back();
  end
endtask

dac_prescaler #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SCALE_WIDTH(SCALE_WIDTH),
  .SAMPLE_FRAC_BITS(SAMPLE_FRAC_BITS),
  .SCALE_FRAC_BITS(SCALE_FRAC_BITS)
) dut_i (
  .clk,
  .reset,
  .data_out(data_out_if),
  .data_in(data_in_if),
  .scale_factor(scale_factor_if)
);

initial begin
  debug.display("### RUNNING TEST FOR DAC_PRESCALER ###", DEFAULT);
  reset <= 1'b1;
  data_in_if.data <= '0;
  data_in_if.valid <= 1'b0;
  data_out_if.ready <= 1'b0;
  repeat (500) @(posedge clk);
  reset <= 1'b0;
  scale_factor <= $urandom_range(18'h3ffff);
  repeat(5) @(posedge clk);

  // send a bunch of data with no backpressure
  debug.display("testing without backpressure and random data valid", VERBOSE);
  data_out_if.ready <= 1'b1;
  repeat (5) begin
    // don't send any data while we're changing scale factor
    data_in_if.valid <= 1'b0;
    scale_factor <= $urandom_range(18'h3ffff);
    repeat (5) @(posedge clk);
    data_in_if.send_samples(clk, 20, 1'b0, 1'b1, 1'b0);
    repeat (50) @(posedge clk);
    data_in_if.send_samples(clk, 20, 1'b1, 1'b1, 1'b0);
    repeat (50) @(posedge clk);
  end
  // stop sending data and finish reading out anything that is in the pipeline
  data_in_if.valid <= 1'b0;
  data_out_if.ready <= 1'b1;
  repeat (10) @(posedge clk);
  check_results();

  // apply backpressure with input data always valid
  debug.display("testing with backpressure and continuous data valid", VERBOSE);
  repeat (5) begin
    data_in_if.valid <= 1'b0;
    data_out_if.ready <= 1'b1;
    scale_factor <= $urandom_range(18'h3ffff);
    repeat (5) @(posedge clk);
    data_in_if.valid <= 1'b1;
    repeat (40) begin
      data_out_if.ready <= $urandom() & 1'b1;
      @(posedge clk);
    end
  end
  // stop sending data and finish reading out anything that is in the pipeline
  data_in_if.valid <= 1'b0;
  data_out_if.ready <= 1'b1;
  repeat (10) @(posedge clk);
  check_results();


  // apply backpressure and toggle input data valid
  debug.display("testing with backpressure and random data valid", VERBOSE);
  repeat (5) begin
    data_in_if.valid <= 1'b0;
    data_out_if.ready <= 1'b1;
    scale_factor <= $urandom_range(18'h3ffff);
    repeat (5) @(posedge clk);
    repeat (40) begin
      data_in_if.valid <= $urandom() & 1'b1;
      data_out_if.ready <= $urandom() & 1'b1;
      @(posedge clk);
    end
  end
  // stop sending data and finish reading out anything that is in the pipeline
  data_in_if.valid <= 1'b0;
  data_out_if.ready <= 1'b1;
  repeat (10) @(posedge clk);
  check_results();

  debug.finish();
end

endmodule
