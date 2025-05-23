// timetagging_sample_buffer.sv - Reed Foster
// Combines two buffers, one for timestamps, one for samples
//
// Datastream interfaces
// - adc_samples_in: incoming sample data
// - adc_timestamps_in: incoming timestamp data
// - ps_readout_data:
//    - rx_pkg::AXI_MM_WIDTH-wide bus for DMA readout of buffers
//    - First outputs timestamps, then samples
//    - Transfer size (and order) is fixed; use write_depth registers to
//      determine number of valid samples
//    - [valid timestamps, ..., valid samples, ...]
//
// Realtime I/O
// - adc_digital_trigger:
//    - Output of trigger manager, used to start capture from a digital event
// - adc_discriminator_reset:
//    - Input to sample discriminator that goes high when capture is started
//      to reset sample discriminator hysteresis tracking and sample index
//
// Status registers
// - ps_samples_write_depth:
//    - number of sample batches saved
//    - rx_pkg::PARALLEL_SAMPLES per batch
// - ps_timestamps_write_depth:
//    - number of timestamp batches saved
//    - 1 timestamp per batch
//
// Configuration registers
// - ps_capture_arm_start_stop:
//    - {arm, start, stop}
//    - arm will put the capture FSM into a state where adc_digital_trigger
//      can start a capture
//      - {1,0,0} to arm
//    - start causes a software start, and must be accompanied by an arm
//      - {1,1,0} to start
//    - stop allows manual stopping of capture, e.g. when input stream is very
//      sparse and one doesn't want to wait until the buffer fills up
//      - {0,0,1} to stop
// - ps_capture_banking_mode:
//    - selects number of active capture channels
//    - see buffer.sv for details
// - ps_capture_sw_reset:
//    - reset capture FSM
//    - see buffer.sv for details
// - ps_readout_sw_reset:
//    - reset readout FSM
//    - see buffer.sv for details
// - ps_readout_start:
//    - put readout FSM into DMA mode and initiate a readout of data

