// trigger_manager_test.sv - Reed Foster

import sim_util_pkg::*;

`timescale 1ns/1ps
module trigger_manager_test ();

sim_util_pkg::debug debug = new(DEFAULT);

localparam int CHANNELS = 8;

logic reset;
logic clk = 0;
localparam int CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

logic [CHANNELS-1:0] triggers_in;
logic trigger_out;
Axis_If #(.DWIDTH(1+CHANNELS)) trigger_config ();

trigger_manager #(
  .CHANNELS(CHANNELS)
) dut_i (
  .clk,
  .reset,
  .triggers_in,
  .trigger_config,
  .trigger_out
);

task set_trigger_config(
  input bit mode,
  input logic [CHANNELS-1:0] mask
);
  trigger_config.data <= {mode, mask};
  trigger_config.valid <= 1'b1;
  @(posedge clk);
  trigger_config.valid <= 1'b0;
endtask

task test_trigger(
  input logic [CHANNELS-1:0] trig,
  input bit expected
);
  triggers_in <= trig;
  @(posedge clk); // load trigger
  triggers_in <= '0;
  @(posedge clk); // match latency of module
  if (expected !== trigger_out) begin
    debug.error($sformatf("expected %0d, got %0d", expected, trigger_out));
  end
  @(posedge clk);
endtask

initial begin
  debug.display("### TESTING TRIGGER MANAGER ###", DEFAULT);
  reset <= 1'b1;
  trigger_config.data <= '0;
  trigger_config.valid <= 1'b0;
  triggers_in <= '0;
  repeat (50) @(posedge clk);
  reset <= 1'b0;
  @(posedge clk);
  set_trigger_config(0, 8'h1); // OR, only enable channel 0
  test_trigger(8'hfe, 0);
  test_trigger(8'h01, 1);
  test_trigger(8'hff, 1);
  set_trigger_config(0, 8'ha); // OR, enable channels 1, 3
  test_trigger(8'hf5, 0);
  test_trigger(8'h02, 1);
  test_trigger(8'h08, 1);
  test_trigger(8'h0a, 1);
  test_trigger(8'hff, 1);
  set_trigger_config(1, 8'h1); // AND, enable channel 0
  test_trigger(8'hfe, 0);
  test_trigger(8'h01, 1);
  test_trigger(8'hff, 1);
  set_trigger_config(1, 8'h90); // AND, enable channels 4, 7
  test_trigger(8'h6f, 0);
  test_trigger(8'h7f, 0);
  test_trigger(8'hef, 0);
  test_trigger(8'h90, 1);
  test_trigger(8'hff, 1);
  debug.finish(); 
end

endmodule
