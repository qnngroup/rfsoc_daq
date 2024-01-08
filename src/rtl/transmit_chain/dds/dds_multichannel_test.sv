// dds_multichannel_test.sv - Reed Foster
// Check multichannel DDS module is working correctly

import sim_util_pkg::*;

`timescale 1ns / 1ps
module dds_multichannel_test ();

sim_util_pkg::debug debug = new(DEFAULT); // printing, error tracking

localparam PHASE_BITS = 24;
localparam SAMPLE_WIDTH = 18;
localparam QUANT_BITS = 8;
localparam PARALLEL_SAMPLES = 4;
localparam CHANNELS = 2;
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

Axis_If #(.DWIDTH(PHASE_BITS*CHANNELS)) phase_inc_in();
Axis_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) data_out();

// easier debugging in waveform view
sample_t data_out_split [CHANNELS][PARALLEL_SAMPLES];
always_comb begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
      data_out_split[channel][sample] = data_out.data[channel][SAMPLE_WIDTH*sample+:SAMPLE_WIDTH];
    end
  end
end

dds_multichannel #(
  .PHASE_BITS(PHASE_BITS),
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .QUANT_BITS(QUANT_BITS),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) dut_i (
  .clk,
  .reset,
  .data_out,
  .phase_inc_in
);

// test data at a few different frequencies
localparam int N_FREQS = 8;
int freqs [N_FREQS] = {
  12_130_000,
  517_036_000,
  1_729_725_000,
  2_759_000,
  127_420,
  8_143_219,
  14_892_357,
  764_987_640
};

multi_phase_t phase_inc, phase_inc_prev, phase;
sample_t received [CHANNELS][$];

localparam real PI = 3.14159265;

function phase_t get_phase_inc_from_freq(input int freq);
  return unsigned'(int'($floor((real'(freq)/6_400_000_000.0) * (2**(PHASE_BITS)))));
endfunction

always @(posedge clk) begin
  if (reset) begin
    phase_inc <= '0;
  end else begin
    if (phase_inc_in.valid) begin
      phase_inc <= phase_inc_in.data;
    end
    for (int channel = 0; channel < CHANNELS; channel++) begin
      if (data_out.ok[channel]) begin
        for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
          received[channel].push_front(sample_t'(data_out.data[channel][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
        end
      end
    end
  end
end

task automatic check_output(inout multi_phase_t phase, input multi_phase_t phase_inc, input multi_phase_t phase_inc_prev);
  sample_t expected;
  int count;

  for (int channel = 0; channel < CHANNELS; channel++) begin
    count = 0;
    debug.display($sformatf(
      "channel %0d: checking output with initial phase %x, phase_inc %x, phase_inc_prev %x",
      channel,
      phase[channel],
      phase_inc[channel],
      phase_inc_prev[channel]),
      VERBOSE
    );
    while (received[channel].size() > 0) begin
      expected = sample_t'($floor((2**(SAMPLE_WIDTH-1) - 0.5)*$cos(2*PI/real'(2**PHASE_BITS)*real'(phase[channel]))-0.5));
      if (math.abs(received[channel][$] - expected) > 4'hf) begin
        debug.error($sformatf(
          "mismatched sample value for phase = %x: expected %x got %x",
          phase[channel],
          expected,
          received[channel][$])
        );
      end
      debug.display($sformatf(
        "got phase/sample pair: %x, %x",
        phase[channel],
        received[channel][$]),
        DEBUG
      );
      // first few samples are with previous phase inc:
      // 5 cycles of latency
      if (count < 4*PARALLEL_SAMPLES) begin
        phase[channel] = phase[channel] + phase_inc_prev[channel];
      end else begin
        phase[channel] = phase[channel] + phase_inc[channel];
      end
      received[channel].pop_back();
      count = count + 1;
    end
  end
endtask

initial begin
  debug.display("### TESTING MULTICHANNEL DDS SIGNAL GENERATOR ###", DEFAULT);
  reset <= 1'b1;
  data_out.ready <= '0;
  phase <= '0;
  phase_inc_prev <= '0;
  repeat (50) @(posedge clk);
  reset <= 1'b0;
  repeat (20) @(posedge clk);
  repeat (10) begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      phase_inc_in.data[channel*PHASE_BITS+:PHASE_BITS] <= get_phase_inc_from_freq(freqs[$urandom_range(0,N_FREQS-1)]);
    end
    phase_inc_in.valid <= 1'b1;
    repeat (1) @(posedge clk);
    phase_inc_in.valid <= 0;
    repeat (100) @(posedge clk);
    // wait a few cycles before asserting data_out.ready to ensure that any
    // phase_inc changes have propagated
    // this makes it easier to test for correct behavior
    // TODO actually implement the correct latency tracking so that the
    // verification works properly regardless of whether the phase increment
    // is changed while the output is active
    data_out.ready <= {CHANNELS{1'b1}};
    repeat (100) begin
      @(posedge clk);
      data_out.ready <= $urandom_range(0,4) & {CHANNELS{1'b1}};
    end
    data_out.ready <= {CHANNELS{1'b1}};
    repeat (100) @(posedge clk);
    data_out.ready <= '0;
    repeat (100) @(posedge clk);
    for (int channel = 0; channel < CHANNELS; channel++) begin
      debug.display($sformatf(
        "checking behavior for freq = %0d MHz",
        (real'(phase_inc_in.data[channel]) / 2.0**(PHASE_BITS)) * 6_400_000),
        VERBOSE
      );
    end
    check_output(phase, phase_inc, phase_inc_prev);
    phase_inc_prev <= phase_inc;
  end
  debug.finish();
end

endmodule
