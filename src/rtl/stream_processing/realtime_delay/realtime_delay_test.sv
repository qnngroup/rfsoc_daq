// realtime_delay_test.sv - Reed Foster

`timescale 1ns / 1ps
module realtime_delay_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT); // printing, error tracking

localparam int DATA_WIDTH = 16;
localparam int CHANNELS = 4;

logic reset;
logic clk = 0;
localparam int CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

Realtime_Parallel_If #(.DWIDTH(DATA_WIDTH), .CHANNELS(CHANNELS)) data_out ();
Realtime_Parallel_If #(.DWIDTH(DATA_WIDTH), .CHANNELS(CHANNELS)) data_in ();

realtime_delay #(
  .DATA_WIDTH(DATA_WIDTH),
  .CHANNELS(CHANNELS),
  .DELAY(5)
) dut_i (
  .clk,
  .reset,
  .data_in,
  .data_out
);

logic data_enable;
realtime_parallel_driver #(
  .DWIDTH(DATA_WIDTH),
  .CHANNELS(CHANNELS)
) driver_i (
  .clk,
  .reset,
  .valid_rand('0),
  .valid_en({CHANNELS{data_enable}}),
  .intf(data_in)
);

realtime_parallel_receiver #(
  .DWIDTH(DATA_WIDTH),
  .CHANNELS(CHANNELS)
) receiver_i (
  .clk,
  .intf(data_out)
);

initial begin
  debug.display("### TESTING REALTIME DELAY ###", sim_util_pkg::DEFAULT);
  reset <= 1'b1;
  data_enable <= 1'b0;
  repeat (10) @(posedge clk);
  reset <= 1'b0;
  repeat (10) @(posedge clk);
  data_enable <= 1'b1;
  repeat (50) @(posedge clk);
  for (int channel = 0; channel < CHANNELS; channel++) begin
    if (receiver_i.data_q[channel].size() !== driver_i.data_q[channel].size() - 5) begin
      debug.error($sformatf("expected exactly %0d - 5 samples, got %0d", driver_i.data_q[channel].size(), receiver_i.data_q[channel].size()));
    end
  end
  debug.finish();
end

endmodule
