// pulse_delay.sv - Reed Foster
// Delays an incoming pulse by a variable number of cycles using a counter
// Cannot process multiple pulses simultaneously (use a shift register for that)

`timescale 1ns/1ps
module pulse_delay #(
  parameter int TIMER_BITS = 8,
  // RETRIGGER_MODE:
  // 0 -> block incoming events until finished with current event
  // 1 -> reset count every time a new event occurs
  parameter int RETRIGGER_MODE = 0
) (
  input logic clk, reset,
  input [TIMER_BITS-1:0] delay,
  input in_pls,
  output out_pls
);

logic [TIMER_BITS-1:0] counter;
logic active;
logic done;
assign done = counter == 0;
assign out_pls = done & active;

always_ff @(posedge clk) begin
  if (reset) begin
    counter <= '0;
    active <= '0;
  end else begin
    // if RETRIGGER_MODE = 0, block incoming events and wait until ~active
    // if RETRIGGER_MODE = 1, allow any incoming event to reset count
    if ((~(active & ~done) | (RETRIGGER_MODE == 1)) & in_pls) begin
      counter <= delay;
      active <= 1'b1;
    end else begin
      if (~done) begin
        counter <= counter - 1;
      end else begin
        active <= 1'b0;
      end
    end
  end
end

endmodule
