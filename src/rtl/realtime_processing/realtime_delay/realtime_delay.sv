// realtime_delay.sv - Reed Foster
// delay a signal by a fixed number of clock cycles

`timescale 1ns/1ps
module realtime_delay #(
  parameter int DATA_WIDTH,
  parameter int CHANNELS,
  parameter int DELAY
) (
  input wire clk, reset,
  Realtime_Parallel_If.Slave data_in,
  Realtime_Parallel_If.Master data_out
);

logic [DELAY-1:0][CHANNELS-1:0][DATA_WIDTH-1:0] data;
logic [DELAY-1:0][CHANNELS-1:0] valid;
always_ff @(posedge clk) begin
  data <= {data[DELAY-2:0], data_in.data};
  if (reset) begin
    valid <= '0;
  end else begin
    valid <= {valid[DELAY-2:0], data_in.valid};
  end
end

assign data_out.data = data[DELAY-1];
assign data_out.valid = valid[DELAY-1];

endmodule


