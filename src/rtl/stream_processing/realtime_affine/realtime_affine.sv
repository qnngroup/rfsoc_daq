// realtime_affine.sv - Reed Foster
// Scales and offsets a Realtime_Parallel_If data stream by constant values

`timescale 1ns/1ps
module realtime_affine #(
  parameter int SAMPLE_WIDTH = 16,
  parameter int PARALLEL_SAMPLES = 16,
  parameter int CHANNELS = 8,
  parameter int SCALE_WIDTH = 18,
  parameter int OFFSET_WIDTH = 14,
  parameter int SCALE_INT_BITS = 2
) (
  input logic data_clk, data_reset,
  Realtime_Parallel_If.Master data_out,
  Realtime_Parallel_If.Slave data_in,
  input logic config_clk, config_reset,
  Axis_If.Slave config_scale_offset // {CHANNELS{2Q16 scale, 0Q14 offset}}
);

localparam int CONFIG_WIDTH = CHANNELS*(SCALE_WIDTH+OFFSET_WIDTH);
Axis_If #(.DWIDTH(CONFIG_WIDTH)) data_scale_offset_sync ();
axis_config_reg_cdc #(
  .DWIDTH(CONFIG_WIDTH)
) config_cdc_i (
  .src_clk(config_clk),
  .src_reset(config_reset),
  .src(config_scale_offset),
  .dest_clk(data_clk),
  .dest_reset(data_reset),
  .dest(data_scale_offset_sync)
);

localparam int SCALE_FRAC_BITS = SCALE_WIDTH - SCALE_INT_BITS;

assign data_scale_offset_sync.ready = 1'b1; // always accept scale_factor and offset_amount

logic signed [SAMPLE_WIDTH-1:0] data_in_reg [CHANNELS][PARALLEL_SAMPLES]; // 0Q16
logic signed [SCALE_WIDTH-1:0] data_scale_factor_reg [CHANNELS]; // 2Q16
logic signed [OFFSET_WIDTH-1:0] data_offset_amount_reg [CHANNELS]; // 0Q14
logic signed [SAMPLE_WIDTH+SCALE_WIDTH-1:0] data_product [CHANNELS][PARALLEL_SAMPLES]; // 2Q32
logic signed [SAMPLE_WIDTH+SCALE_WIDTH-1:0] data_offset_shifted [CHANNELS]; // 2Q32
logic signed [SAMPLE_WIDTH+SCALE_WIDTH:0] data_sum [CHANNELS][PARALLEL_SAMPLES]; // 3Q32
logic signed [SAMPLE_WIDTH-1:0] data_sum_d [CHANNELS][PARALLEL_SAMPLES]; // 0Q16
logic [CHANNELS-1:0][4:0] data_valid_d;

always_comb begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    data_offset_shifted[channel] = {
      {SCALE_INT_BITS{data_offset_amount_reg[channel][OFFSET_WIDTH-1]}}, // sign extend MSB
      data_offset_amount_reg[channel],
      {(SAMPLE_WIDTH+SCALE_FRAC_BITS-OFFSET_WIDTH){1'b0}}
    };
  end
end

always_ff @(posedge data_clk) begin
  if (data_reset) begin
    data_valid_d <= '0;
  end
  if (data_scale_offset_sync.valid & dac_scale_offset_sync.ready) begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      data_scale_factor_reg[channel] <= data_scale_offset_sync.data[channel*(OFFSET_WIDTH+SCALE_WIDTH)+OFFSET_WIDTH+:SCALE_WIDTH];
      data_offset_amount_reg[channel] <= data_scale_offset_sync.data[channel*(OFFSET_WIDTH+SCALE_WIDTH)+:OFFSET_WIDTH];
    end
  end
  for (int channel = 0; channel < CHANNELS; channel++) begin
    for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
      data_in_reg[channel][sample] <= data_in.data[channel][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH]; // 0Q16*2Q16 = 2Q32
      data_product[channel][sample] <= data_in_reg[channel][sample]*data_scale_factor_reg[channel]; // 2Q32
      data_sum[channel][sample] <= data_product[channel][sample] + data_offset_shifted[channel]; // 2Q32
      data_sum_d[channel][sample] <= data_sum[channel][sample][SAMPLE_WIDTH+SCALE_FRAC_BITS-1-:SAMPLE_WIDTH]; // 0Q16
      data_out.data[channel][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= data_sum_d[channel][sample];
    end
    data_valid_d[channel] <= {data_valid_d[channel][3:0], data_in.valid[channel]};
  end
end

always_comb begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    data_out.valid[channel] = data_valid_d[channel][4];
  end
end

endmodule
