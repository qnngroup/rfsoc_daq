// dds.sv - Reed Foster
// Direct Digital Synthesis module, uses phase dithering with a maximal LFSR
// to achieve high spectral purity.

`timescale 1ns/1ps
module dds #(
  parameter int PHASE_BITS = 32,
  parameter int SAMPLE_WIDTH = 16,
  parameter int QUANT_BITS = 20,
  parameter int PARALLEL_SAMPLES = 16,
  parameter int CHANNELS = 8
) (
  input wire clk, reset,
  Realtime_Parallel_If.Master data_out,
  Axis_If.Slave phase_inc_in
);

assign phase_inc_in.ready = 1'b1; // always accept new phase increment

localparam int LUT_ADDR_BITS = PHASE_BITS - QUANT_BITS;
localparam int LUT_DEPTH = 2**LUT_ADDR_BITS;

genvar channel;
generate
  for (channel = 0; channel < CHANNELS; channel++) begin
    // generate LUT for phase -> cos(phase) conversion
    // LUT entries are indexed normalized to 2*pi (so 4x more space is used than
    // necessary, but it simplifies phase-wrapping and dithering for high SFDR
    // signal synthesis)
    localparam real PI = 3.14159265;
    logic signed [SAMPLE_WIDTH-1:0] lut [LUT_DEPTH];
    initial begin
      for (int i = 0; i < LUT_DEPTH; i = i + 1) begin
        lut[i] = SAMPLE_WIDTH'(signed'(int'($floor($cos(2*PI/(LUT_DEPTH)*i)*(2**(SAMPLE_WIDTH-1) - 0.5) - 0.5))));
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
    
    // delay data_valid to match phase increment + LUT latency
    logic [4:0] data_valid;
    assign data_out.valid[channel] = data_valid[4];
    
    always_ff @(posedge clk) begin
      if (reset) begin
        phase_inc <= '0;
        cycle_phase <= '0;
        sample_phase <= '0;
        data_valid <= '0;
      end else begin
        // if there's a new phase_inc, load it
        if (phase_inc_in.valid) begin
          for (int i = 0; i < PARALLEL_SAMPLES; i = i + 1) begin
            // phase_inc[0] = 1*phase_in_in.data
            // phase_inc[1] = 2*phase_in_in.data
            // ...
            // the final entry in phase_inc is used to update the cycle_phase
            phase_inc[i] <= PHASE_BITS'(phase_inc_in.data[channel*PHASE_BITS+:PHASE_BITS] * (i + 1));
          end
        end
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
    
    // Dither LFSR, used to add a random offset to the phase before quantization
    // that changes each cycle. This improves the SFDR by spreading the spectrum
    // of the phase quantization noise
    logic [PARALLEL_SAMPLES-1:0][15:0] lfsr;
    lfsr16_parallel #(.PARALLEL_SAMPLES(PARALLEL_SAMPLES)) lfsr_i (
      .clk,
      .reset,
      .enable(1'b1), // always update
      .data_out(lfsr)
    );
    
    logic [PARALLEL_SAMPLES-1:0][PHASE_BITS-1:0] phase_dithered, phase_dithered_d;
    logic [PARALLEL_SAMPLES-1:0][LUT_ADDR_BITS-1:0] phase_quant;
    if (QUANT_BITS > 16) begin
      always_comb begin
        for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
          // if the number of bits that are quantized is more than the
          // LFSR width, left-shift the LFSR output so that it has the
          // correct amplitude
          assign phase_dithered[i] = {{(PHASE_BITS-QUANT_BITS){1'b0}}, lfsr[i], {(QUANT_BITS - 16){1'b0}}} + sample_phase[i];
        end
      end
    end else begin
      always_comb begin
        for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
          // otherwise, right shift the LFSR
          assign phase_dithered[i] = {{(PHASE_BITS-QUANT_BITS){1'b0}}, lfsr[i][QUANT_BITS-1:0]} + sample_phase[i];
        end
      end
    end

    always_ff @(posedge clk) begin
      if (reset) begin
        data_out.data[channel] <= '0;
        phase_quant <= '0;
        phase_dithered_d <= '0;
      end else begin
        phase_dithered_d <= phase_dithered;
        for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
          // quantize the phase, then perform the lookup
          phase_quant[i] <= phase_dithered_d[i][PHASE_BITS-1:QUANT_BITS];
          data_out.data[channel][SAMPLE_WIDTH*i+:SAMPLE_WIDTH] <= lut[phase_quant[i]];
        end
      end
    end
  end
endgenerate

endmodule
