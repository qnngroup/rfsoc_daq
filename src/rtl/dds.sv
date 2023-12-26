// dds.sv - Reed Foster
// Direct Digital Synthesis module, uses phase dithering with a maximal LFSR
// to achieve high spectral purity.
module dds #(
  parameter int PHASE_BITS = 24,
  parameter int OUTPUT_WIDTH = 18,
  parameter int QUANT_BITS = 8,
  parameter int PARALLEL_SAMPLES = 4
) (
  input wire clk, reset,
  Axis_If.Master_Simple cos_out,
  Axis_If.Slave_Simple phase_inc_in
);


localparam int LUT_ADDR_BITS = PHASE_BITS - QUANT_BITS;
localparam int LUT_DEPTH = 2**LUT_ADDR_BITS;

assign phase_inc_in.ready = 1'b1;

// generate LUT for phase -> cos(phase) conversion
// LUT entries are indexed normalized to 2*pi (so 4x more space is used than
// necessary, but it simplifies phase-wrapping and dithering for high SFDR
// signal synthesis)
localparam real PI = 3.14159265;
logic signed [OUTPUT_WIDTH-1:0] lut [LUT_DEPTH];
initial begin
  for (int i = 0; i < LUT_DEPTH; i = i + 1) begin
    lut[i] = signed'(int'($floor($cos(2*PI/(LUT_DEPTH)*i)*(2**(OUTPUT_WIDTH-1) - 0.5) - 0.5)));
  end
end

// phases, one for each parallel sample
// precompute the different phase increments required for each parallel
// sample, relative to the cycle_phase offset
logic [PARALLEL_SAMPLES-1:0][PHASE_BITS-1:0] phase_inc;
// each sample_phase is the phase of an individual parallel sample
// all sample_phase outputs are derived from the cycle_phase, which is the
// only quantity that actually gets incremented
logic [PARALLEL_SAMPLES-1:0][PHASE_BITS-1:0] sample_phase;
logic [PHASE_BITS-1:0] cycle_phase;
assign phase_inc_in.ready = 1'b1;

// delay data_valid to match phase increment + LUT latency
logic [4:0] data_valid;
assign cos_out.valid = data_valid[4];

always_ff @(posedge clk) begin
  if (reset) begin
    phase_inc <= '0;
    cycle_phase <= '0;
    sample_phase <= '0;
    data_valid <= '0;
  end else begin
    // load new phase_inc
    if (phase_inc_in.ok) begin
      for (int i = 0; i < PARALLEL_SAMPLES; i = i + 1) begin
        // phase_inc[0] = 1*phase_in_in.data
        // phase_inc[1] = 2*phase_in_in.data
        // ...
        // the final entry in phase_inc is used to update the cycle_phase
        phase_inc[i] <= phase_inc_in.data * (i + 1);
      end
    end
    // whenever the output needs data (either if we're in startup and the
    // output isn't valid yet, or the receiving module is ready), increment
    // the phases in parallel
    if (cos_out.ready || ~cos_out.valid) begin
      // increment cycle_phase
      cycle_phase <= cycle_phase + phase_inc[PARALLEL_SAMPLES-1];
      // first sample_phase is just the cycle_phase, following
      // sample_phase[i>0] are derived from the cycle_phase plus some phase
      // increment
      sample_phase[0] <= cycle_phase;
      for (int i = 1; i < PARALLEL_SAMPLES; i = i + 1) begin
        sample_phase[i] <= cycle_phase + phase_inc[i-1];
      end
      // match startup latency of addition pipeline
      data_valid <= {data_valid[3:0], 1'b1};
    end
  end
end

// Dither LFSR, used to add a random offset to the phase before quantization
// that changes each cycle. This improves the SFDR by spreading the spectrum
// of the phase quantization noise
logic [PARALLEL_SAMPLES-1:0][15:0] lfsr;
lfsr16_parallel #(.PARALLEL_SAMPLES(PARALLEL_SAMPLES)) lfsr_i (
  .clk,
  .reset,
  .enable(cos_out.ready || ~cos_out.valid),
  .data_out(lfsr)
);

logic [PARALLEL_SAMPLES-1:0][PHASE_BITS-1:0] phase_dithered;
logic [PARALLEL_SAMPLES-1:0][LUT_ADDR_BITS-1:0] phase_quant;
always_ff @(posedge clk) begin
  if (reset) begin
    cos_out.data <= '0;
    phase_quant <= '0;
    phase_dithered <= '0;
  end else begin
    if (cos_out.ready || ~cos_out.valid) begin
      for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
        if (QUANT_BITS > 16) begin
          // if the number of bits that are quantized is more than the
          // LFSR width, left-shift the LFSR output so that it has the
          // correct amplitude
          phase_dithered[i] <= {lfsr[i], {(QUANT_BITS - 16){1'b0}}} + sample_phase[i];
        end else begin
          // otherwise, right shift the LFSR
          phase_dithered[i] <= lfsr[i][QUANT_BITS-1:0] + sample_phase[i];
        end
        // quantize the phase, then perform the lookup
        phase_quant[i] <= phase_dithered[i][PHASE_BITS-1:QUANT_BITS];
        cos_out.data[OUTPUT_WIDTH*i+:OUTPUT_WIDTH] <= lut[phase_quant[i]];
      end
    end
  end
end

endmodule
