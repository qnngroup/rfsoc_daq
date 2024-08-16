// trigger_manager.sv - Reed Foster
// applies a per-channel mask
// MSB of config selects either OR or AND
// default config = 0 disables output of any triggers: |(triggers_in & 0)
// most of the time, the MSB should be set to 0, unless multiple trigger
// conditions must be satisfied simultaneously

`timescale 1ns/1ps
module trigger_manager #(
  parameter int CHANNELS = 8
) (
  input wire clk, reset,
  input logic [CHANNELS-1:0] triggers_in,
  Axis_If.Slave trigger_config, // {OR/AND, per-channel mask}
  output logic trigger_out
);

assign trigger_config.ready = 1'b1; // always accept a new trigger configuration

logic [CHANNELS-1:0] trigger_mask;
enum {OR=0, AND=1} comb_mode;

// process new configuration
always_ff @(posedge clk) begin
  if (reset) begin
    trigger_mask <= '0;
    comb_mode <= OR;
  end else begin
    if (trigger_config.valid) begin
      trigger_mask <= trigger_config.data[CHANNELS-1:0];
      comb_mode <= trigger_config.data[CHANNELS] ? AND : OR;
    end
  end
end

// trigger combining logic
always_ff @(posedge clk) begin
  unique case (comb_mode)
    OR: begin
      trigger_out <= |(triggers_in & trigger_mask);
    end
    AND: begin
      trigger_out <= &((triggers_in & trigger_mask) | (~trigger_mask));
    end
  endcase
end

endmodule
