// dds_pkg.sv - Reed Foster
// utilities for testing DDS module

package dds_pkg;

  class util #(
    parameter int PHASE_BITS = 24,
    parameter int SAMPLE_WIDTH = 16,
    parameter int QUANT_BITS = 8,
    parameter int PARALLEL_SAMPLES = 4,
    parameter int CHANNELS = 8
  );

    localparam real PI = 3.14159265;

    typedef logic [CHANNELS-1:0][PHASE_BITS-1:0] multi_phase_t;
    typedef logic [PHASE_BITS-1:0] phase_t;
    typedef logic signed [SAMPLE_WIDTH-1:0] sample_t;
    sim_util_pkg::math #(sample_t) math; // abs, max functions on sample_t

    task automatic check_output(
      inout sim_util_pkg::debug debug,
      input multi_phase_t phase_inc,
      inout sample_t received [CHANNELS][$],
      input sample_t max_error
    );
      phase_t phase, dphase;
      sample_t expected;
      for (int channel = 0; channel < CHANNELS; channel++) begin
        debug.display($sformatf("checking output for channel %0d", channel), sim_util_pkg::DEBUG);
        // get close to a zero-crossing to get better estimate of the phase
        while ((math.abs(received[channel][$]) > math.abs(received[channel][$-1]))
                || (math.abs(received[channel][$]) > {'0, 12'hfff})) received[channel].pop_back();
        if (received[channel].size() < 64) begin
          debug.error("not enough values left to test, please increase number of samples captured");
        end
        // estimate initial phase
        phase = phase_t'($acos((real'(sample_t'(received[channel][$])) + 0.5)
                                / (2.0**(SAMPLE_WIDTH-1) - 0.5))/(2.0*PI)*(2.0**PHASE_BITS));
        // phase difference between first and second sample
        dphase = phase_t'($acos((real'(sample_t'(received[channel][$-1])) + 0.5)
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
        while (received[channel].size() > 0) begin
          expected = sample_t'($floor((2.0**(SAMPLE_WIDTH-1) - 0.5)*$cos(2.0*PI/real'(2.0**PHASE_BITS)*real'(phase))-0.5));
          if (math.abs(received[channel][$] - expected) > max_error) begin
            debug.error($sformatf(
              "mismatched sample value for phase = %x: expected %x got %x",
              phase,
              expected,
              received[channel][$])
            );
          end
          debug.display($sformatf(
            "got phase/sample pair: %x, %x",
            phase,
            received[channel][$]),
            sim_util_pkg::DEBUG
          );
          phase = phase + phase_inc[channel];
          received[channel].pop_back();
        end
      end
    endtask

  endclass

endpackage


