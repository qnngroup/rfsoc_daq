// dds_tb.sv - Reed Foster
// utilities for testing DDS module

`timescale 1ns/1ps

module dds_tb #(
  parameter int PHASE_BITS = 24,
  parameter int SAMPLE_WIDTH = 16,
  parameter int QUANT_BITS = 8,
  parameter int PARALLEL_SAMPLES = 4,
  parameter int CHANNELS = 8
) (
  input logic clk,
  Axis_If.Master phase_inc_in,
  Realtime_Parallel_If.Slave data_out
);

  localparam real PI = 3.14159265;

  typedef logic [CHANNELS-1:0][PHASE_BITS-1:0] multi_phase_t;
  typedef logic [PHASE_BITS-1:0] phase_t;
  typedef logic signed [SAMPLE_WIDTH-1:0] sample_t;
  typedef logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] burst_t;
  sim_util_pkg::math #(sample_t) math; // abs, max functions on sample_t
  sim_util_pkg::queue #(.T(sample_t), .T2(burst_t)) data_q_util = new;

  multi_phase_t phase_inc;

  realtime_parallel_receiver #(
    .DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH),
    .CHANNELS(CHANNELS)
  ) receiver_i (
    .clk,
    .intf(data_out)
  );

  axis_driver #(
    .DWIDTH(CHANNELS*PHASE_BITS)
  ) driver_i (
    .clk,
    .intf(phase_inc_in)
  );

  function phase_t get_phase_inc_from_freq(input int freq);
    return unsigned'(int'($floor((real'(freq)/6_400_000_000.0) * (2**(PHASE_BITS)))));
  endfunction

  task automatic clear_queues();
    receiver_i.clear_queues();
  endtask

  task automatic set_phases(
    inout sim_util_pkg::debug debug,
    input int freqs [CHANNELS]
  );
    bit success;
    for (int channel = 0; channel < CHANNELS; channel++) begin
      phase_inc[channel] = get_phase_inc_from_freq(freqs[channel]);
    end
    driver_i.send_sample_with_timeout(10, phase_inc, success);
    if (~success) begin
      debug.error("failed to write phase increments");
    end
  endtask

  task automatic check_output(
    inout sim_util_pkg::debug debug,
    input sample_t max_error
  );
    phase_t phase, dphase;
    sample_t expected;
    sample_t received [$];
    for (int channel = 0; channel < CHANNELS; channel++) begin
      debug.display($sformatf("checking output for channel %0d", channel), sim_util_pkg::DEBUG);
      // first convert receiver_i.data_q[channel] to samples
      data_q_util.samples_from_batches(receiver_i.data_q[channel], received, SAMPLE_WIDTH, PARALLEL_SAMPLES);
      
      // get close to a zero-crossing to get better estimate of the phase
      while ((math.abs(received[$]) > math.abs(received[$-1]))
              || (math.abs(received[$]) > {'0, 12'hfff})) received.pop_back();
      if (received.size() < 64) begin
        debug.error("not enough values left to test, please increase number of samples captured");
      end
      // estimate initial phase
      phase = phase_t'($acos((real'(sample_t'(received[$])) + 0.5)
                              / (2.0**(SAMPLE_WIDTH-1) - 0.5))/(2.0*PI)*(2.0**PHASE_BITS));
      // phase difference between first and second sample
      dphase = phase_t'($acos((real'(sample_t'(received[$-1])) + 0.5)
                              / (2.0**(SAMPLE_WIDTH-1) - 0.5))/(2.0*PI)*(2.0**PHASE_BITS)) - phase;
      if (dphase > {1'b0, {(PHASE_BITS-1){1'b1}}}) begin
        // if the difference in phase was negative, then we're on the wrong side of the unit circle
        phase = phase_t'((2.0**PHASE_BITS) - real'(phase));
      end
      debug.display($sformatf(
        "checking output with initial phase %x, phase_inc %x",
        phase,
        phase_inc[channel]),
        sim_util_pkg::VERBOSE
      );
      while (received.size() > 0) begin
        expected = sample_t'($floor((2.0**(SAMPLE_WIDTH-1) - 0.5)*$cos(2.0*PI/real'(2.0**PHASE_BITS)*real'(phase))-0.5));
        if (math.abs(received[$] - expected) > max_error) begin
          debug.error($sformatf(
            "mismatched sample value for phase = %x: expected %x got %x",
            phase,
            expected,
            received[$])
          );
        end
        debug.display($sformatf(
          "got phase/sample pair: %x, %x",
          phase,
          received[$]),
          sim_util_pkg::DEBUG
        );
        phase = phase + phase_inc[channel];
        received.pop_back();
      end
    end
    clear_queues();
  endtask

endmodule
