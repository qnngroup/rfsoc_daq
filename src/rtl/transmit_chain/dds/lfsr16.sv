// lfsr16.sv - Reed Foster
// 16-bit maximal LFSR, used for DDS module as a phase-dither signal

`timescale 1ns/1ps
module lfsr16_parallel #(
  parameter int PARALLEL_SAMPLES = 4
) (
  input wire clk, reset,
  input logic enable,
  output logic [PARALLEL_SAMPLES-1:0][15:0] data_out
);

localparam [15:0] LFSR_POLY = 16'hb400;

function automatic logic [15:0] lfsr_step(input logic [15:0] state, input int N);
  // Galois right-shift LFSR: https://en.wikipedia.org/wiki/Linear-feedback_shift_register
  // equivalent C program:
  //    unsigned state;
  //    unsigned lsb = state & 1u;
  //    state >>= state;
  //    if (lsb)
  //      state ^= LFSR_POLY; // 0xb400
  for (int i = 0; i < N; i++) begin
    state = ({16{state[0]}} & LFSR_POLY) ^ {1'b0, state[15:1]};
  end
  return state;
endfunction

always @(posedge clk) begin
  if (reset) begin
    for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
      // can probably be optimized to improve timing (which may be an issue at 384MHz)
      // would need to divide LFSR length by PARALLEL_SAMPLES and space out
      // initial states by that quantity (since we want the period of the
      // dither signal to be large)
      data_out[i] <= lfsr_step(16'hace1, i);
    end
  end else begin
    if (enable) begin
      for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
        // same comment as above to improve timing
        data_out[i] <= lfsr_step(data_out[i], PARALLEL_SAMPLES);
      end
    end
  end
end

endmodule
