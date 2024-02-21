// axis_channel_mux_test.sv - Reed Foster
// Verifies operation of channel multiplexer
// Ignore/don't check data around transients when mux selection is changed
// through config_in interface

`timescale 1ns / 1ps
module axis_channel_mux_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT); // printing, error tracking

logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

logic reset;

localparam int PARALLEL_SAMPLES = 16;
localparam int SAMPLE_WIDTH = 16;
localparam int INPUT_CHANNELS = 16;
localparam int OUTPUT_CHANNELS = 8;

typedef logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] sample_t;
sim_util_pkg::queue #(.T(sample_t)) q_util = new;

localparam int SELECT_BITS = $clog2(INPUT_CHANNELS);

Realtime_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(INPUT_CHANNELS)) data_in ();
Realtime_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(OUTPUT_CHANNELS)) data_out ();

Axis_If #(.DWIDTH(OUTPUT_CHANNELS*SELECT_BITS)) config_in ();

axis_channel_mux #(
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .INPUT_CHANNELS(INPUT_CHANNELS),
  .OUTPUT_CHANNELS(OUTPUT_CHANNELS)
) dut_i (
  .clk,
  .reset,
  .data_in,
  .data_out,
  .config_in
);

logic [INPUT_CHANNELS-1:0] valid_en;
realtime_parallel_driver #(
  .DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH),
  .CHANNELS(INPUT_CHANNELS)
) driver_i (
  .clk,
  .reset,
  .valid_rand('1),
  .valid_en,
  .intf(data_in)
);

realtime_parallel_receiver #(
  .DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH),
  .CHANNELS(OUTPUT_CHANNELS)
) receiver_i (
  .clk,
  .intf(data_out)
);

logic [OUTPUT_CHANNELS-1:0][SELECT_BITS-1:0] source_select;

always_ff @(posedge clk) begin
  if (reset) begin
    config_in.data <= '0;
  end else begin
    for (int out_channel = 0; out_channel < OUTPUT_CHANNELS; out_channel++) begin
      if (config_in.ok) begin
        config_in.data[SELECT_BITS*out_channel+:SELECT_BITS] <= $urandom_range(0, {SELECT_BITS{1'b1}});
        source_select[out_channel] <= config_in.data[SELECT_BITS*out_channel+:SELECT_BITS];
      end
    end
  end
end

task automatic check_results(
  input logic [OUTPUT_CHANNELS-1:0][SELECT_BITS-1:0] source_select
);
  int sample_count;
  int selected_input;
  debug.display($sformatf(
    "source_select = %x",
    source_select),
    sim_util_pkg::DEBUG
  );
  for (int out_channel = 0; out_channel < OUTPUT_CHANNELS; out_channel++) begin
    sample_count = 0;
    selected_input = source_select[out_channel];
    debug.display($sformatf(
      "checking data queues for channel %d",
      out_channel),
      sim_util_pkg::VERBOSE
    );
    q_util.compare(debug, receiver_i.data_q[out_channel], driver_i.data_q[selected_input]);
  end
endtask

initial begin
  debug.display("### TESTING AXIS_CHANNEL_MUX ###", sim_util_pkg::DEFAULT);
  reset <= 1'b1;
  config_in.valid <= 1'b0;
  valid_en <= '0;
  repeat (100) @(posedge clk);
  reset <= 1'b0;
  repeat (100) @(posedge clk);
  // change the configuration a few times
  repeat (5) begin
    receiver_i.clear_queues();
    driver_i.clear_queues();
    valid_en <= '0;
    config_in.valid <= 1'b1;
    @(posedge clk);
    config_in.valid <= 1'b0;
    valid_en <= '1;
    repeat (200) begin
      @(posedge clk);
    end
    valid_en <= '0;
    repeat (5) @(posedge clk);
    check_results(source_select);
  end
  debug.finish();
end

endmodule
