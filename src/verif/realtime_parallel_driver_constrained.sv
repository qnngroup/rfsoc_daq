// realtime_parallel_driver_constrained.sv - Reed Foster
// Test utility for Realtime_Parallel_If.Master interfaces
// Automatically outputs random data whenever valid is high
// Optionally deasserts, asserts, or toggles valid

`timescale 1ns/1ps
module realtime_parallel_driver_constrained #(
  parameter int DWIDTH = 32,
  parameter int CHANNELS = 1,
  parameter int SAMPLE_WIDTH = 16,
  parameter int PARALLEL_SAMPLES = 2,
  type sample_t=logic signed [SAMPLE_WIDTH-1:0]
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

batch_randomizer_pkg::BatchRandomizer #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .sample_t(sample_t)
) randomizer_i = new(
  .min({1'b1, {(SAMPLE_WIDTH-1){1'b0}}}),
  .max({1'b0, {(SAMPLE_WIDTH-1){1'b1}}})
);

always @(posedge clk) begin
  // if valid_rand & valid_en, then toggle valid randomly
  // if ~valid_rand & valid_en, hold valid high
  // if ~valid_en, hold valid low
  intf.valid <= (~valid_rand | $urandom()) & valid_en;
end

always @(posedge clk) begin
  if (reset) begin
    intf.data <= '0;
  end else begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      if (intf.valid[channel]) begin
        data_q[channel].push_front(intf.data[channel]);
        randomizer_i.randomize();
        intf.data[channel] <= {<<SAMPLE_WIDTH{randomizer_i.data}};
      end
    end
  end
end

task automatic set_data_range (
  input sample_t min,
  input sample_t max
);
  randomizer_i.min = min;
  randomizer_i.max = max;
endtask

task automatic clear_queues ();
  for (int channel = 0; channel < CHANNELS; channel++) begin
    while (data_q[channel].size() > 0) data_q[channel].pop_back();
  end
endtask

endmodule
