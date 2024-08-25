// triangle_tb.sv - Reed Foster
// Triangle wave test utilities

`timescale 1ns/1ps

module triangle_tb #(
  parameter int PHASE_BITS = 32,
  parameter int CHANNELS = 8,
  parameter int PARALLEL_SAMPLES = 16,
  parameter int SAMPLE_WIDTH = 16
) (
  input logic ps_clk,
  Axis_If.Master ps_phase_inc,
  input logic dac_clk,
  input logic [CHANNELS-1:0] dac_trigger,
  Realtime_Parallel_If.Slave dac_data_out
);

typedef logic signed [SAMPLE_WIDTH-1:0] sample_t;
typedef logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] batch_t;
sim_util_pkg::math #(int) math_int;
sim_util_pkg::math #(sample_t) math_samp;
sim_util_pkg::queue #(.T(sample_t), .T2(batch_t)) data_q_util = new;

realtime_parallel_receiver #(
  .DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH),
  .CHANNELS(CHANNELS)
) receiver_i (
  .clk(dac_clk),
  .intf(dac_data_out)
);
axis_driver #(
  .DWIDTH(CHANNELS*PHASE_BITS)
) driver_i (
  .clk(ps_clk),
  .intf(ps_phase_inc)
);

batch_t trigger_values [CHANNELS][$];

always @(posedge dac_clk) begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    if (dac_trigger[channel] === 1'b1) begin
      trigger_values[channel].push_front(dac_data_out.data[channel]);
    end
  end
end

task automatic check_results (
  inout sim_util_pkg::debug debug,
  input logic [CHANNELS-1:0][PHASE_BITS-1:0] phase_increment
);
  enum {UP, DOWN} direction;
  sample_t recv [$];
  sample_t last_sample;
  bit in_trigger_values;
  // actually check that we're producing the correct output
  for (int channel = 0; channel < CHANNELS; channel++) begin
    data_q_util.samples_from_batches(receiver_i.data_q[channel], recv, SAMPLE_WIDTH, PARALLEL_SAMPLES);
    debug.display($sformatf(
      "channel %0d: trigger_values.size() = %0d",
      channel,
      trigger_values[channel].size()),
      sim_util_pkg::DEBUG
    );
    // pop first two samples to get direction
    last_sample = recv.pop_back();
    if (recv[$] > last_sample) begin
      direction = UP;
    end else begin
      direction = DOWN;
    end
    if ((last_sample > 0) && (phase_increment[channel] > last_sample)) begin
      // might've missed a zero crossing and accidentally gotten a timestamp
      // for it. If so, just pop the last element in trigger_values[channel]
      in_trigger_values = 1'b0;
      for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
        if (last_sample === trigger_values[channel][$][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH]) begin
          in_trigger_values = 1'b1;
        end
      end
      if (in_trigger_values) begin
        trigger_values[channel].pop_back();
      end
    end
    while (recv.size() > 0) begin
      debug.display($sformatf(
        "channel %0d: sample pair %x, %x (%0d, %0d)",
        channel,
        recv[$],
        last_sample,
        recv[$],
        last_sample),
        sim_util_pkg::DEBUG
      );
      if ($isunknown(recv[$])) begin
        debug.error("recv[$] is undefined");
      end
      // extra + 2 for rounding/truncation
      if (math_samp.abs(recv[$] - last_sample) > 2 + 2*phase_increment[channel][PHASE_BITS-1-:SAMPLE_WIDTH]) begin
        debug.error($sformatf(
        "channel %0d: sample pair with incorrect difference %x, %x; phase_inc = %x",
        channel,
        recv[$],
        last_sample,
        phase_increment[channel])
        );
      end
      case (direction)
        UP: begin
          if (recv[$] < last_sample) begin
            // if we're near the edge, then that's okay
            if (last_sample < ({1'b0, {(SAMPLE_WIDTH-1){1'b1}}} - phase_increment[channel][PHASE_BITS-1-:SAMPLE_WIDTH])) begin
              // not okay
              debug.error($sformatf(
                "channel %0d: samples should be increasing, but decreasing pair %x, %x",
                channel,
                last_sample,
                recv[$])
              );
            end else begin
              // okay
              direction = DOWN;
            end
          end
          if ((recv[$] >= 0) & (last_sample < 0)) begin
            debug.display($sformatf(
              "channel %0d: got a zero-crossing %x, %x",
              channel,
              recv[$],
              last_sample),
              sim_util_pkg::DEBUG
            );
            // check for trigger if we crossed zero
            // if recv[$] is in trigger_values[$], then we're good
            if (trigger_values[channel].size() > 0) begin
              in_trigger_values = 1'b0;
              for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
                if (recv[$] === trigger_values[channel][$][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH]) begin
                  in_trigger_values = 1'b1;
                end
              end
              if (~in_trigger_values) begin
                debug.error($sformatf(
                  "channel %0d: got incorrect trigger time, current sample is %x, but trigger_values[$] is %x",
                  channel,
                  recv[$],
                  trigger_values[channel][$])
                );
              end
              trigger_values[channel].pop_back();
            end else begin
              debug.error($sformatf(
                "channel %0d: expected a trigger event, but no triggers left",
                channel)
              );
            end
          end
        end
        DOWN: begin
          if (recv[$] > last_sample) begin
            // if we're near the edge, then that's okay
            if (last_sample > ({1'b1, {(SAMPLE_WIDTH-1){1'b0}}} + phase_increment[channel][PHASE_BITS-1-:SAMPLE_WIDTH])) begin
              // not okay
              debug.error($sformatf(
                "channel %0d: samples should be decreasing, but increasing pair %x, %x",
                channel,
                last_sample,
                recv[$])
              );
            end else begin
              // okay
              direction = UP;
            end
          end
        end
      endcase
      last_sample = recv[$];
      recv.pop_back();
    end
    // if any leftover triggers, raise an error
    if (trigger_values[channel].size() > 0) begin
      debug.error($sformatf(
        "channel %0d: got %0d leftover trigger events that weren't expected",
        channel,
        trigger_values[channel].size())
      );
      while (trigger_values[channel].size() > 0) trigger_values[channel].pop_back();
    end
  end
endtask

task automatic clear_queues();
  receiver_i.clear_queues();
  for (int channel = 0; channel < CHANNELS; channel++) begin
    while (trigger_values[channel].size() > 0) trigger_values[channel].pop_back();
  end
endtask

task automatic set_phases(
  inout sim_util_pkg::debug debug,
  input logic [CHANNELS-1:0][PHASE_BITS-1:0] phase_increment
);
  bit success;
  driver_i.send_sample_with_timeout(10, phase_increment, success);
  if (~success) begin
    debug.error("failed to write phase increments");
  end
endtask

task automatic init();
  driver_i.init();
endtask

endmodule
