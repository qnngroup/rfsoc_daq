// dds_test.sv - Reed Foster
// Check that DDS module is generating the correct sinusoidal data in steady
// state by comparing the output with a golden model based on systemverilog
// $cos() on real numbers. That is, the golden model keeps its own phase
// variable in increments it between each sample in the output stream,
// verifying that the output stream values are the correct cos(phase) quantity
// ***NOTE***
// Does not verify correct behavior of phase-transients, but this should be
// straightforward to implement by tracking the latency from changing the
// phase_inc configuration to the observable output frequency change

import sim_util_pkg::*;

`timescale 1ns / 1ps
module dds_test ();

sim_util_pkg::debug debug = new(DEFAULT); // printing, error tracking

localparam PHASE_BITS = 24;
localparam SAMPLE_WIDTH = 16;
localparam QUANT_BITS = 8;
localparam PARALLEL_SAMPLES = 4;
localparam CHANNELS = 8;

localparam LUT_ADDR_BITS = PHASE_BITS - QUANT_BITS;
localparam LUT_DEPTH = 2**LUT_ADDR_BITS;

typedef logic signed [SAMPLE_WIDTH-1:0] sample_t;
typedef logic [PHASE_BITS-1:0] phase_t;
typedef logic [CHANNELS-1:0][PHASE_BITS-1:0] multi_phase_t;

sim_util_pkg::math #(sample_t) math; // abs, max functions on sample_t

logic reset;
logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

Axis_If #(.DWIDTH(CHANNELS*PHASE_BITS)) phase_inc_in();
Realtime_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) data_out();

// easier debugging in waveform view
sample_t cos_out_split [PARALLEL_SAMPLES];
always_comb begin
  for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
    cos_out_split[i] <= data_out.data[SAMPLE_WIDTH*i+:SAMPLE_WIDTH];
  end
end

dds #(
  .PHASE_BITS(PHASE_BITS),
  .QUANT_BITS(QUANT_BITS),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) dut_i (
  .clk,
  .reset,
  .data_out,
  .phase_inc_in
);

// test data at a few different frequencies
localparam int N_FREQS = 4;
int freqs [N_FREQS] = {12_130_000, 517_036_000, 1_729_725_000, 2_759_000};

multi_phase_t phase_inc, phase_inc_prev;
sample_t received [CHANNELS][$];

localparam real PI = 3.14159265;

function phase_t get_phase_inc_from_freq(input int freq);
  return unsigned'(int'($floor((real'(freq)/6_400_000_000.0) * (2**(PHASE_BITS)))));
endfunction

logic save_data;

always @(posedge clk) begin
  if (reset) begin
    phase_inc <= '0;
  end else begin
    if (phase_inc_in.valid) begin
      phase_inc <= phase_inc_in.data;
    end
    if (save_data) begin
      for (int channel = 0; channel < CHANNELS; channel++) begin
        if (data_out.valid[channel]) begin
          for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
            received[channel].push_front(sample_t'(data_out.data[channel][i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
          end
        end
      end
    end
  end
end

task automatic check_output(
  input multi_phase_t phase_inc
);
  phase_t phase, dphase;
  sample_t expected;
  for (int channel = 0; channel < CHANNELS; channel++) begin
    debug.display($sformatf("checking output for channel %0d", channel), DEBUG);
    // get close to a zero-crossing to get better estimate of the phase
    while ((math.abs(received[channel][$]) > math.abs(received[channel][$-1]))
            || (math.abs(received[channel][$]) > 12'hfff)) received[channel].pop_back();
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
      VERBOSE
    );
    while (received[channel].size() > 0) begin
      expected = sample_t'($floor((2.0**(SAMPLE_WIDTH-1) - 0.5)*$cos(2.0*PI/real'(2.0**PHASE_BITS)*real'(phase))-0.5));
      if (math.abs(received[channel][$] - expected) > 3'h7) begin
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
        DEBUG
      );
      phase = phase + phase_inc[channel];
      received[channel].pop_back();
    end
  end
endtask

initial begin
  debug.display("### TESTING DDS SIGNAL GENERATOR ###", DEFAULT);
  reset <= 1'b1;
  phase_inc_prev <= '0;
  save_data <= 1'b0;
  repeat (50) @(posedge clk);
  reset <= 1'b0;
  repeat (20) @(posedge clk);
  for (int i = 0; i < N_FREQS; i++) begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      phase_inc_in.data[channel*PHASE_BITS+:PHASE_BITS] <= get_phase_inc_from_freq(freqs[$urandom_range(0,N_FREQS-1)]);
    end
    phase_inc_in.valid <= 1'b1;
    repeat (1) @(posedge clk);
    phase_inc_in.valid <= 1'b0;
    repeat (5) @(posedge clk);
    save_data <= 1'b1;
    repeat (1000) @(posedge clk);
    check_output(phase_inc);
    save_data <= 1'b0;
  end
  debug.finish();
end

endmodule
