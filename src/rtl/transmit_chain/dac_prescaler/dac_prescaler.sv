// dac_prescaler.sv - Reed Foster
// Scales an AXI-stream data stream by a constant value

`timescale 1ns/1ps
module dac_prescaler #(
  parameter int SAMPLE_WIDTH = 16,
  parameter int PARALLEL_SAMPLES = 16,
  parameter int CHANNELS = 8,
  parameter int SCALE_WIDTH = 18,
  parameter int OFFSET_WIDTH = 14,
  parameter int SCALE_OFFSET_INT_BITS = 2
) (
  input wire clk, reset,
  Realtime_Parallel_If.Master data_out,
  Realtime_Parallel_If.Slave data_in,
  Axis_If.Slave scale_offset // {CHANNELS{2Q16 scale, 2Q12 offset}}
);

localparam int SCALE_FRAC_BITS = SCALE_WIDTH - SCALE_OFFSET_INT_BITS;
localparam int OFFSET_FRAC_BITS = OFFSET_WIDTH - SCALE_OFFSET_INT_BITS;

assign scale_offset.ready = 1'b1; // always accept scale_factor and offset_amount

logic signed [SAMPLE_WIDTH-1:0] data_in_reg [CHANNELS][PARALLEL_SAMPLES]; // 0Q16
logic signed [SCALE_WIDTH-1:0] scale_factor_reg [CHANNELS]; // 2Q16
logic signed [OFFSET_WIDTH-1:0] offset_amount_reg [CHANNELS]; // 2Q12
logic signed [SAMPLE_WIDTH+SCALE_WIDTH-1:0] product [CHANNELS][PARALLEL_SAMPLES]; // 2Q32
logic signed [SAMPLE_WIDTH+SCALE_WIDTH:0] sum [CHANNELS][PARALLEL_SAMPLES]; // 3Q32
logic signed [SAMPLE_WIDTH-1:0] sum_d [CHANNELS][PARALLEL_SAMPLES]; // 0Q16
logic [CHANNELS-1:0][4:0] valid_d;

always_ff @(posedge clk) begin
  if (reset) begin
    valid_d <= '0;
  end
  if (scale_offset.ok) begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      scale_factor_reg[channel] <= scale_offset.data[channel*(OFFSET_WIDTH+SCALE_WIDTH)+OFFSET_WIDTH+:SCALE_WIDTH];
      offset_amount_reg[channel] <= scale_offset.data[channel*(OFFSET_WIDTH+SCALE_WIDTH)+:OFFSET_WIDTH];
    end
  end
  for (int channel = 0; channel < CHANNELS; channel++) begin
    for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
      data_in_reg[channel][sample] <= data_in.data[channel][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH]; // 0Q16*2Q16 = 2Q32
      product[channel][sample] <= data_in_reg[channel][sample]*scale_factor_reg[channel]; // 2Q32
      sum[channel][sample] <= product[channel][sample]
                              + {offset_amount_reg[channel], {(SAMPLE_WIDTH+SCALE_FRAC_BITS-OFFSET_FRAC_BITS){1'b0}}};
      sum_d[channel][sample] <= sum[channel][sample][SAMPLE_WIDTH+SCALE_FRAC_BITS-1-:SAMPLE_WIDTH]; // 0Q16
      data_out.data[channel][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= sum_d[channel][sample];
    end
    valid_d[channel] <= {valid_d[channel][3:0], data_in.valid[channel]};
  end
end

always_comb begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    data_out.valid[channel] = valid_d[channel][4];
  end
end

endmodule
