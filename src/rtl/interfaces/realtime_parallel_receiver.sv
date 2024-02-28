// realtime_parallel_receiver.sv - Reed Foster
// Test utility for Realtime_Parallel_If.Slave interfaces
// Saves all received data in data_q queue

`timescale 1ns/1ps
module realtime_parallel_receiver #(
  parameter DWIDTH = 32,
  parameter CHANNELS = 1
) (
  input logic clk,
  Realtime_Parallel_If.Slave intf
);

logic [DWIDTH-1:0] data_q [CHANNELS][$];

always @(posedge clk) begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    if (intf.valid[channel]) begin
      data_q[channel].push_front(intf.data[channel]);
    end
  end
end

task automatic clear_queues ();
  for (int channel = 0; channel < CHANNELS; channel++) begin
    while (data_q[channel].size() > 0) data_q[channel].pop_back();
  end
endtask

endmodule
