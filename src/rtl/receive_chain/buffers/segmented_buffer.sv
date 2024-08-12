// segmented_buffer.sv - Reed Foster
// combines sample_discriminator with two buffers

`timescale 1ns/1ps
module segmented_buffer #(
  parameter int DISC_MAX_DELAY_CYCLES, // 64 -> capture up to 128 ns before event @ 512 MHz
  parameter int BUFFER_READ_LATENCY, // default 4 to permit UltraRAM inference
  parameter int AXI_MM_WIDTH // 128 bits
) (
  // ADC clock, reset (512 MHz)
  input logic adc_clk, adc_reset,
  // Data
  Realtime_Parallel_If.Slave adc_data_in,
  // Realtime inputs
  input logic [tx_pkg::CHANNELS-1:0] adc_digital_trigger_in,

  // Status/configuration (PS) clock, reset (100 MHz)
  input logic ps_clk, ps_reset,
  // Buffer output data (both timestamp and data buffers are merged)
  Axis_If.Master ps_readout_data,
  // Buffer configuration (merged)
  Axis_If.Slave ps_capture_start_stop, // {start, stop}
  Axis_If.Slave ps_capture_banking_mode,
  // Discriminator configs
  Axis_If.Slave ps_discriminator_thresholds,
  Axis_If.Slave ps_discriminator_delays,
  Axis_If.Slave ps_discriminator_trigger_select,
  Axis_If.Slave ps_discriminator_bypass,
  // Buffer reset
  Axis_If.Slave ps_capture_sw_reset, // ps clock domain; reset capture logic
  Axis_If.Slave ps_readout_sw_reset, // ps clock domain; reset readout logic
  Axis_If.Slave ps_readout_start, // enable DMA over ps_readout_data interface
  // Buffer status (merged)
  Axis_If.Master ps_capture_write_depth
);

Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_data_out ();
Realtime_Parallel_If #(.DWIDTH(buffer_pkg::TSTAMP_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_timestamps_out ();

Axis_If #(.DWIDTH(rx_pkg::DATA_WIDTH)) ps_data ();
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) ps_data_resized ();
Axis_If #(.DWIDTH(buffer_pkg::TSTAMP_WIDTH)) ps_timestamps ();
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) ps_timestamps_resized ();
Axis_If #(.DWIDTH(rx_pkg::DATA_WIDTH)) ps_data_write_depth ();
Axis_If #(.DWIDTH(buffer_pkg::TSTAMP_WIDTH)) ps_timestamp_write_depth ();

// CDC for start/stop
Axis_If #(.DWIDTH(2)) adc_capture_start_stop_sync ();
logic adc_capture_start, adc_capture_stop;
assign adc_capture_start_stop_sync.ready = 1'b1;
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    {adc_capture_start, adc_capture_stop} <= '0;
  end
  if (adc_capture_start_stop_sync.valid) begin
    {adc_capture_start, adc_capture_stop} <= adc_capture_start_stop_sync.data;
  end
end
axis_config_reg_cdc #(
  .DWIDTH(2)
) capture_start_stop_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_capture_start_stop),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_capture_start_stop_sync)
);

localparam int DISC_LATENCY = 4;
logic [DISC_LATENCY-1:0] adc_capture_start_pipe;
logic adc_capture_hw_start;
always_ff @(posedge adc_clk) begin
  adc_capture_start_pipe <= {adc_capture_start_pipe[DISC_LATENCY-2:0], adc_capture_start};
end
assign adc_capture_hw_start = adc_capture_start_pipe[DISC_LATENCY-1];

sample_discriminator #(
  .MAX_DELAY_CYCLES(DISC_MAX_DELAY_CYCLES)
) disc_i (
  .adc_clk,
  .adc_reset,
  .adc_data_in,
  .adc_data_out,
  .adc_timestamps_out,
  .adc_reset_state(adc_capture_start),
  .adc_digital_trigger_in,
  .ps_clk,
  .ps_reset,
  .ps_thresholds(ps_discriminator_thresholds),
  .ps_delays(ps_discriminator_delays),
  .ps_trigger_select(ps_discriminator_trigger_select),
  .ps_bypass(ps_discriminator_bypass)
);

logic [1:0] adc_capture_full;

buffer #(
  .BUFFER_DEPTH(buffer_pkg::TSTAMP_BUFFER_DEPTH),
  .READ_LATENCY(BUFFER_READ_LATENCY)
) timestamp_buffer_i (
  .adc_clk,
  .adc_reset,
  .adc_data(adc_timestamps_out),
  .adc_capture_hw_start,
  .adc_capture_hw_stop(adc_capture_full[1] | adc_capture_stop),
  .adc_capture_full(adc_capture_full[0]),
  .ps_clk,
  .ps_reset,
  .ps_readout_data(ps_timestamps),
  .ps_capture_arm,
  .ps_capture_banking_mode,
  .ps_capture_sw_reset,
  .ps_readout_sw_reset,
  .ps_readout_start,
  .ps_capture_write_depth(ps_timestamp_write_depth)
);

buffer #(
  .BUFFER_DEPTH(buffer_pkg::SAMPLE_BUFFER_DEPTH),
  .READ_LATENCY(BUFFER_READ_LATENCY)
) data_buffer_i (
  .adc_clk,
  .adc_reset,
  .adc_data(adc_data_out),
  .adc_capture_hw_start,
  .adc_capture_hw_stop(adc_capture_full[0] | adc_capture_stop),
  .adc_capture_full(adc_capture_full[1]),
  .ps_clk,
  .ps_reset,
  .ps_readout_data(ps_data),
  .ps_capture_arm,
  .ps_capture_banking_mode,
  .ps_capture_sw_reset,
  .ps_readout_sw_reset,
  .ps_readout_start,
  .ps_capture_write_depth(ps_data_write_depth)
);

axis_width_converter #(
  .DWIDTH_IN(buffer_pkg::TSTAMP_WIDTH),
  .DWIDTH_OUT(AXI_MM_WIDTH)
) timestamp_width_converter_i (
  .clk(ps_clk),
  .reset(ps_reset),
  .data_in(ps_timestamps),
  .data_out(ps_timestamps_resized)
);

axis_width_converter #(
  .DWIDTH_IN(rx_pkg::DATA_WIDTH),
  .DWIDTH_OUT(AXI_MM_WIDTH)
) data_width_converter_i (
  .clk(ps_clk),
  .reset(ps_reset),
  .data_in(ps_data),
  .data_out(ps_data_resized)
);

/////////////////////
// mux the outputs
/////////////////////

enum {TIMESTAMP, DATA} ps_buffer_select;

always_ff @(posedge ps_clk) begin
  if (ps_reset) begin
    ps_buffer_select <= TIMESTAMP;
  end else begin
    unique case (ps_buffer_select)
      TIMESTAMP: if (ps_timestamps_resized.last && ps_timestamps_resized.ok) ps_buffer_select <= DATA;
      DATA: if (ps_data_resized.last && ps_data_resized.ok) ps_buffer_select <= TIMESTAMP;
    endcase
  end
end

// buffer -> DMA
always_comb begin
  unique case (ps_buffer_select)
    TIMESTAMP:
      ps_readout_data.data = ps_timestamps_resized.data;
      ps_readout_data.valid = ps_timestamps_resized.valid;
      ps_readout_data.last = 1'b0; // don't send last until all data has been sent
    DATA:
      ps_readout_data.data = ps_data_resized.data;
      ps_readout_data.valid = ps_data_resized.valid;
      ps_readout_data.last = ps_data_resized.last;
  endcase
end

// DMA -> buffer
assign ps_timestamps_resized.ready = (buffer_select == TIMESTAMP) ? ps_readout_data.ready : 1'b0;
assign ps_data_resized.ready = (buffer_select == DATA) ? ps_readout_data.ready : 1'b0;

endmodule
