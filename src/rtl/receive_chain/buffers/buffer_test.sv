// buffer_test.sv - Reed Foster
// Test for sample buffer
//
// Things to check:
//  - check capture_write_depth is correct at a variety of times between starting capture and performing DMA
//  - test sw_resets
//    - make sure capture_sw_reset can be triggered at any time
//    - make sure that dma_reset can only be triggered during an active DMA transfer
//  - test hw_start/hw_stop work correctly
//    - when asserted at the expected time, start/stop work as expected
//    - when asserted at the incorrect time, start/stop have no effect
//  - test that we get a capture_full signal when the buffers are full
//  - test that write_depth is outputted only once per capture
//    - also check that the correct number of samples were saved
//  - test that all the data we sent was saved and read out
//    - data sent between capture start and stop (from full or sw_stop)

`timescale 1ns/1ps
module buffer_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEBUG);

localparam int CHANNELS = 4;
localparam int BUFFER_DEPTH = 64;
localparam int DATA_WIDTH = 16;
localparam int READ_LATENCY = 4;

buffer_pkg::util #(
  .CHANNELS(CHANNELS),
  .BUFFER_DEPTH(BUFFER_DEPTH),
  .DATA_WIDTH(DATA_WIDTH)
) buffer_util = new;

logic capture_reset;
logic capture_clk = 0;
localparam CAPTURE_CLK_RATE_HZ = 512_000_000;
always #(0.5s/CAPTURE_CLK_RATE_HZ) capture_clk = ~capture_clk;

logic readout_reset;
logic readout_clk = 0;
localparam READOUT_CLK_RATE_HZ = 100_000_000;
always #(0.5s/READOUT_CLK_RATE_HZ) readout_clk = ~readout_clk;

Realtime_Parallel_If #(.DWIDTH(DATA_WIDTH), .CHANNELS(CHANNELS)) capture_data ();
logic capture_hw_start, capture_hw_stop; // DUT input
logic capture_full; // DUT output

Axis_If #(.DWIDTH(DATA_WIDTH)) readout_data ();
Axis_If #(.DWIDTH(3)) readout_capture_arm_sw_start_stop ();
Axis_If #(.DWIDTH($clog2($clog2(CHANNELS+1)))) readout_banking_mode ();
Axis_If #(.DWIDTH(1)) readout_capture_sw_reset ();
Axis_If #(.DWIDTH(1)) readout_dma_sw_reset ();
Axis_If #(.DWIDTH(1)) readout_dma_start ();
Axis_If #(.DWIDTH(CHANNELS*($clog2(BUFFER_DEPTH)+1))) readout_write_depth();

buffer #(
  .CHANNELS(CHANNELS),
  .BUFFER_DEPTH(BUFFER_DEPTH),
  .DATA_WIDTH(DATA_WIDTH),
  .READ_LATENCY(READ_LATENCY)
) dut_i (
  .capture_clk,
  .capture_reset,
  .capture_data,
  .capture_hw_start,
  .capture_hw_stop,
  .capture_full,
  .readout_clk,
  .readout_reset,
  .readout_data,
  .readout_capture_arm_sw_start_stop,
  .readout_banking_mode,
  .readout_capture_sw_reset,
  .readout_dma_sw_reset,
  .readout_dma_start,
  .readout_write_depth
);

// always accept write_depth info
logic [CHANNELS-1:0][$clog2(BUFFER_DEPTH):0] write_depth [$];
always @(posedge readout_clk) begin
  if (readout_write_depth.ok) begin
    write_depth.push_front(readout_write_depth.data);
  end
end

// always accept DMA data
logic [DATA_WIDTH-1:0] dma_data [$];
int dma_last_received [$];
always @(posedge readout_clk) begin
  if (readout_data.ok) begin
    dma_data.push_front(readout_data.data);
    if (readout_data.last) begin
      dma_last_received.push_front(dma_data.size());
    end
  end
end

logic capture_enabled;
logic [DATA_WIDTH-1:0] samples_sent [CHANNELS][$];
always @(posedge capture_clk) begin
  //if ((dut_i.capture_state == dut_i.SAVE_SAMPLES) & capture_enabled) begin
  if (capture_enabled) begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      if (capture_data.valid[channel]) begin
        samples_sent[channel].push_front(capture_data.data[channel]);
        capture_data.data[channel] <= $urandom_range(0, {DATA_WIDTH{1'b1}});
      end
    end
  end
end

logic [CHANNELS-1:0] capture_disable_valid;
always @(posedge capture_clk) begin
  if (capture_reset) begin
    capture_data.valid <= '0;
  end else begin
    capture_data.valid <= $urandom_range(0, {CHANNELS{1'b1}}) & (~capture_disable_valid);
  end
end
always @(posedge readout_clk) begin
  if (readout_reset) begin
    readout_data.ready <= 1'b0;
    readout_write_depth.ready <= 1'b0;
  end
  readout_data.ready <= $urandom_range(0, 1);
  readout_write_depth.ready <= $urandom_range(0, 1);
end

logic reg_write_success;

task automatic invalid_hw_start_test();
  // send hw_start
  @(posedge capture_clk);
  capture_hw_start <= 1'b1;
  @(posedge capture_clk);
  capture_hw_start <= 1'b0;
  repeat (20) @(posedge capture_clk);
  // send sw_stop
  @(posedge readout_clk);
  readout_capture_arm_sw_start_stop.send_sample_with_timeout(readout_clk, 3'b001, 10, reg_write_success);
  if (~reg_write_success) begin
    debug.error("failed to stop buffer");
  end
  repeat (100) @(posedge readout_clk);
  // check write_depth queue is empty
  if (write_depth.size() > 0) begin
    debug.error($sformatf(
      "write_depth.size() = %0d, expected no write_depth transactions",
      write_depth.size())
    );
  end
endtask

int expected_depths [CHANNELS];
logic send_complete;

initial begin
  debug.display("### TESTING BUFFER TOPLEVEL WITH FSM ###", sim_util_pkg::DEFAULT);

  // reset
  capture_reset <= 1'b1;
  readout_reset <= 1'b1;

  capture_hw_start <= 1'b0;
  capture_hw_stop <= 1'b0;

  readout_capture_arm_sw_start_stop.valid <= 1'b0;
  readout_banking_mode.valid <= 1'b0;
  readout_capture_sw_reset.valid <= 1'b0;
  readout_dma_sw_reset.valid <= 1'b0;
  readout_dma_start.valid <= 1'b0;

  capture_enabled <= 1'b0;
  capture_disable_valid <= '0;

  repeat (100) @(posedge readout_clk);
  readout_reset <= 1'b0;
  @(posedge capture_clk);
  capture_reset <= 1'b0;

  for (int banking_mode = 0; banking_mode <= $clog2(CHANNELS); banking_mode++) begin
    debug.display($sformatf("testing for banking_mode = %0d", banking_mode), sim_util_pkg::VERBOSE);
    readout_banking_mode.send_sample_with_timeout(readout_clk, banking_mode, 10, reg_write_success);
    if (~reg_write_success) begin
      debug.error("failed to write banking_mode");
    end
    // First try starting capture with hw_start when the buffer isn't in the
    // correct mode. Expected behavior: no samples captured
    debug.display("testing invalid hw start", sim_util_pkg::DEBUG);
    invalid_hw_start_test();
    //
    // arm for capture
    debug.display("arming for capture", sim_util_pkg::DEBUG);
    readout_capture_arm_sw_start_stop.send_sample_with_timeout(readout_clk, 3'b100, 10, reg_write_success);
    if (~reg_write_success) begin
      debug.error("failed to arm buffer");
    end
    //
    repeat (10) @(posedge readout_clk);
    debug.display("sending hw_start", sim_util_pkg::DEBUG);
    // send hw_start
    @(posedge capture_clk);
    capture_hw_start <= 1'b1;
    @(posedge capture_clk);
    capture_hw_start <= 1'b0;
    for (int channel = 0; channel < CHANNELS; channel++) begin
      expected_depths[channel] = 0;
    end
    //
    debug.display("waiting for full", sim_util_pkg::DEBUG);
    // wait for full
    send_complete = 1'b0;
    while (~send_complete) begin
      for (int channel = 0; channel < CHANNELS; channel++) begin
        if (capture_data.valid[channel]) begin
          if (expected_depths[channel] < BUFFER_DEPTH * (CHANNELS / (1 << banking_mode))) begin
            expected_depths[channel]++;
          end else begin
            send_complete = 1'b1;
          end
        end
      end
      @(posedge capture_clk);
    end
    while (~capture_full) @(posedge capture_clk);
    // wait a couple clock cycles for write_depth data to synchronize
    repeat (10) @(posedge readout_clk);
    debug.display("checking write_depth", sim_util_pkg::DEBUG);
    // check write_depth (make sure we have exactly 1 packet and that it has
    // the correct value)
    if (write_depth.size() !== 1) begin
      debug.error($sformatf(
        "wrong number of write_depth packets, expected exactly 1, got %0d",
        write_depth.size())
      );
    end else begin
      buffer_util.check_write_depth(debug, expected_depths, write_depth[$], 1 << banking_mode);
    end
    while (write_depth.size() > 0) write_depth.pop_back();
    capture_disable_valid <= '0;
    //
    // send sw_reset (capture)
    @(posedge readout_clk);
    debug.display("sending capture sw_reset", sim_util_pkg::DEBUG);
    readout_capture_sw_reset.send_sample_with_timeout(readout_clk, 1'b1, 10, reg_write_success);
    if (~reg_write_success) begin
      debug.error("failed to send reset to capture");
    end
    //
    @(posedge capture_clk);
    // disable valid so we're not sending samples until after sw_start
    capture_disable_valid <= '1;
    repeat (10) @(posedge readout_clk);
    // send sw_start
    debug.display("starting capture", sim_util_pkg::DEBUG);
    readout_capture_arm_sw_start_stop.send_sample_with_timeout(readout_clk, 3'b010, 10, reg_write_success);
    if (~reg_write_success) begin
      debug.error("failed to start capture");
    end
    // set capture_enabled (so we start saving in samples_sent)
    repeat (4) @(posedge capture_clk); // CDC
    // enable capture,
    capture_enabled <= 1'b1;
    @(posedge capture_clk);
    capture_disable_valid <= '0;
    // wait so we capture some samples
    repeat ($urandom_range(40, 60)) @(posedge capture_clk);
    // disable valid so that we stop sending samples
    capture_disable_valid <= '1;
    @(posedge capture_clk);
    capture_enabled <= 1'b0;
    // disable capture_enabled (so we stop saving samples_sent)
    repeat (10) @(posedge capture_clk);
    // send sw_stop
    @(posedge readout_clk);
    debug.display("stopping capture", sim_util_pkg::DEBUG);
    readout_capture_arm_sw_start_stop.send_sample_with_timeout(readout_clk, 3'b001, 10, reg_write_success);
    if (~reg_write_success) begin
      debug.error("failed to stop capture");
    end
    repeat (10) @(posedge readout_clk);
    @(posedge capture_clk);
    capture_disable_valid <= '0;
    @(posedge readout_clk);
    // check write_depth (make sure we have exactly 1 packet and that it has
    // the correct value)
    debug.display("checking write_depth", sim_util_pkg::DEBUG);
    if (write_depth.size() !== 1) begin
      debug.error($sformatf(
        "wrong number of write_depth packets, expected exactly 1, got %0d",
        write_depth.size())
      );
    end else begin
      for (int channel = 0; channel < CHANNELS; channel++) begin
        expected_depths[channel] = samples_sent[channel].size();
      end
      buffer_util.check_write_depth(debug, expected_depths, write_depth[$], 1 << banking_mode);
    end
    while (write_depth.size() > 0) write_depth.pop_back();
    //
    // start dma
    debug.display("starting DMA", sim_util_pkg::DEBUG);
    readout_dma_start.send_sample_with_timeout(readout_clk, 1'b1, 10, reg_write_success);
    if (~reg_write_success) begin
      debug.error("failed to start DMA");
    end
    //
    // do half of dma
    repeat (BUFFER_DEPTH*CHANNELS/2) begin
      do @(posedge readout_clk); while (~readout_data.ok);
    end
    //
    @(posedge readout_clk);
    // send sw_reset (readout)
    debug.display("resetting DMA", sim_util_pkg::DEBUG);
    readout_dma_sw_reset.send_sample_with_timeout(readout_clk, 1'b1, 10, reg_write_success);
    if (~reg_write_success) begin
      debug.error("failed to reset DMA");
    end
    //
    @(posedge readout_clk);
    // clear saved dma data, since we want to recapture it
    while (dma_data.size() > 0) dma_data.pop_back();
    // start dma
    debug.display("starting DMA", sim_util_pkg::DEBUG);
    readout_dma_start.send_sample_with_timeout(readout_clk, 1'b1, 10, reg_write_success);
    if (~reg_write_success) begin
      debug.error("failed to start DMA");
    end
    //
    // do full dma
    while (~(readout_data.ok & readout_data.last)) @(posedge readout_clk);
    //
    // check samples match what was sent
    repeat (10) @(posedge readout_clk);
    if (dma_last_received.size() !== 1) begin
      debug.error($sformatf(
        "expected exactly 1 tlast event on DMA, got %0d",
        dma_last_received.size())
      );
    end
    buffer_util.check_results(debug, samples_sent, dma_data, dma_last_received[$], 1 << banking_mode);
    while (dma_last_received.size() > 0) dma_last_received.pop_back();
  end
  debug.finish();
end

endmodule
