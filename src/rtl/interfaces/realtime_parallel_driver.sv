// realtime_parallel_driver.sv - Reed Foster
// Test utility for Realtime_Parallel_If.Master interfaces
// Automatically outputs random data whenever valid is high
// Optionally deasserts, asserts, or toggles valid

`timescale 1ns/1ps
module realtime_parallel_driver #(
  parameter DWIDTH = 32,
  parameter CHANNELS = 1
) (
  input logic clk,
  input logic reset,
  input logic [CHANNELS-1:0] valid_rand,
  input logic [CHANNELS-1:0] valid_en,
  Realtime_Parallel_If.Master intf
);

localparam int WORD_WIDTH = 32;
localparam int NUM_WORDS = (DWIDTH + WORD_WIDTH - 1)/WORD_WIDTH;

logic [DWIDTH-1:0] data_q [CHANNELS][$];

always @(posedge clk) begin
  // if valid_rand & valid_en, then toggle valid randomly
  // if ~valid_rand & valid_en, hold valid high
  // if ~valid_en, hold valid low
  intf.valid <= (~valid_rand | $urandom()) & valid_en;
end

logic [CHANNELS-1:0][NUM_WORDS*WORD_WIDTH-1:0] temp_data;

always @(posedge clk) begin
  if (reset) begin
    intf.data <= '0;
  end else begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      if (intf.valid[channel]) begin
        data_q[channel].push_front(intf.data[channel]);
        for (int word = 0; word < NUM_WORDS; word++) begin
          temp_data[channel][word*WORD_WIDTH+:WORD_WIDTH] = $urandom();
        end
        intf.data[channel] <= temp_data[channel][DWIDTH-1:0];
      end
    end
  end
end

task automatic clear_queues ();
  for (int channel = 0; channel < CHANNELS; channel++) begin
    while (data_q[channel].size() > 0) data_q[channel].pop_back();
  end
endtask

endmodule
