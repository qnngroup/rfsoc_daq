// lfsr16.sv - Reed Foster
// 16-bit maximal LFSR, used for DDS module as a phase-dither signal
module lfsr16_parallel #(
  parameter int PARALLEL_SAMPLES = 4
) (
  input wire clk, reset,
  input logic enable,
  output logic [PARALLEL_SAMPLES-1:0][15:0] data_out
);

localparam [15:0] LFSR_POLY = 16'hb400;

function logic [15:0] lfsr_step(input logic [15:0] state);
  // Galois right-shift LFSR: https://en.wikipedia.org/wiki/Linear-feedback_shift_register
  // equivalent C program:
  //    unsigned state;
  //    unsigned lsb = state & 1u;
  //    state >>= state;
  //    if (lsb)
  //      state ^= LFSR_POLY; // 0xb400
  return ({16{state[0]}} & LFSR_POLY) ^ {1'b0, state[15:1]};
endfunction

logic [15:0] state_t;

always @(posedge clk) begin
  logic [PARALLEL_SAMPLES-1:0][15:0] state_t;
  if (reset) begin
    for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
      state_t = 16'hace1;
      // can probably be optimized to improve timing (which may be an issue at 384MHz)
      // would need to divide LFSR length by PARALLEL_SAMPLES and space out
      // initial states by that quantity (since we want the period of the
      // dither signal to be large)
      for (int j = 0; j < i; j++) begin
        state_t = lfsr_step(state_t);
      end
      data_out[i] <= state_t;
    end
  end else begin
    if (enable) begin
      for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
        state_t = data_out[i];
        // same comment as above to improve timing
        for (int j = 0; j < PARALLEL_SAMPLES; j++) begin
          state_t = lfsr_step(state_t);
        end
        data_out[i] <= state_t;
      end
    end
  end
end

endmodule
