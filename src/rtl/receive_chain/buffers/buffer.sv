// buffer.sv - Reed Foster
// adds capture and readout FSMs to buffer_core to reduce deadlocks due to
// stalled DMA transfers

`timescale 1ns/1ps
module buffer #(
  parameter int CHANNELS = 8,
  parameter int BUFFER_DEPTH = 256,
  parameter int DATA_WIDTH = 256,
  parameter int READ_LATENCY = 4
) (
  // ADC clock, reset (512 MHz)
  input wire capture_clk, capture_reset,
  // data
  Realtime_Parallel_If.Slave capture_data,
  // hardware control
  input logic capture_hw_start,
  input logic capture_hw_stop,
  output logic capture_full,

  // Readout (PS) clock, reset (100 MHz)
  input wire readout_clk, readout_reset,
  Axis_If.Master readout_data,
  // configuration
  Axis_If.Slave readout_capture_arm_sw_start_stop, // controls capture {arm, sw_start, sw_stop}
  Axis_If.Slave readout_banking_mode, // controls capture (active_channels = 1 << banking_mode)
  Axis_If.Slave readout_capture_sw_reset, // readout clock domain; reset capture logic
  Axis_If.Slave readout_dma_sw_reset, // readout clock domain; reset readout logic
  Axis_If.Slave readout_dma_start, // enable DMA over readout_data interface
  // status
  Axis_If.Master readout_write_depth // number of samples saved per bank; outputted after a capture completes
);

enum {CAPTURE_IDLE, TRIGGER_WAIT, SAVE_SAMPLES, HOLD_SAMPLES} capture_state;
enum {DMA_IDLE, DMA_READY, DMA_ACTIVE} readout_state;

logic [$clog2(CHANNELS+1)-1:0] capture_active_channels;
logic [CHANNELS-1:0][$clog2(BUFFER_DEPTH):0] capture_write_depth;
logic capture_start, capture_stop;

assign capture_stop = (capture_hw_stop | capture_sw_stop) & (capture_state == SAVE_SAMPLES);
assign capture_start = ((capture_hw_start | capture_sw_start) & (capture_state == TRIGGER_WAIT))
                        | (capture_sw_start & (capture_state == CAPTURE_IDLE));

logic capture_sw_reset;
logic capture_arm;
logic capture_sw_start;
logic capture_sw_stop;

logic readout_sw_reset;
logic readout_start;

assign readout_sw_reset = (readout_dma_sw_reset.data == 1) & readout_dma_sw_reset.ok;
// only accept resets during DMA state transfer
assign readout_dma_sw_reset.ready = readout_state == DMA_ACTIVE;

logic capture_full_d; // delay so we can detect rising edge when buffer first fills up
always_ff @(posedge capture_clk) capture_full_d <= capture_full;

logic capture_done; // pulse, goes high when either capture_stop is asserted, or when capture_full goes high
logic readout_capture_done_sync; // synchronized capture_done to readout clock domain

logic readout_dma_done;
assign readout_dma_done = readout_data.last & readout_data.ok;
logic capture_dma_done_sync; // synchronized

always_ff @(posedge capture_clk) begin
  if (capture_reset) begin
    capture_done <= 1'b0;
  end else begin
    if ((capture_full & ~capture_full_d) | capture_stop) begin
      // we don't need edge detection for capture_stop, since capture_stop
      // will trigger a state transfer for capture_state which will reset
      // capture_stop
      capture_done <= 1'b1;
    end else begin
      capture_done <= 1'b0;
    end
  end
end

buffer_core #(
  .CHANNELS(CHANNELS),
  .BUFFER_DEPTH(BUFFER_DEPTH),
  .DATA_WIDTH(DATA_WIDTH),
  .READ_LATENCY(READ_LATENCY)
) buffer_core_i (
  .capture_clk,
  .capture_reset,
  .capture_data,
  .capture_active_channels,
  .capture_start,
  .capture_stop,
  .capture_full,
  .capture_write_depth,
  .capture_sw_reset,
  .readout_clk,
  .readout_reset,
  .readout_data,
  .readout_sw_reset,
  .readout_start
);

// capture state machine
always_ff @(posedge capture_clk) begin
  if (capture_reset) begin
    capture_state <= CAPTURE_IDLE;
  end else begin
    if (capture_sw_reset) begin
      capture_state <= CAPTURE_IDLE;
    end else begin
      unique case (capture_state)
        CAPTURE_IDLE: begin
          // if we get an arm signal, go to TRIGGER_WAIT
          // if we get a sw_start signal, go to SAVE_SAMPLES
          if (capture_arm) begin
            capture_state <= TRIGGER_WAIT;
          end else if (capture_start) begin
            // for capture_state == CAPTURE_IDLE, capture_start can
            // only be asserted from sw_start, since hw_start is
            // gated by capture_state == TRIGGER_WAIT
            capture_state <= SAVE_SAMPLES;
          end
        end
        TRIGGER_WAIT:
          // if we get a hw_start signal or a sw_start signal, go to
          // SAVE_SAMPLES
          if (capture_start) begin
            capture_state <= SAVE_SAMPLES;
          end
        SAVE_SAMPLES:
          // if we get capture_stop or buffer is full, go to HOLD_SAMPLES
          if (capture_stop | capture_full) capture_state <= HOLD_SAMPLES;
        HOLD_SAMPLES:
          // if we get capture_dma_done_sync, go to CAPTURE_IDLE
          if (capture_dma_done_sync) capture_state <= CAPTURE_IDLE;
      endcase
    end
  end
end

// accept DMA start only when we're ready (i.e. the buffer has valid data in it)
assign readout_dma_start.ready = readout_state == DMA_READY;
always_ff @(posedge readout_clk) begin
  if (readout_reset) begin
    readout_start <= 1'b0;
  end else begin
    if (readout_dma_start.ok & (readout_dma_start.data == 1)) begin
      readout_start <= 1'b1;
    end else begin
      readout_start <= 1'b0;
    end
  end
end

// readout state machine
always_ff @(posedge readout_clk) begin
  if (readout_reset) begin
  end else begin
    unique case (readout_state)
      // stay in IDLE until capture completes (either from a sw_stop or by
      // filling up the buffer)
      DMA_IDLE: if (readout_capture_done_sync) readout_state <= DMA_READY;
      // wait until dma_start register is written to before enabling readout
      DMA_READY: if (readout_dma_start.ok & (readout_dma_start.data == 1)) readout_state <= DMA_ACTIVE;
      DMA_ACTIVE: begin
        // in case there are any issues with the DMA and it doesn't complete,
        // the user can reset the readout logic and try again
        if (readout_sw_reset) begin
          readout_state <= DMA_READY;
        end else begin
          if (readout_dma_done) begin
            readout_state <= DMA_IDLE;
          end
        end
      end
    endcase
  end
end

// synchronize sw_reset for capture to capture clock domain
Axis_If #(.DWIDTH(1)) capture_sw_reset_sync();
assign capture_sw_reset_sync.ready = 1'b1; // always accept reset
assign capture_sw_reset = (capture_sw_reset_sync.data == 1) & (capture_sw_reset_sync.ok);
// clock domain crossing
axis_config_reg_cdc #(
  .DWIDTH(1)
) capture_sw_reset_cdc_i (
  .src_clk(readout_clk),
  .src_reset(readout_reset),
  .src(readout_capture_sw_reset),
  .dest_clk(capture_clk),
  .dest_reset(capture_reset),
  .dest(capture_sw_reset_sync)
);

// synchronize arm/sw_start/sw_stop to capture clock domain
Axis_If #(.DWIDTH(3)) capture_arm_sw_start_stop_sync();
// accept stop in any of the following states. sw_start and arm have
// additional logic that renders assertion of these subsignals ineffective
// outside of CAPTURE_IDLE and/or TRIGGER_WAIT
assign capture_arm_sw_start_stop_sync.ready = (capture_state == CAPTURE_IDLE)
                                              | (capture_state == TRIGGER_WAIT)
                                              | (capture_state == SAVE_SAMPLES);
always_comb begin
  if (capture_arm_sw_start_stop_sync.ok) begin
    capture_arm = capture_arm_sw_start_stop_sync.data[2] == 1;
    capture_sw_start = capture_arm_sw_start_stop_sync.data[1] == 1;
    capture_sw_stop = capture_arm_sw_start_stop_sync.data[0] == 1;
  end else begin
    capture_arm = 1'b0;
    capture_sw_start = 1'b0;
    capture_sw_stop = 1'b0;
  end
end
// clock domain crossing
axis_config_reg_cdc #(
  .DWIDTH(3)
) capture_arm_sw_start_stop_cdc_i (
  .src_clk(readout_clk),
  .src_reset(readout_reset),
  .src(readout_capture_arm_sw_start_stop),
  .dest_clk(capture_clk),
  .dest_reset(capture_reset),
  .dest(capture_arm_sw_start_stop_sync)
);

// synchronize banking mode and convert it to a number of active channels
Axis_If #(.DWIDTH($clog2($clog2(CHANNELS+1)))) capture_banking_mode ();
assign capture_banking_mode.ready = capture_state == CAPTURE_IDLE;
assign capture_active_channels = 1 << capture_banking_mode.data;
axis_config_reg_cdc #(
  .DWIDTH($clog2($clog2(CHANNELS+1)))
) banking_mode_cdc_i (
  .src_clk(readout_clk),
  .src_reset(readout_reset),
  .src(readout_banking_mode),
  .dest_clk(capture_clk),
  .dest_reset(capture_reset),
  .dest(capture_banking_mode)
);

// synchronize write depth to readout clock domain
Axis_If #(.DWIDTH(CHANNELS*($clog2(BUFFER_DEPTH)+1))) capture_write_depth_if();
assign capture_write_depth_if.data = capture_write_depth;
assign capture_write_depth_if.valid = capture_done; // only go high for one cycle at the end of each capture
assign capture_write_depth_if.last = 1'b1; // always send a full packet
axis_config_reg_cdc #(
  .DWIDTH(CHANNELS*($clog2(BUFFER_DEPTH)+1))
) capture_write_depth_cdc_i (
  .src_clk(capture_clk),
  .src_reset(capture_reset),
  .src(capture_write_depth_if),
  .dest_clk(readout_clk),
  .dest_reset(readout_reset),
  .dest(readout_write_depth)
);

// synchronize capture_done
xpm_cdc_pulse #(
  .DEST_SYNC_FF(4), // 4 synchronization stages
  .INIT_SYNC_FF(0), // don't allow behavioral initialization
  .REG_OUTPUT(1), // register the output
  .RST_USED(1), // use resets
  .SIM_ASSERT_CHK(1) // report potential violations
) capture_done_cdc_i (
  .src_clk(capture_clk),
  .src_rst(capture_reset),
  .src_pulse(capture_done),
  .dest_clk(readout_clk),
  .dest_rst(readout_reset),
  .dest_pulse(readout_capture_done_sync)
);

// synchronize dma_done
xpm_cdc_pulse #(
  .DEST_SYNC_FF(4), // 4 synchronization stages
  .INIT_SYNC_FF(0), // don't allow behavioral initialization
  .REG_OUTPUT(1), // register the output
  .RST_USED(1), // use resets
  .SIM_ASSERT_CHK(1) // report potential violations
) dma_done_cdc_i (
  .src_clk(readout_clk),
  .src_rst(readout_reset),
  .src_pulse(readout_dma_done),
  .dest_clk(capture_clk),
  .dest_rst(capture_reset),
  .dest_pulse(capture_dma_done_sync)
);

endmodule
