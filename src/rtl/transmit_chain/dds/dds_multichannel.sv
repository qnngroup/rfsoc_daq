// dds_multichannel.sv - Reed Foster
// Direct Digital Synthesis module, uses phase dithering with a maximal LFSR
// to achieve high spectral purity.
module dds_multichannel #(
  parameter int PHASE_BITS = 32,
  parameter int SAMPLE_WIDTH = 16,
  parameter int QUANT_BITS = 20,
  parameter int PARALLEL_SAMPLES = 4,
  parameter int CHANNELS = 8
) (
  input wire clk, reset,
  Axis_Parallel_If.Master_Stream data_out,
  Axis_If.Slave_Realtime phase_inc_in // PHASE_BITS*CHANNELS
);

genvar channel;
generate
  for (channel = 0; channel < CHANNELS; channel++) begin
    Axis_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH)) data_out_channel ();
    Axis_If #(.DWIDTH(PHASE_BITS)) phase_inc_channel ();

    assign data_out.data[channel] = data_out_channel.data;
    assign data_out.valid[channel] = data_out_channel.valid;
    assign data_out_channel.ready = data_out.ready[channel];

    assign phase_inc_channel.data = phase_inc_in.data[channel*PHASE_BITS+:PHASE_BITS];
    assign phase_inc_channel.valid = phase_inc_in.valid;

    dds #(
      .PHASE_BITS(PHASE_BITS),
      .SAMPLE_WIDTH(SAMPLE_WIDTH),
      .QUANT_BITS(QUANT_BITS),
      .PARALLEL_SAMPLES(PARALLEL_SAMPLES)
    ) dds_i (
      .clk(clk),
      .reset(reset),
      .cos_out(data_out_channel),
      .phase_inc_in(phase_inc_channel)
    );
  end
endgenerate

endmodule
