// triangle_test.sv - Reed Foster
// Test triangle wave generator

import sim_util_pkg::*;

`timescale 1ns/1ps

module triangle_test ();

sim_util_pkg::debug debug = new(DEFAULT);
sim_util_pkg::math #(int) math;

logic dac_reset;
logic dac_clk = 0;
localparam DAC_CLK_RATE_HZ = 384_000_000;
always #(0.5s/DAC_CLK_RATE_HZ) dac_clk = ~dac_clk;

logic ps_reset;
logic ps_clk = 0;
localparam PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

parameter int PHASE_BITS = 32;
parameter int CHANNELS = 2;
parameter int PARALLEL_SAMPLES = 4;
parameter int SAMPLE_WIDTH = 16;

Axis_If #(.DWIDTH(PHASE_BITS*CHANNELS)) ps_phase_inc ();
Axis_Parallel_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH), .CHANNELS(CHANNELS)) dac_data_out ();
logic [CHANNELS-1:0] dac_trigger;

triangle #(
  .PHASE_BITS(PHASE_BITS),
  .CHANNELS(CHANNELS),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SAMPLE_WIDTH(SAMPLE_WIDTH)
) dut_i (
  .ps_clk,
  .ps_reset,
  .ps_phase_inc,
  .dac_clk,
  .dac_reset,
  .dac_data_out,
  .dac_trigger
);

logic [CHANNELS-1:0][PHASE_BITS-1:0] phase_increment;
int trigger_times [CHANNELS][$];
typedef logic signed [SAMPLE_WIDTH-1:0] sample_t;
sample_t samples_received [CHANNELS][$];
logic save_data;

assign phase_increment = {CHANNELS{32'h00080000}};

always @(posedge dac_clk) begin
  if (save_data) begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
        samples_received[channel].push_front(sample_t'(dac_data_out.data[channel][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
      end
    end
  end
end

task automatic check_results ();
  enum {UP, DOWN} direction;
  sample_t last_sample;
  int sample_count;
  // actually check that we're producing the correct output
  for (int channel = 0; channel < CHANNELS; channel++) begin
    debug.display($sformatf("channel %0d: trigger_times.size() = %0d", channel, trigger_times[channel].size()), DEBUG);
    last_sample = {1'b1, {(SAMPLE_WIDTH-1){1'b0}}};
    sample_count = 0;
    direction = UP;
    while (samples_received[channel].size() > 0) begin
      debug.display($sformatf(
        "channel %0d: sample pair %x, %x (%0d, %0d)",
        channel,
        samples_received[channel][$],
        last_sample,
        samples_received[channel][$],
        last_sample),
        DEBUG
      );
      case (direction)
        UP: begin
          if (samples_received[channel][$] < last_sample) begin
            // if we're near the edge, then that's okay
            if (last_sample < ({1'b0, {(SAMPLE_WIDTH-1){1'b1}}} - phase_increment[PHASE_BITS-1-:SAMPLE_WIDTH])) begin
              // not okay
              debug.error($sformatf(
                "channel %0d: samples should be increasing, but decreasing pair %x, %x",
                channel,
                last_sample,
                samples_received[channel][$])
              );
            end else begin
              // okay
              direction = DOWN;
            end
          end
          if ((samples_received[channel][$] >= 0) & (last_sample < 0)) begin
            debug.display($sformatf(
              "channel %0d: got a zero-crossing %x, %x",
              channel,
              samples_received[channel][$],
              last_sample),
              DEBUG
            );
            // check for trigger if we crossed zero
            // if the trigger time is within PARALLEL_SAMPLES of the actual
            // time, then that's okay
            if (trigger_times[channel].size() > 0) begin
              if (math.abs(trigger_times[channel][$] - sample_count) > PARALLEL_SAMPLES) begin
                debug.error($sformatf(
                  "channel %0d: got incorrect trigger time, current sample count is %0d, but trigger_time is %0d",
                  channel,
                  sample_count,
                  trigger_times[channel][$])
                );
              end
              trigger_times[channel].pop_back();
            end else begin
              debug.error($sformatf(
                "channel %0d: expected a trigger event, but no trigger times left",
                channel)
              );
            end
          end
        end
        DOWN: begin
          if (samples_received[channel][$] > last_sample) begin
            // if we're near the edge, then that's okay
            if (last_sample > ({1'b1, {(SAMPLE_WIDTH-1){1'b0}}} + phase_increment[PHASE_BITS-1-:SAMPLE_WIDTH])) begin
              // not okay
              debug.error($sformatf(
                "channel %0d: samples should be decreasing, but increasing pair %x, %x",
                channel,
                last_sample,
                samples_received[channel][$])
              );
            end else begin
              // okay
              direction = UP;
            end
          end
        end
      endcase
      last_sample = samples_received[channel][$];
      samples_received[channel].pop_back();
      sample_count++;
    end
    // if any leftover triggers, raise an error
    if (trigger_times[channel].size() > 0) begin
      debug.error($sformatf(
        "channel %0d: got %0d leftover trigger events that weren't expected",
        channel,
        trigger_times[channel].size())
      );
      while (trigger_times[channel].size() > 0) trigger_times[channel].pop_back();
    end
  end
endtask

initial begin
  debug.display("### TESTING TRIANGLE WAVE GENERATOR ###", DEFAULT);
  ps_reset <= 1'b1;
  dac_reset <= 1'b1;
  ps_phase_inc.valid <= 1'b0;
  save_data = 0;
  repeat (100) @(posedge ps_clk);
  ps_reset <= 1'b0;
  @(posedge dac_clk);
  dac_reset <= 1'b0;
  @(posedge ps_clk);
  // send some data
  ps_phase_inc.data <= phase_increment; // increment by 8
  ps_phase_inc.valid <= 1'b1;
  @(posedge ps_clk);
  ps_phase_inc.valid <= 1'b0;
  while (dac_data_out.data === '0) @(posedge dac_clk);
  save_data = 1;
  // check data
  repeat (20) begin
    while (dac_trigger === '0) @(posedge dac_clk);
    for (int channel = 0; channel < CHANNELS; channel++) begin
      if (dac_trigger[channel] === 1'b1) begin
        trigger_times[channel].push_front(samples_received[channel].size());
      end
    end
    @(posedge dac_clk);
  end
  check_results();
  debug.finish();
end

endmodule
