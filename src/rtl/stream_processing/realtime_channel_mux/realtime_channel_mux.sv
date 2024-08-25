// realtime_channel_mux.sv - Reed Foster
// Multiplexer to downselect input channels
// - used to multiplex physical ADC channels and derived quantites from the
//   physical ADC channels, such as finite-difference derivatives or filters
// - used to multiplex multiple signal sources to physical DAC channels

`timescale 1ns/1ps
module realtime_channel_mux #(
  parameter int DATA_WIDTH,
  parameter int OUTPUT_CHANNELS,
  parameter int INPUT_CHANNELS,
  parameter int OUTPUT_REG,
  parameter int INPUT_REG
) (
  input logic data_clk, data_reset,

  Realtime_Parallel_If.Slave data_in, // INPUT_CHANNELS
  Realtime_Parallel_If.Master data_out, // OUTPUT_CHANNELS

  // selection of which input goes to each output
  // OUTPUT_CHANNELS * $clog2(INPUT_CHANNELS) bits
  input logic config_clk, config_reset,
  Axis_If.Slave config_in
);

localparam int CONFIG_WIDTH = OUTPUT_CHANNELS*$clog2(INPUT_CHANNELS);
Axis_If #(.DWIDTH(CONFIG_WIDTH)) data_config_sync ();
axis_config_reg_cdc #(
  .DWIDTH(CONFIG_WIDTH)
) config_cdc_i (
  .src_clk(config_clk),
  .src_reset(config_reset),
  .src(config_in),
  .dest_clk(data_clk),
  .dest_reset(data_reset),
  .dest(data_config_sync)
);

assign data_config_sync.ready = 1'b1; // always accept a new configuration

// register to store current selection for each logical channel
localparam int SELECT_BITS = $clog2(INPUT_CHANNELS);
logic [OUTPUT_CHANNELS-1:0][SELECT_BITS-1:0] data_source_select;

always_ff @(posedge data_clk) begin
  if (data_reset) begin
    for (int out_channel = 0; out_channel < OUTPUT_CHANNELS; out_channel++) begin
      data_source_select[out_channel] <= SELECT_BITS'(out_channel); // map raw physical channels directly to logical channels
    end
  end else begin
    if (data_config_sync.valid & data_config_sync.ready) begin
      data_source_select <= data_config_sync.data;
    end
  end
end

Realtime_Parallel_If #(.DWIDTH(DATA_WIDTH), .CHANNELS(INPUT_CHANNELS)) data_in_reg ();
Realtime_Parallel_If #(.DWIDTH(DATA_WIDTH), .CHANNELS(OUTPUT_CHANNELS)) data_out_reg ();

realtime_delay #(
  .DATA_WIDTH(DATA_WIDTH),
  .CHANNELS(INPUT_CHANNELS),
  .DELAY(INPUT_REG)
) data_delay_in_i (
  .clk(data_clk),
  .reset(data_reset),
  .data_in,
  .data_out(data_in_reg)
);

realtime_delay #(
  .DATA_WIDTH(DATA_WIDTH),
  .CHANNELS(OUTPUT_CHANNELS),
  .DELAY(OUTPUT_REG)
) data_delay_out_i (
  .clk(data_clk),
  .reset(data_reset),
  .data_in(data_out_reg),
  .data_out
);

// actually mux the data (registered so we could probably run this at 512 MHz if we wanted)
always_ff @(posedge data_clk) begin
  if (data_reset) begin
    data_out_reg.valid <= '0;
  end else begin
    // no data_reset condition for data, since it doesn't really matter
    for (int out_channel = 0; out_channel < OUTPUT_CHANNELS; out_channel++) begin
      data_out_reg.data[out_channel] <= data_in_reg.data[data_source_select[out_channel]];
      data_out_reg.valid[out_channel] <= data_in_reg.valid[data_source_select[out_channel]];
    end
  end
end

endmodule
