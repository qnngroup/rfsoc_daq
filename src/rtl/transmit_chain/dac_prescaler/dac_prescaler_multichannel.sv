// dac_prescaler_multichannel.sv - Reed Foster
// Allows for a streamlined instantiation of multi-channel scaling
module dac_prescaler_multichannel #(
  parameter int SAMPLE_WIDTH = 16,
  parameter int PARALLEL_SAMPLES = 16,
  parameter int SCALE_WIDTH = 18,
  parameter int SAMPLE_FRAC_BITS = 16,
  parameter int SCALE_FRAC_BITS = 16,
  parameter int CHANNELS = 8
) (
  input wire clk, reset,
  Axis_Parallel_If.Master_Stream data_out,
  Axis_Parallel_If.Slave_Stream data_in,
  Axis_If.Slave scale_factor // 2Q16*CHANNELS
);

assign scale_factor.ready = 1'b1; // always accept new scale factor

genvar channel;
generate
  for (channel = 0; channel < CHANNELS; channel++) begin
    Axis_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH)) data_out_channel ();
    Axis_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH)) data_in_channel ();
    Axis_If #(.DWIDTH(SCALE_WIDTH)) scale_factor_channel ();

    assign data_out.data[channel] = data_out_channel.data;
    assign data_out.valid[channel] = data_out_channel.valid;
    assign data_out_channel.ready = data_out.ready[channel];

    assign data_in_channel.data = data_in.data[channel];
    assign data_in_channel.valid = data_in.valid[channel];
    assign data_in.ready[channel] = data_in_channel.ready;

    assign scale_factor_channel.data = scale_factor.data[channel*SCALE_WIDTH+:SCALE_WIDTH];
    assign scale_factor_channel.valid = scale_factor.valid;

    dac_prescaler #(
      .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
      .SAMPLE_WIDTH(SAMPLE_WIDTH),
      .SAMPLE_FRAC_BITS(SAMPLE_FRAC_BITS),
      .SCALE_WIDTH(SCALE_WIDTH),
      .SCALE_FRAC_BITS(SCALE_FRAC_BITS)
    ) prescaler_i (
      .clk(clk),
      .reset(reset),
      .data_out(data_out_channel),
      .data_in(data_in_channel),
      .scale_factor(scale_factor_channel)
    );
  end
endgenerate

endmodule
