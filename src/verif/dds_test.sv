import sim_util_pkg::*;

`timescale 1ns / 1ps
module dds_test ();

localparam PHASE_BITS = 24;
localparam OUTPUT_WIDTH = 18;
localparam QUANT_BITS = 8;
localparam PARALLEL_SAMPLES = 4;
localparam LUT_ADDR_BITS = PHASE_BITS - QUANT_BITS;
localparam LUT_DEPTH = 2**LUT_ADDR_BITS;

typedef logic signed [OUTPUT_WIDTH-1:0] sample_t;
typedef logic [PHASE_BITS-1:0] phase_t;

sim_util_pkg::generic #(sample_t) util; // abs, max functions on sample_t
sim_util_pkg::debug #(.VERBOSITY(DEFAULT)) dbg = new; // printing, error tracking

logic reset;
logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

Axis_If #(.DWIDTH(PHASE_BITS)) phase_inc_in();
Axis_If #(.DWIDTH(OUTPUT_WIDTH*PARALLEL_SAMPLES)) cos_out();

// easier debugging in waveform view
sample_t cos_out_split [PARALLEL_SAMPLES];
always_comb begin
  for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
    cos_out_split[i] <= cos_out.data[OUTPUT_WIDTH*i+:OUTPUT_WIDTH];
  end
end

dds #(.PHASE_BITS(PHASE_BITS), .OUTPUT_WIDTH(OUTPUT_WIDTH), .QUANT_BITS(QUANT_BITS)) dut_i (
  .clk,
  .reset,
  .cos_out,
  .phase_inc_in
);

localparam int N_FREQS = 4;
int freqs [N_FREQS] = {12_130_000, 517_036_000, 1_729_725_000, 2_759_000};

phase_t phase_inc, phase_inc_prev, phase;
sample_t received [$];

localparam real PI = 3.14159265;

function phase_t get_phase_inc_from_freq(input int freq);
  return unsigned'(int'($floor((real'(freq)/6_400_000_000.0) * (2**(PHASE_BITS)))));
endfunction

always @(posedge clk) begin
  if (reset) begin
    phase_inc <= '0;
  end else begin
    if (phase_inc_in.ok) begin
      phase_inc <= phase_inc_in.data;
    end
    if (cos_out.ok) begin
      for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
        received.push_front(sample_t'(cos_out.data[i*OUTPUT_WIDTH+:OUTPUT_WIDTH]));
      end
    end
  end
end

task automatic check_output(inout phase_t phase, input phase_t phase_inc, input phase_t phase_inc_prev);
  sample_t expected;
  int count;
  count = 0;
  dbg.display($sformatf(
    "checking output with initial phase %x, phase_inc %x, phase_inc_prev %x",
    phase,
    phase_inc,
    phase_inc_prev),
    VERBOSE
  );
  while (received.size() > 0) begin
    // first four 12 samples are with previous phase inc
    expected = sample_t'($floor((2**(OUTPUT_WIDTH-1) - 0.5)*$cos(2*PI/real'(2**PHASE_BITS)*real'(phase))-0.5));
    if (util.abs(received[$] - expected) > 4'hf) begin
      dbg.error($sformatf(
        "mismatched sample value for phase = %x: expected %x got %x",
        phase,
        expected,
        received[$])
      );
    end
    dbg.display($sformatf(
      "got phase/sample pair: %x, %x",
      phase,
      received[$]),
      DEBUG
    );
    // 5 cycles of latency
    if (count < 4*PARALLEL_SAMPLES) begin
      phase = phase + phase_inc_prev;
    end else begin
      phase = phase + phase_inc;
    end
    received.pop_back();
    count = count + 1;
  end
endtask

initial begin
  dbg.display("################################", DEFAULT);
  dbg.display("# testing dds signal generator #", DEFAULT);
  dbg.display("################################", DEFAULT);
  reset <= 1'b1;
  cos_out.ready <= 1'b0;
  phase <= '0;
  phase_inc_prev <= '0;
  repeat (50) @(posedge clk);
  reset <= 1'b0;
  repeat (20) @(posedge clk);
  for (int i = 0; i < N_FREQS; i++) begin
    phase_inc_in.data <= get_phase_inc_from_freq(freqs[i]);
    phase_inc_in.valid <= 1;
    repeat (1) @(posedge clk);
    phase_inc_in.valid <= 0;
    repeat (100) @(posedge clk);
    // wait a few cycles before asserting cos_out.ready to ensure that any
    // phase_inc changes have propagated
    // this makes it easier to test for correct behavior
    // TODO actually implement the correct latency tracking so that the
    // verification works properly regardless of whether the phase increment
    // is changed while the output is active
    cos_out.ready <= 1'b1;
    repeat (100) begin
      @(posedge clk);
      cos_out.ready <= $urandom_range(0,1) & 1'b1;
    end
    cos_out.ready <= 1'b1;
    repeat (100) @(posedge clk);
    cos_out.ready <= 1'b0;
    repeat (100) @(posedge clk);
    dbg.display($sformatf(
      "checking behavior for freq = %0d Hz",
      freqs[i]),
      VERBOSE
    );
    check_output(phase, phase_inc, phase_inc_prev);
    phase_inc_prev <= phase_inc;
  end
  dbg.finish();
end

endmodule
