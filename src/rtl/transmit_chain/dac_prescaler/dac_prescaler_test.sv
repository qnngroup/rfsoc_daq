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
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

localparam int SAMPLE_WIDTH = 16;
localparam int PARALLEL_SAMPLES = 4;
localparam int CHANNELS = 2;
localparam int SCALE_WIDTH = 18;
localparam int OFFSET_WIDTH = 14;
localparam int SCALE_OFFSET_INT_BITS = 2;

localparam int SCALE_FRAC_BITS = SCALE_WIDTH - SCALE_OFFSET_INT_BITS;
localparam int OFFSET_FRAC_BITS = OFFSET_WIDTH - SCALE_OFFSET_INT_BITS;

// signed int types for samples and scale factors
typedef logic signed [SAMPLE_WIDTH-1:0] int_t;
typedef logic signed [SCALE_WIDTH-1:0] sc_int_t;
typedef logic signed [OFFSET_WIDTH-1:0] os_int_t;

sim_util_pkg::math #(int_t) math; // abs, max functions on signed sample type

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

real d_in;
real scale;
real offset;

int_t sent_data [CHANNELS][$];
sc_int_t sent_scale [CHANNELS][$];
os_int_t sent_offset [CHANNELS][$];
int_t expected [CHANNELS][$];
int_t received [CHANNELS][$];

always @(posedge clk) begin
  if (reset) begin
    data_in_if.data <= '0;
  end else begin
    // save data/scale_factor we send, as well as what should be outputted based on the
    // scale factor and sent data
    for (int channel = 0; channel < CHANNELS; channel++) begin
      if (data_in_if.valid[channel]) begin
        for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
          data_in_if.data[channel][i*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= SAMPLE_WIDTH'($urandom_range({{(32-SAMPLE_WIDTH){1'b0}}, {SAMPLE_WIDTH{1'b1}}}));
          d_in = real'(int_t'(data_in_if.data[channel][i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
          scale = real'(sc_int_t'(scale_factor[channel]));
          offset = real'(os_int_t'(offset_amount[channel]));
          sent_data[channel].push_front(int_t'(data_in_if.data[channel][i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
          sent_scale[channel].push_front(sc_int_t'(scale_factor[channel]));
          sent_offset[channel].push_front(os_int_t'(offset_amount[channel]));
          expected[channel].push_front(int_t'((d_in/(2.0**SAMPLE_WIDTH) * scale/(2.0**SCALE_FRAC_BITS) + offset/(2.0**OFFSET_FRAC_BITS))* 2.0**SAMPLE_WIDTH));
        end
      end
      // save data we got
      if (data_out_if.valid[channel]) begin
        for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
          received[channel].push_front(int_t'(data_out_if.data[channel][i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
        end
      end
    end
  end
end

task check_results();
  for (int channel = 0; channel < CHANNELS; channel++) begin
    debug.display($sformatf(
      "received[%0d].size() = %0d",
      channel,
      received[channel].size()),
      sim_util_pkg::VERBOSE
    );
    debug.display($sformatf(
      "expected[%0d].size() = %0d",
      channel,
      expected[channel].size()),
      sim_util_pkg::VERBOSE
    );
    if (received[channel].size() != expected[channel].size()) begin
      debug.error("mismatched sizes; got a different number of samples than expected");
    end
    // check the values match
    // casting to uint_t seems to perform a rounding operation, so the test data may be slightly too large
    while (received[channel].size() > 0 && expected[channel].size() > 0) begin
      debug.display($sformatf(
        "processing data, scale = %x, offset = %x, sent_data = %x, expected = %x, received = %x",
        sent_scale[channel][$],
        sent_offset[channel][$],
        sent_data[channel][$],
        expected[channel][$],
        received[channel][$]),
        sim_util_pkg::DEBUG
      );
      if (math.abs(expected[channel][$] - received[channel][$]) > 1) begin
        debug.error($sformatf(
          "mismatch: got %x, expected %x",
          received[channel][$],
          expected[channel][$])
        );
      end
      received[channel].pop_back();
      expected[channel].pop_back();
      sent_scale[channel].pop_back();
      sent_offset[channel].pop_back();
      sent_data[channel].pop_back();
    end
  end
endtask

dac_prescaler #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS),
  .SCALE_WIDTH(SCALE_WIDTH),
  .OFFSET_WIDTH(OFFSET_WIDTH),
  .SCALE_OFFSET_INT_BITS(SCALE_OFFSET_INT_BITS)
) dut_i (
  .clk,
  .reset,
  .data_out(data_out_if),
  .data_in(data_in_if),
  .scale_offset(scale_offset_if)
);

initial begin
  debug.display("### RUNNING TEST FOR DAC_PRESCALER ###", sim_util_pkg::DEFAULT);
  reset <= 1'b1;
  data_in_if.data <= '0;
  data_in_if.valid <= '0;
  repeat (500) @(posedge clk);
  reset <= 1'b0;
  for (int channel = 0; channel < CHANNELS; channel++) begin
    scale_factor[channel] <= sc_int_t'($urandom_range(32'h3ffff));
    offset_amount[channel] <= os_int_t'($urandom_range(32'h3fff));
  end
  repeat(5) @(posedge clk);

  // send a bunch of data with no backpressure
  debug.display("testing without backpressure and random data valid", sim_util_pkg::VERBOSE);
  repeat (5) begin
    // don't send any data while we're changing scale factor
    data_in_if.valid <= '0;
    for (int channel = 0; channel < CHANNELS; channel++) begin
      scale_factor[channel] <= sc_int_t'($urandom_range(32'h3ffff));
      offset_amount[channel] <= os_int_t'($urandom_range(32'h3fff));
    end
    repeat (5) @(posedge clk);
    data_in_if.send_samples(clk, 20, 1'b0, 1'b1);
    repeat (50) @(posedge clk);
    data_in_if.send_samples(clk, 20, 1'b1, 1'b1);
    repeat (50) @(posedge clk);
  end
  // stop sending data and finish reading out anything that is in the pipeline
  data_in_if.valid <= '0;
  repeat (10) @(posedge clk);
  check_results();

  debug.finish();
end

endmodule