`timescale 1ns/1ps
module timetagging_sample_buffer #(
  parameter int BUFFER_READ_LATENCY // default 4 to permit UltraRAM inference
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
Axis_If #(.DWIDTH(rx_pkg::AXI_MM_WIDTH)) ps_samples_resized ();
Axis_If #(.DWIDTH(buffer_pkg::TSTAMP_WIDTH)) ps_timestamps ();
Axis_If #(.DWIDTH(rx_pkg::AXI_MM_WIDTH)) ps_timestamps_resized ();

// only allow start_stop when both buffers are not in HOLD_SAMPLES state
logic [1:0] adc_capture_ready;

// CDC for start/stop
Axis_If #(.DWIDTH(2)) adc_capture_start_stop_sync ();
logic adc_capture_start, adc_capture_stop;
assign adc_capture_start_stop_sync.ready = &adc_capture_ready;
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    {adc_capture_start, adc_capture_stop} <= '0;
  end
  if (adc_capture_start_stop_sync.valid & adc_capture_start_stop_sync.ready) begin
    // use hw_start/hw_stop inputs of buffer
    {adc_capture_start, adc_capture_stop} <= adc_capture_start_stop_sync.data;
  end else begin
    adc_capture_start <= 1'b0;
    adc_capture_stop <= 1'b0;
  end
end
// delay ps_capture_arm_start_stop by a cycle to ensure start/stop signals are
// delayed enough to arrive after arm signal
Axis_If #(.DWIDTH(2)) ps_capture_start_stop_delay ();
assign ps_capture_arm_start_stop.ready = ps_capture_start_stop_delay.ready;
assign ps_capture_start_stop_delay.last = 1'b0; // don't care
always_ff @(posedge ps_clk) begin
  if (ps_capture_start_stop_delay.ready) begin
    ps_capture_start_stop_delay.valid <= ps_capture_arm_start_stop.valid;
    ps_capture_start_stop_delay.data <= ps_capture_arm_start_stop.data;
  end
end
axis_config_reg_cdc #(
  .DWIDTH(2)
) capture_start_stop_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_capture_start_stop_delay),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_capture_start_stop_sync)
);

// send arm signal to both buffers whenever arm_start_stop comes in
Axis_If #(.DWIDTH(1)) ps_samples_capture_arm ();
Axis_If #(.DWIDTH(1)) ps_timestamps_capture_arm ();
assign ps_samples_capture_arm.data = 1'b1;
assign ps_timestamps_capture_arm.data = 1'b1;
assign ps_samples_capture_arm.last = 1'b0; // don't care
assign ps_timestamps_capture_arm.last = 1'b0; // don't care
always_ff @(posedge ps_clk) begin
  if (ps_capture_arm_start_stop.valid & ps_capture_arm_start_stop.ready & ps_capture_arm_start_stop.data[2]) begin
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
  adc_capture_start_pipe <= {adc_capture_start_pipe[DISC_LATENCY-2:0], adc_capture_start | adc_digital_trigger};
end
assign adc_capture_hw_start = adc_capture_start_pipe[DISC_LATENCY-1];
assign adc_discriminator_reset = adc_capture_start | adc_digital_trigger;


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
assign ps_readout_sw_reset.ready = ps_samples_readout_sw_reset.ready | ps_timestamps_readout_sw_reset.ready;
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
  .DATA_WIDTH(buffer_pkg::TSTAMP_WIDTH),
  .BUFFER_DEPTH(buffer_pkg::TSTAMP_BUFFER_DEPTH),
  .READ_LATENCY(BUFFER_READ_LATENCY)
) timestamp_buffer_i (
  .adc_clk,
  .adc_reset,
  .adc_data(adc_timestamps_in),
  .adc_capture_hw_start,
  .adc_capture_hw_stop(adc_capture_full[1] | adc_capture_stop),
  .adc_capture_ready(adc_capture_ready[0]),
  .adc_capture_full(adc_capture_full[0]),
  .ps_clk,
  .ps_reset,
  .ps_readout_data(ps_timestamps),
  .ps_capture_arm(ps_timestamps_capture_arm),
  .ps_capture_banking_mode(ps_timestamps_capture_banking_mode),
  .ps_capture_sw_reset(ps_timestamps_capture_sw_reset),
  .ps_readout_sw_reset(ps_timestamps_readout_sw_reset),
  .ps_readout_start(ps_timestamps_readout_start),
  .ps_capture_write_depth(ps_timestamps_write_depth)
);

buffer #(
  .DATA_WIDTH(rx_pkg::DATA_WIDTH),
  .BUFFER_DEPTH(buffer_pkg::SAMPLE_BUFFER_DEPTH),
  .READ_LATENCY(BUFFER_READ_LATENCY)
) sample_buffer_i (
  .adc_clk,
  .adc_reset,
  .adc_data(adc_samples_in),
  .adc_capture_hw_start,
  .adc_capture_hw_stop(adc_capture_full[0] | adc_capture_stop),
  .adc_capture_ready(adc_capture_ready[1]),
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

logic ps_readout_sw_reset_d;
always_ff @(posedge ps_clk) begin
  if (ps_reset) begin
    ps_readout_sw_reset_d <= 1'b0;
  end else begin
    if (ps_readout_sw_reset.valid & ps_readout_sw_reset.ready) begin
      ps_readout_sw_reset_d <= 1'b1;
    end else begin
      ps_readout_sw_reset_d <= 1'b0;
    end
  end
end

axis_width_converter #(
  .DWIDTH_IN(buffer_pkg::TSTAMP_WIDTH),
  .DWIDTH_OUT(rx_pkg::AXI_MM_WIDTH)
) timestamp_width_converter_i (
  .clk(ps_clk),
  .reset(ps_reset | ps_readout_sw_reset_d),
  .data_in(ps_timestamps),
  .data_out(ps_timestamps_resized)
);

axis_width_converter #(
  .DWIDTH_IN(rx_pkg::DATA_WIDTH),
  .DWIDTH_OUT(rx_pkg::AXI_MM_WIDTH)
) data_width_converter_i (
  .clk(ps_clk),
  .reset(ps_reset | ps_readout_sw_reset_d),
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
    if (ps_readout_sw_reset.valid & ps_readout_sw_reset.ready) begin
      ps_buffer_select <= TIMESTAMP;
    end else begin
      unique case (ps_buffer_select)
        TIMESTAMP: if (ps_timestamps_resized.last & ps_timestamps_resized.valid & ps_timestamps_resized.ready) ps_buffer_select <= DATA;
        DATA: if (ps_samples_resized.last & ps_samples_resized.valid & ps_samples_resized.ready) ps_buffer_select <= TIMESTAMP;
      endcase
    end
  end
end

// buffer -> DMA
always_comb begin
  unique case (ps_buffer_select)
    TIMESTAMP: begin
      ps_readout_data.data = ps_timestamps_resized.data;
      ps_readout_data.valid = ps_timestamps_resized.valid;
      ps_readout_data.last = 1'b0; // don't send last until all data has been sent
    end
    DATA: begin
      ps_readout_data.data = ps_samples_resized.data;
      ps_readout_data.valid = ps_samples_resized.valid;
      ps_readout_data.last = ps_samples_resized.last;
    end
  endcase
end

// DMA -> buffer
assign ps_timestamps_resized.ready = (ps_buffer_select == TIMESTAMP) ? ps_readout_data.ready : 1'b0;
assign ps_samples_resized.ready = (ps_buffer_select == DATA) ? ps_readout_data.ready : 1'b0;

endmodule
