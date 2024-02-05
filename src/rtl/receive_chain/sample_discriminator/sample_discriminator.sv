// sample discriminator - Reed Foster

`timescale 1ns/1ps
module sample_discriminator (
  input logic adc_clk, adc_reset,
  Realtime_Parallel_If.Slave adc_data_in,
  Realtime_Parallel_If.Master adc_data_out,
  Realtime_Parallel_If.Master adc_timestamps_out,
  input logic adc_reset_state

  input logic [tx_pkg::CHANNELS-1:0] adc_digital_trigger_in;

  input logic ps_clk, ps_reset,
  Axis_If.Slave ps_thresholds, // {threshold_high, threshold_low} for each channel
  Axis_If.Slave ps_delay_holdoff, // {delay, holdoff} for each channel (32-bit quantities)
  Axis_If.Slave ps_trigger_select // {analog_trigger_enable, digital_trigger_enable, analog_trigger_source, digital_trigger_source} for each channel
);

//////////////////////////////////
// CDC configuration registers
//////////////////////////////////

// thresholds
logic [rx_pkg::CHANNELS-1:0][rx_pkg::SAMPLE_WIDTH_1:0] adc_thresholds_low;
logic [rx_pkg::CHANNELS-1:0][rx_pkg::SAMPLE_WIDTH_1:0] adc_thresholds_high;
Axis_If #(.DWIDTH(2*rx_pkg::SAMPLE_WIDTH*rx_pkg::CHANNELS)) adc_thresholds_sync ();
assign adc_thresholds_sync.ready = 1'b1; // always accept new config
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_thresholds_low <= '0;
    adc_thresholds_high <= '0;
  end else begin
    if (adc_thresholds_sync.ok) begin
      for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
        adc_thresholds_low[channel] <= adc_thresholds_sync.data[(2*channel)*rx_pkg::SAMPLE_WIDTH+:rx_pkg::SAMPLE_WIDTH];
        adc_thresholds_high[channel] <= adc_thresholds_sync.data[(2*channel+1)*rx_pkg::SAMPLE_WIDTH+:rx_pkg::SAMPLE_WIDTH];
      end
    end
  end
end
axis_config_reg_cdc #(
  .DWIDTH(2*rx_pkg::SAMPLE_WIDTH*rx_pkg::CHANNELS)
) threshold_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_thresholds),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_thresholds_sync)
);

// delay, holdoff
logic [rx_pkg::CHANNELS-1:0][31:0] adc_delay;
logic [rx_pkg::CHANNELS-1:0][31:0] adc_holdoff;
Axis_If #(.DWIDTH(32*rx_pkg::CHANNELS)) adc_delay_holdoff_sync ();
assign adc_delay_holdoff_sync.ready = 1'b1; // always accept new config
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_delay <= '0;
    adc_holdoff <= '0;
  end else begin
    if (adc_delay_holdoff_sync.ok) begin
      for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
        adc_delay[channel] <= adc_delay_holdoff_sync.data[(2*channel)*32+:32];
        adc_holdoff[channel] <= adc_delay_holdoff_sync.data[(2*channel+1)*32+:32];
      end
    end
  end
end
axis_config_reg_cdc #(
  .DWIDTH(2*32*rx_pkg::CHANNELS)
) delay_holdoff_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_delay_holdoff),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_delay_holdoff_sync)
);

// triggering
localparam int TRIGGER_SELECT_WIDTH = 2 + $clog2(rx_pkg::CHANNELS) + $clog2(tx_pkg::CHANNELS);
// signals
logic [rx_pkg::CHANNELS-1:0] adc_analog_trigger_enable;
logic [rx_pkg::CHANNELS-1:0] adc_digital_trigger_enable;
logic [rx_pkg::CHANNELS-1:0][$clog2(tx_pkg::CHANNELS)-1:0] adc_analog_trigger_source;
logic [rx_pkg::CHANNELS-1:0][$clog2(rx_pkg::CHANNELS)-1:0] adc_digital_trigger_source;
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*(TRIGGER_SELECT_WIDTH))) adc_trigger_select_sync ();
assign adc_trigger_select_sync.ready = 1'b1; // always accept new config
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_digital_trigger_enable <= '0; // disable digital triggers by default
    adc_analog_trigger_enable <= '1; // enable analog triggers by default
    adc_digital_trigger_source <= '0; // don't configure digital trigger sources
    for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
      // assign each analog trigger to its respective data channel
      adc_analog_trigger_source[channel] <= $clog2(rx_pkg::CHANNELS)'(channel);
    end
  end else begin
    if (adc_trigger_select_sync.ok) begin
      for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
        adc_analog_trigger_enable[channel] <= adc_trigger_select_sync[(channel+1)*TRIGGER_SELECT_WIDTH-1];
        adc_digital_trigger_enable[channel] <= adc_trigger_select_sync[(channel+1)*TRIGGER_SELECT_WIDTH-2];
        adc_analog_trigger_source[channel] <= adc_trigger_select_sync[channel*TRIGGER_SELECT_WIDTH+$clog2(tx_pkg::CHANNELS)+:$clog2(rx_pkg::CHANNELS)];
        adc_digital_trigger_source[channel] <= adc_trigger_select_sync[channel*TRIGGER_SELECT_WIDTH+:$clog2(tx_pkg::CHANNELS)];
      end
    end
  end
end
axis_config_reg_cdc #(
  .DWIDTH(TRIGGER_SELECT_WIDTH)
) trigger_select_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_trigger_select),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_trigger_select_sync)
);

logic [rx_pkg::CHANNELS-1:0][rx_pkg::DATA_WIDTH-1:0] adc_data_reg;
logic [rx_pkg::CHANNELS-1:0] adc_valid_reg;

endmodule
