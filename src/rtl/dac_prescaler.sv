// dac prescaler
module dac_prescaler #(
  parameter int SAMPLE_WIDTH = 16,
  parameter int PARALLEL_SAMPLES = 16,
  parameter int SCALE_WIDTH = 18,
  parameter int SAMPLE_FRAC_BITS = 16,
  parameter int SCALE_FRAC_BITS = 16
) (
  input wire clk, reset,
  Axis_If.Master_Simple data_out,
  Axis_If.Slave_Simple data_in,
  Axis_If.Slave_Simple scale_factor // 2Q16
);

logic signed [SAMPLE_WIDTH-1:0] data_in_reg [PARALLEL_SAMPLES]; // 0Q16
logic signed [SCALE_WIDTH-1:0] scale_factor_reg; // 2Q16
logic signed [SAMPLE_WIDTH+SCALE_WIDTH-1:0] product [PARALLEL_SAMPLES]; // 2Q32
logic signed [SAMPLE_WIDTH-1:0] product_d [PARALLEL_SAMPLES]; // 0Q16
logic [3:0] valid_d;

always_ff @(posedge clk) begin
  if (reset) begin
    valid_d <= '0;
  end
  if (scale_factor.valid && scale_factor.ready) begin
    scale_factor_reg <= scale_factor.data; // always update scale factor
  end
  if (data_in.ok) begin
    for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
      data_in_reg[i] <= data_in.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH]; // 0Q16*2Q16 = 2Q32
    end
  end
  if (data_out.ready || ~data_out.valid) begin
    for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
      product[i] <= data_in_reg[i]*scale_factor_reg; // 2Q32
      product_d[i] <= product[i][SAMPLE_WIDTH+SCALE_FRAC_BITS-1-:SAMPLE_WIDTH]; // 0Q16
      data_out.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= product_d[i];
    end
    valid_d <= {valid_d[2:0], data_in.ok};
  end
end

assign data_out.valid = valid_d[3];
assign data_in.ready = data_out.ready;
assign scale_factor.ready = 1'b1;

endmodule
