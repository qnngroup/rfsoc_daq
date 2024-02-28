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
  input logic ps_clk,
  Axis_If.Master ps_phase_inc,
  input logic dac_clk,
  Realtime_Parallel_If.Slave dac_data_out
);

localparam real PI = 3.14159265;

typedef logic [CHANNELS-1:0][PHASE_BITS-1:0] multi_phase_t;
typedef logic signed [PHASE_BITS-1:0] phase_t;
typedef logic signed [SAMPLE_WIDTH-1:0] sample_t;
typedef logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] burst_t;
sim_util_pkg::math #(sample_t) math; // abs, max functions on sample_t
sim_util_pkg::math #(phase_t) math_phase; // abs, max functions on phase_t
sim_util_pkg::queue #(.T(sample_t), .T2(burst_t)) data_q_util = new;

multi_phase_t phase_inc;

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

function phase_t get_phase_inc_from_freq(input int freq);
  return unsigned'(int'($floor((real'(freq)/6_400_000_000.0) * (2.0**(PHASE_BITS)))));
endfunction

task automatic clear_queues();
  receiver_i.clear_queues();
endtask

task automatic init();
  driver_i.init();
endtask

task automatic set_phases(
  inout sim_util_pkg::debug debug,
  input int freqs [CHANNELS]
);
  bit success;
  for (int channel = 0; channel < CHANNELS; channel++) begin
    phase_inc[channel] = get_phase_inc_from_freq(freqs[channel]);
  end
  debug.display($sformatf("setting phase_inc = %x", phase_inc), sim_util_pkg::VERBOSE);
  driver_i.send_sample_with_timeout(10, phase_inc, success);
  if (~success) begin
    debug.error("failed to write phase increments");
  end
endtask

function phase_t estimate_phase(
  input sample_t sample
);
  return phase_t'($acos((real'(sample) + 0.5) / (2.0**(SAMPLE_WIDTH-1) - 0.5))/(2.0*PI)*(2.0**PHASE_BITS));
endfunction

task automatic check_output(
  inout sim_util_pkg::debug debug,
  input sample_t max_error
);
  phase_t phase, dphase;
  logic [PHASE_BITS*2-1:0] phase_corrected;
  int correction_bits;
  sample_t expected;
  sample_t received [$];
  for (int channel = 0; channel < CHANNELS; channel++) begin
    debug.display($sformatf("checking output for channel %0d", channel), sim_util_pkg::DEBUG);
    // first convert receiver_i.data_q[channel] to samples
    data_q_util.samples_from_batches(receiver_i.data_q[channel], received, SAMPLE_WIDTH, PARALLEL_SAMPLES);

    // get close to a zero-crossing to get better estimate of the phase
    while ((received[$] > received[$-1]) || (math.abs(received[$]) > 16'h00ff))  begin
      received.pop_back();
    end
    if (received.size() < 1025) begin
      debug.error("not enough values left to test, please increase number of samples captured");
    end
    // estimate initial phase
    phase = estimate_phase(received[$]);
    dphase = estimate_phase(received[$-1]) - phase;
    // correct phase by averaging phase estimated from multiple samples
    // 2**correction_bits is a rough heuristic for the appropriate number of
    // samples needed to create an accurate estimate
    correction_bits = PHASE_BITS - 2 - $clog2(phase_inc[channel]);
    // clip sample count to [1,64]
    correction_bits = (correction_bits > 8) ? 8 : ((correction_bits < 0) ? 0 : correction_bits);
    // get average phase from multiple samples
    phase_corrected = '0;
    for (int i = 0; i < 2**correction_bits; i++) begin
      phase_corrected += estimate_phase(received[$-i]);
      phase_corrected += (dphase < 0) ? phase_inc[channel]*i : -phase_inc[channel]*i;
    end
    phase_corrected = phase_corrected / (2**correction_bits);
    debug.display($sformatf(
      "correcting initial phase estimate %x to %x (using %0d samples)",
      phase,
      phase_corrected[PHASE_BITS-1:0],
      2**correction_bits),
      sim_util_pkg::VERBOSE
    );
    phase = phase_corrected[PHASE_BITS-1:0];
    // if the difference in phase was negative, then we're on the wrong side of the unit circle
    if (dphase < 0) begin
      phase = phase_t'((2.0**PHASE_BITS) - real'(phase));
    end
    debug.display($sformatf(
      "checking output with initial phase %x, phase_inc %x, dphase = %x (abs %x)",
      phase,
      phase_inc[channel],
      dphase,
      math_phase.abs(dphase)),
      sim_util_pkg::VERBOSE
    );
    // check data
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
