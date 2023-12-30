// axis_channel_mux.sv - Reed Foster
// Multiplexer to assign physical ADC channels (and derived quantites from the
// physical ADC channels, such as finite-difference derivatives or filters) to
// logical channels that are inputs to the sample buffer (either
// sparse_sample_buffer or sample_buffer)

module axis_channel_mux #(
  parameter int PARALLEL_SAMPLES = 16, // 4.096 GS/s @ 256 MHz
  parameter int SAMPLE_WIDTH = 16, // 12-bit ADC
  parameter int CHANNELS = 8, // same number of logical and physical channels for simplicity
  // if FUNCTIONS_PER_CHANNEL needs to be more than 3, we should rethink how best to
  // implement this or the muxes will explode and timing will become difficult to meet
  // for now, we just have finite difference time-derivative approximation
  parameter int FUNCTIONS_PER_CHANNEL = 1
) (
  input wire clk, reset,

  Axis_Parallel_If.Slave_Realtime data_in, // CHANNELS*(1+FUNCTIONS_PER_CHANNEL) physical/math channels
  Axis_Parallel_If.Master_Realtime data_out, // CHANNELS logical channels

  // selection of which input goes to each output
  // CHANNELS * $clog2((1+FUNCTIONS_PER_CHANNEL)*CHANNELS) bits
  // there are 1+FUNCTIONS_PER_CHANNEL different sources for each logical
  // channel since we can pick the raw data from the physical channel, or any
  // of the derived math quantities
  Axis_If.Slave_Realtime config_in
);

// register to store current selection for each logical channel
localparam int SELECT_BITS = $clog2((1+FUNCTIONS_PER_CHANNEL)*CHANNELS);
logic [CHANNELS-1:0][SELECT_BITS-1:0] source_select;

always_ff @(posedge clk) begin
  if (reset) begin
    for (int logical_channel = 0; logical_channel < CHANNELS; logical_channel++) begin
      source_select[logical_channel] <= logical_channel; // map raw physical channels directly to logical channels
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
  for (int logical_channel = 0; logical_channel < CHANNELS; logical_channel++) begin
    data_out.data[logical_channel] <= data_in.data[source_select[logical_channel]];
    data_out.valid[logical_channel] <= data_in.valid[source_select[logical_channel]];
  end
end

endmodule
