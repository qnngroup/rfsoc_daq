// axis_channel_mux.sv - Reed Foster
// Multiplexer to downselect input channels
// - used to multiplex physical ADC channels and derived quantites from the
//   physical ADC channels, such as finite-difference derivatives or filters
// - used to multiplex multiple signal sources to physical DAC channels

module axis_channel_mux #(
  parameter int PARALLEL_SAMPLES = 16, // 4.096 GS/s @ 256 MHz
  parameter int SAMPLE_WIDTH = 16, // 12-bit ADC
  parameter int OUTPUT_CHANNELS = 8,
  parameter int INPUT_CHANNELS = 16
) (
  input wire clk, reset,

  Axis_Parallel_If.Slave_Realtime data_in, // INPUT_CHANNELS
  Axis_Parallel_If.Master_Realtime data_out, // OUTPUT_CHANNELS

  // selection of which input goes to each output
  // OUTPUT_CHANNELS * $clog2(INPUT_CHANNELS) bits
  Axis_If.Slave_Realtime config_in
);

// register to store current selection for each logical channel
localparam int SELECT_BITS = $clog2(INPUT_CHANNELS);
logic [OUTPUT_CHANNELS-1:0][SELECT_BITS-1:0] source_select;

always_ff @(posedge clk) begin
  if (reset) begin
    for (int out_channel = 0; out_channel < OUTPUT_CHANNELS; out_channel++) begin
      source_select[out_channel] <= out_channel; // map raw physical channels directly to logical channels
    end
  end else begin
    if (config_in.valid) begin
      source_select <= config_in.data;
    end
  end
end

// actually mux the data (registered so we could probably run this at 512 MHz if we wanted)
always_ff @(posedge clk) begin
  // no reset condition for data, since it doesn't really matter
  for (int out_channel = 0; out_channel < OUTPUT_CHANNELS; out_channel++) begin
    data_out.data[out_channel] <= data_in.data[source_select[out_channel]];
    data_out.valid[out_channel] <= data_in.valid[source_select[out_channel]];
  end
end

endmodule
