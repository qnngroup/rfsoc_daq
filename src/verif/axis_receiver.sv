// axis_receiver.sv - Reed Foster
// Test utility for Axis_If.Slave interfaces
// Saves all received data in data_q queue
// Saves the "time" of all tlast events in last_q queue
// "time" is determined by the size of data_q
// Optionally deasserts, asserts, or toggles ready

`timescale 1ns/1ps
module axis_receiver #(
  parameter DWIDTH = 32
) (
  input logic clk,
  input logic ready_rand,
  input logic ready_en,
  Axis_If.Slave intf
);

logic [DWIDTH-1:0] data_q [$];
int last_q [$];

always @(posedge clk) begin
  if (intf.valid & intf.ready) begin
    data_q.push_front(intf.data);
    if (intf.last) begin
      last_q.push_front(data_q.size());
    end
  end
end

always @(posedge clk) begin
  // if ready_rand & ready_en, then toggle ready randomly
  // if ~ready_rand & ready_en, hold ready high
  // if ~ready_en, hold ready low
  intf.ready <= (~ready_rand | $urandom()) & ready_en;
end

task automatic clear_queues();
  while (data_q.size() > 0) data_q.pop_back();
  while (last_q.size() > 0) last_q.pop_back();
endtask

endmodule
