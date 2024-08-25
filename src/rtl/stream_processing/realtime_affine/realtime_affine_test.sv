// realtime_affine_test.sv - Reed Foster
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
module realtime_affine_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT); // printing, error tracking

logic data_reset;
logic data_clk = 0;
localparam int DATA_CLK_RATE_HZ = 256_000_000;
always #(0.5s/DATA_CLK_RATE_HZ) data_clk = ~data_clk;

logic config_reset;
logic config_clk = 0;
localparam int CONFIG_CLK_RATE_HZ = 100_000_000;
always #(0.5s/CONFIG_CLK_RATE_HZ) config_clk = ~config_clk;

localparam int SAMPLE_WIDTH = 16;
localparam int PARALLEL_SAMPLES = 4;
localparam int CHANNELS = 2;
localparam int SCALE_WIDTH = 18;
localparam int OFFSET_WIDTH = 14;
localparam int SCALE_INT_BITS = 2;

localparam int CONFIG_WIDTH = CHANNELS*(SCALE_WIDTH+OFFSET_WIDTH);

Realtime_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) data_out ();
Realtime_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) data_in ();
Axis_If #(.DWIDTH(CONFIG_WIDTH)) config_scale_offset ();

realtime_affine_tb #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS),
  .SCALE_WIDTH(SCALE_WIDTH),
  .OFFSET_WIDTH(OFFSET_WIDTH),
  .SCALE_INT_BITS(SCALE_INT_BITS)
) tb_i (
  .data_clk,
  .data_reset,
  .data_out,
  .data_in,
  .config_clk,
  .config_reset,
  .config_scale_offset
);

realtime_affine #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS),
  .SCALE_WIDTH(SCALE_WIDTH),
  .OFFSET_WIDTH(OFFSET_WIDTH),
  .SCALE_INT_BITS(SCALE_INT_BITS)
) dut_i (
  .data_clk,
  .data_reset,
  .data_out,
  .data_in,
  .config_clk,
  .config_reset,
  .config_scale_offset
);

initial begin
  debug.display("### RUNNING TEST FOR REALTIME_AFFINE ###", sim_util_pkg::DEFAULT);
  tb_i.init();
  config_reset <= 1'b1;
  data_reset <= 1'b1;
  repeat (100) @(posedge config_clk);
  config_reset <= 1'b0;
  @(posedge data_clk);
  data_reset <= 1'b0;
  repeat(5) @(posedge data_clk);

  repeat (50) begin
    // send_data = 0 -> don't send any data while we're changing scale factor
    tb_i.update_scale_offset(debug);
    // wait for data to get CDC'd
    repeat (100) @(posedge config_clk);
    tb_i.send_data();
    tb_i.check_output(debug);
    tb_i.clear_queues();
  end

  debug.finish();
end

endmodule
