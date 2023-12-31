// axis_channel_mux_test.sv - Reed Foster
// Verifies operation of channel multiplexer
// Ignore/don't check data around transients when mux selection is changed
// through config_in interface

import sim_util_pkg::*;

`timescale 1ns / 1ps
module axis_channel_mux_test ();

sim_util_pkg::debug #(.VERBOSITY(DEFAULT)) debug = new; // printing, error tracking

logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

logic reset;

localparam int PARALLEL_SAMPLES = 16;
localparam int SAMPLE_WIDTH = 16;
localparam int CHANNELS = 8;
localparam int FUNCTIONS_PER_CHANNEL = 1;

localparam int SELECT_BITS = $clog2((1+FUNCTIONS_PER_CHANNEL)*CHANNELS);

Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS((1+FUNCTIONS_PER_CHANNEL)*CHANNELS)) data_in ();
Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) data_out ();

Axis_If #(.DWIDTH(CHANNELS*SELECT_BITS)) config_in ();

axis_channel_mux #(
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .CHANNELS(CHANNELS),
  .FUNCTIONS_PER_CHANNEL(FUNCTIONS_PER_CHANNEL)
) dut_i (
  .clk,
  .reset,
  .data_in,
  .data_out,
  .config_in
);

typedef logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] sample_t;
sample_t expected [CHANNELS][$];
sample_t received [CHANNELS][$];

logic [CHANNELS-1:0][SELECT_BITS-1:0] source_select;

always_ff @(posedge clk) begin
  if (reset) begin
    data_in.data <= '0;
    config_in.data <= '0;
  end else begin
    for (int in_channel = 0; in_channel < (1+FUNCTIONS_PER_CHANNEL)*CHANNELS; in_channel++) begin
      if (data_in.valid[in_channel]) begin
        for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
          data_in.data[in_channel][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= $urandom_range(0, {SAMPLE_WIDTH{1'b1}});
        end
      end
    end
    for (int out_channel = 0; out_channel < CHANNELS; out_channel++) begin
      if (config_in.valid) begin
        config_in.data[SELECT_BITS*out_channel+:SELECT_BITS] <= $urandom_range(0, {SELECT_BITS{1'b1}});
        source_select[out_channel] <= config_in.data[SELECT_BITS*out_channel+:SELECT_BITS];
      end
      if (data_out.valid[out_channel]) begin
        received[out_channel].push_front(data_out.data[out_channel]);
      end
      if (data_in.valid[source_select[out_channel]]) begin
        expected[out_channel].push_front(data_in.data[source_select[out_channel]]);
      end
    end
  end
end

task check_results();
  for (int out_channel = 0; out_channel < CHANNELS; out_channel++) begin
    debug.display($sformatf(
      "checking results for channel %d",
      out_channel),
      VERBOSE
    );
    debug.display($sformatf(
      "received[%0d].size() = %0d",
      out_channel,
      received[out_channel].size()),
      VERBOSE
    );
    debug.display($sformatf(
      "expected[%0d].size() = %0d",
      out_channel,
      expected[out_channel].size()),
      VERBOSE
    );
    if (received[out_channel].size() != expected[out_channel].size()) begin
      debug.error($sformatf(
        "mismatched sizes for channel %0d; got %0d samples, expected %0d samples",
        out_channel,
        received[out_channel].size(),
        expected[out_channel].size())
      );
    end
    while (received[out_channel].size() > 0 && expected[out_channel].size() > 0) begin
      if (expected[out_channel][$] !== received[out_channel][$]) begin
        debug.error($sformatf(
          "mismatch: got %x, expected %x",
          received[out_channel][$],
          expected[out_channel][$])
        );
      end
      received[out_channel].pop_back();
      expected[out_channel].pop_back();
    end
  end
endtask

initial begin
  debug.display("### testing axis_channel_mux ###", DEFAULT);
  reset <= 1'b1;
  config_in.data <= '0;
  config_in.valid <= 1'b0;
  data_in.valid <= 1'b0;
  repeat (100) @(posedge clk);
  reset <= 1'b0;
  repeat (100) @(posedge clk);
  // change the configuration a few times
  repeat (5) begin
    data_in.valid <= 1'b0;
    config_in.valid <= 1'b1;
    @(posedge clk);
    config_in.valid <= 1'b0;
    repeat (200) begin
      @(posedge clk);
      data_in.valid <= $urandom();
    end
    data_in.valid <= 1'b1;
    repeat (20) @(posedge clk);
    data_in.valid <= 1'b0;
    repeat (5) @(posedge clk);
    check_results();
  end
  debug.finish();
end

endmodule
