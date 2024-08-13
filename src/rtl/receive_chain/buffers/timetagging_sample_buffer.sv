// timetagging_sample_buffer.sv - Reed Foster
// combines sample_discriminator with two buffers

`timescale 1ns/1ps
module timetagging_sample_buffer #(
  parameter int BUFFER_READ_LATENCY, // default 4 to permit UltraRAM inference
  parameter int AXI_MM_WIDTH // 128 bits
) (
  // ADC clock, reset (512 MHz)
  input logic adc_clk, adc_reset,
  // Data
  Realtime_Parallel_If.Slave adc_samples_in,
  Realtime_Parallel_If.Slave adc_timestamps_in,
  // Realtime inputs
  input logic adc_digital_trigger,
  // Realtime outputs
  output logic adc_discriminator_reset, // send signal to sample discriminator to reset hysteresis/index tracking

  // Status/configuration (PS) clock, reset (100 MHz)
  input logic ps_clk, ps_reset,
  // Buffer output data (both timestamp and data buffers are merged)
  Axis_If.Master ps_readout_data,
  // Status registers
  Axis_If.Master ps_samples_write_depth,
  Axis_If.Master ps_timestamps_write_depth,

  // Buffer configuration (merged)
  Axis_If.Slave ps_capture_arm_start_stop, // {arm, start, stop}
  Axis_If.Slave ps_capture_banking_mode,
  // Buffer reset
  Axis_If.Slave ps_capture_sw_reset, // ps clock domain; reset capture logic
  Axis_If.Slave ps_readout_sw_reset, // ps clock domain; reset readout logic
  Axis_If.Slave ps_readout_start // enable DMA over ps_readout_data interface
);

Axis_If #(.DWIDTH(rx_pkg::DATA_WIDTH)) ps_samples ();
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) ps_samples_resized ();
Axis_If #(.DWIDTH(buffer_pkg::TSTAMP_WIDTH)) ps_timestamps ();
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) ps_timestamps_resized ();

// only allow start_stop when both buffers are not in HOLD_SAMPLES state
logic [1:0] adc_capture_ready;

// CDC for start/stop
Axis_If #(.DWIDTH(3)) adc_capture_arm_start_stop_sync ();
logic adc_capture_start, adc_capture_stop;
assign adc_capture_start_stop_sync.ready = &adc_capture_ready;
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    {adc_capture_start, adc_capture_stop} <= '0;
  end
  if (adc_capture_start_stop_sync.ok) begin
    // use hw_start/hw_stop inputs of buffer
    {adc_capture_start, adc_capture_stop} <= adc_capture_arm_start_stop_sync.data[1:0];
  end
end
axis_config_reg_cdc #(
  .DWIDTH(3)
) capture_arm_start_stop_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_capture_arm_start_stop),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_capture_arm_start_stop_sync)
);

// send arm signal to both buffers whenever arm_start_stop comes in
Axis_If #(.DWIDTH(1)) ps_samples_capture_arm ();
Axis_If #(.DWIDTH(1)) ps_timestamps_capture_arm ();
assign ps_samples_capture_arm.data = 1'b1;
assign ps_timestamps_capture_arm.data = 1'b1;
always_ff @(posedge ps_clk) begin
  if (ps_capture_arm_start_stop.ok & ps_capture_arm_start_stop.data[2]) begin
    ps_samples_capture_arm.valid <= 1'b1;
    ps_timestamps_capture_arm.valid <= 1'b1;
  end else begin
    if (ps_samples_capture_arm.valid) begin
      ps_samples_capture_arm.valid <= 1'b0;
    end
    if (ps_timestamps_capture_arm.valid) begin
      ps_timestamps_capture_arm.valid <= 1'b0;
    end
  end
end

// wait for discriminator latency before starting to save samples
localparam int DISC_LATENCY = 4;
logic [DISC_LATENCY-1:0] adc_capture_start_pipe;
logic adc_capture_hw_start;
always_ff @(posedge adc_clk) begin
  adc_capture_start_pipe <= {adc_capture_start_pipe[DISC_LATENCY-2:0], adc_capture_start};
end
assign adc_capture_hw_start = adc_capture_start_pipe[DISC_LATENCY-1] | adc_digital_trigger_in;
assign adc_discriminator_reset = adc_capture_start;


// merge banking_mode, capture/readout sw_reset, and readout_start config registers
Axis_If #(.DWIDTH(buffer_pkg::BANKING_MODE_WIDTH)) ps_samples_capture_banking_mode ();
Axis_If #(.DWIDTH(buffer_pkg::BANKING_MODE_WIDTH)) ps_timestamps_capture_banking_mode ();
Axis_If #(.DWIDTH(1)) ps_samples_capture_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_timestamps_capture_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_samples_readout_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_timestamps_readout_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_samples_readout_start ();
Axis_If #(.DWIDTH(1)) ps_timestamps_readout_start ();

// banking mode
assign ps_capture_banking_mode.ready = ps_samples_capture_banking_mode.ready & ps_timestamps_capture_banking_mode.ready;
assign ps_samples_capture_banking_mode.data = ps_capture_banking_mode.data;
assign ps_timestamps_capture_banking_mode.data = ps_capture_banking_mode.data;
assign ps_samples_capture_banking_mode.valid = ps_capture_banking_mode.valid;
assign ps_timestamps_capture_banking_mode.valid = ps_capture_banking_mode.valid;
assign ps_samples_capture_banking_mode.last = ps_capture_banking_mode.last;
assign ps_timestamps_capture_banking_mode.last = ps_capture_banking_mode.last;

// capture_sw_reset
assign ps_capture_sw_reset.ready = ps_samples_capture_sw_reset.ready & ps_timestamps_capture_sw_reset.ready;
assign ps_samples_capture_sw_reset.data = ps_capture_sw_reset.data;
assign ps_timestamps_capture_sw_reset.data = ps_capture_sw_reset.data;
assign ps_samples_capture_sw_reset.valid = ps_capture_sw_reset.valid;
assign ps_timestamps_capture_sw_reset.valid = ps_capture_sw_reset.valid;
assign ps_samples_capture_sw_reset.last = ps_capture_sw_reset.last;
assign ps_timestamps_capture_sw_reset.last = ps_capture_sw_reset.last;

// readout_sw_reset
assign ps_readout_sw_reset.ready = ps_samples_readout_sw_reset.ready & ps_timestamps_readout_sw_reset.ready;
assign ps_samples_readout_sw_reset.data = ps_readout_sw_reset.data;
assign ps_timestamps_readout_sw_reset.data = ps_readout_sw_reset.data;
assign ps_samples_readout_sw_reset.valid = ps_readout_sw_reset.valid;
assign ps_timestamps_readout_sw_reset.valid = ps_readout_sw_reset.valid;
assign ps_samples_readout_sw_reset.last = ps_readout_sw_reset.last;
assign ps_timestamps_readout_sw_reset.last = ps_readout_sw_reset.last;

// readout_start
assign ps_readout_start.ready = ps_samples_readout_start.ready & ps_timestamps_readout_start.ready;
assign ps_samples_readout_start.data = ps_readout_start.data;
assign ps_timestamps_readout_start.data = ps_readout_start.data;
assign ps_samples_readout_start.valid = ps_readout_start.valid;
assign ps_timestamps_readout_start.valid = ps_readout_start.valid;
assign ps_samples_readout_start.last = ps_readout_start.last;
assign ps_timestamps_readout_start.last = ps_readout_start.last;

// cross-couple capture_full and capture_hw_stop to allow buffers to stop
// saving data when the other fills up
logic [1:0] adc_capture_full;

buffer #(
  .BUFFER_DEPTH(buffer_pkg::TSTAMP_BUFFER_DEPTH),
  .READ_LATENCY(BUFFER_READ_LATENCY)
) timestamp_buffer_i (
  .adc_clk,
  .adc_reset,
  .adc_data(adc_timestamps_in),
  .adc_capture_hw_start,
  .adc_capture_hw_stop(adc_capture_full[1] | adc_capture_stop),
  .adc_capture_ready(adc_capture_ready[0]);
  .adc_capture_full(adc_capture_full[0]),
  .ps_clk,
  .ps_reset,
  .ps_readout_data(ps_timestamps),
  .ps_capture_arm(ps_timestamps_capture_arm),
  .ps_capture_banking_mode(ps_timestamps_capture_banking_mode),
  .ps_capture_sw_reset(ps_timestamps_capture_sw_reset),
  .ps_readout_sw_reset(ps_timestamps_readout_sw_reset),
  .ps_readout_start(ps_timestamps_readout_start),
  .ps_capture_write_depth(ps_timestamp_write_depth)
);

buffer #(
  .BUFFER_DEPTH(buffer_pkg::SAMPLE_BUFFER_DEPTH),
  .READ_LATENCY(BUFFER_READ_LATENCY)
) data_buffer_i (
  .adc_clk,
  .adc_reset,
  .adc_data(adc_samples_in),
  .adc_capture_hw_start,
  .adc_capture_hw_stop(adc_capture_full[0] | adc_capture_stop),
  .adc_capture_ready(adc_capture_ready[1]);
  .adc_capture_full(adc_capture_full[1]),
  .ps_clk,
  .ps_reset,
  .ps_readout_data(ps_samples),
  .ps_capture_arm(ps_samples_capture_arm),
  .ps_capture_banking_mode(ps_samples_capture_banking_mode),
  .ps_capture_sw_reset(ps_samples_capture_sw_reset),
  .ps_readout_sw_reset(ps_samples_readout_sw_reset),
  .ps_readout_start(ps_samples_readout_start),
  .ps_capture_write_depth(ps_samples_write_depth)
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
  .data_in(ps_samples),
  .data_out(ps_samples_resized)
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
      DATA: if (ps_samples_resized.last && ps_samples_resized.ok) ps_buffer_select <= TIMESTAMP;
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
      ps_readout_data.data = ps_samples_resized.data;
      ps_readout_data.valid = ps_samples_resized.valid;
      ps_readout_data.last = ps_samples_resized.last;
  endcase
end

// DMA -> buffer
assign ps_timestamps_resized.ready = (buffer_select == TIMESTAMP) ? ps_readout_data.ready : 1'b0;
assign ps_samples_resized.ready = (buffer_select == DATA) ? ps_readout_data.ready : 1'b0;

endmodule
