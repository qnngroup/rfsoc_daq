// dds.sv - Reed Foster
// Direct Digital Synthesis module, uses phase dithering with a maximal LFSR
// to achieve high spectral purity.

`timescale 1ns/1ps
module dds #(
  parameter int PHASE_BITS = 32,
  parameter int QUANT_BITS = 20
) (
  input logic ps_clk, ps_reset,
  Axis_If.Slave ps_phase_inc,

  input logic dac_clk, dac_reset,
  Realtime_Parallel_If.Master dac_data_out
);

Axis_If #(.DWIDTH(tx_pkg::CHANNELS*PHASE_BITS)) dac_phase_inc ();
axis_config_reg_cdc #(
  .DWIDTH(tx_pkg::CHANNELS*PHASE_BITS)
) ps_to_dac_dds_phase_inc_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_phase_inc),
  .dest_clk(dac_clk),
  .dest_reset(dac_reset),
  .dest(dac_phase_inc)
);

assign dac_phase_inc.ready = 1'b1; // always accept new phase increment

localparam int LUT_ADDR_BITS = PHASE_BITS - QUANT_BITS;
localparam int LUT_DEPTH = 2**LUT_ADDR_BITS;

genvar channel;
generate
  for (channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    // generate LUT for phase -> cos(phase) conversion
    // LUT entries are indexed normalized to 2*pi (so 4x more space is used than
    // necessary, but it simplifies phase-wrapping and dithering for high SFDR
    // signal synthesis)
    localparam real PI = 3.14159265;
    tx_pkg::sample_t lut [LUT_DEPTH];
    initial begin
      for (int i = 0; i < LUT_DEPTH; i = i + 1) begin
        lut[i] = tx_pkg::sample_t'(signed'(int'($floor($cos(2*PI/(LUT_DEPTH)*i)*(2**(tx_pkg::SAMPLE_WIDTH-1) - 0.5) - 0.5))));
      end
    end
    
    // phases, one for each parallel sample
    // precompute the different phase increments required for each parallel
    // sample, relative to the dac_cycle_phase offset
    logic [tx_pkg::PARALLEL_SAMPLES-1:0][PHASE_BITS-1:0] dac_phase_inc_reg;
    // each dac_sample_phase is the phase of an individual parallel sample
    // all dac_sample_phase outputs are derived from the dac_cycle_phase, which is the
    // only quantity that actually gets incremented
    logic [tx_pkg::PARALLEL_SAMPLES-1:0][PHASE_BITS-1:0] dac_sample_phase;
    logic [PHASE_BITS-1:0] dac_cycle_phase;
    
    // delay dac_data_valid to match phase increment + LUT latency
    logic [4:0] dac_data_valid;
    assign dac_data_out.valid[channel] = dac_data_valid[4];
    
    always_ff @(posedge dac_clk) begin
      if (dac_reset) begin
        dac_phase_inc_reg <= '0;
        dac_cycle_phase <= '0;
        dac_sample_phase <= '0;
        dac_data_valid <= '0;
      end else begin
        // if there's a new dac_phase_inc_reg, load it
        if (dac_phase_inc.valid) begin
          for (int i = 0; i < tx_pkg::PARALLEL_SAMPLES; i = i + 1) begin
            // dac_phase_inc_reg[0] = 1*phase_in_in.data
            // dac_phase_inc_reg[1] = 2*phase_in_in.data
            // ...
            // the final entry in dac_phase_inc_reg is used to update the dac_cycle_phase
            dac_phase_inc_reg[i] <= PHASE_BITS'(dac_phase_inc.data[channel*PHASE_BITS+:PHASE_BITS] * (i + 1));
          end
        end
        // increment dac_cycle_phase
        dac_cycle_phase <= dac_cycle_phase + dac_phase_inc_reg[tx_pkg::PARALLEL_SAMPLES-1];
        // first dac_sample_phase is just the dac_cycle_phase, following
        // dac_sample_phase[i>0] are derived from the dac_cycle_phase plus some phase
        // increment
        dac_sample_phase[0] <= dac_cycle_phase;
        for (int i = 1; i < tx_pkg::PARALLEL_SAMPLES; i = i + 1) begin
          dac_sample_phase[i] <= dac_cycle_phase + dac_phase_inc_reg[i-1];
        end
        // match startup latency of addition pipeline
        dac_data_valid <= {dac_data_valid[3:0], 1'b1};
      end
    end
    
    // Dither LFSR, used to add a random offset to the phase before quantization
    // that changes each cycle. This improves the SFDR by spreading the spectrum
    // of the phase quantization noise
    logic [tx_pkg::PARALLEL_SAMPLES-1:0][15:0] dac_lfsr;
    lfsr16 #(.PARALLEL_SAMPLES(tx_pkg::PARALLEL_SAMPLES)) lfsr_i (
      .clk(dac_clk),
      .reset(dac_reset),
      .enable(1'b1), // always update
      .data_out(dac_lfsr)
    );
    
    logic [tx_pkg::PARALLEL_SAMPLES-1:0][PHASE_BITS-1:0] dac_phase_dithered, dac_phase_dithered_d;
    logic [tx_pkg::PARALLEL_SAMPLES-1:0][LUT_ADDR_BITS-1:0] dac_phase_quantized;
    if (QUANT_BITS > 16) begin
      always_comb begin
        for (int i = 0; i < tx_pkg::PARALLEL_SAMPLES; i++) begin
          // if the number of bits that are quantized is more than the
          // LFSR width, left-shift the LFSR output so that it has the
          // correct amplitude
          dac_phase_dithered[i] = {{(PHASE_BITS-QUANT_BITS){1'b0}}, dac_lfsr[i], {(QUANT_BITS - 16){1'b0}}} + dac_sample_phase[i];
        end
      end
    end else begin
      always_comb begin
        for (int i = 0; i < tx_pkg::PARALLEL_SAMPLES; i++) begin
          // otherwise, right shift the LFSR
          dac_phase_dithered[i] = {{(PHASE_BITS-QUANT_BITS){1'b0}}, dac_lfsr[i][QUANT_BITS-1:0]} + dac_sample_phase[i];
        end
      end
    end

    always_ff @(posedge dac_clk) begin
      dac_phase_dithered_d <= dac_phase_dithered;
      for (int i = 0; i < tx_pkg::PARALLEL_SAMPLES; i++) begin
        // quantize the phase, then perform the lookup
        dac_phase_quantized[i] <= dac_phase_dithered_d[i][PHASE_BITS-1:QUANT_BITS];
        dac_data_out.data[channel][tx_pkg::SAMPLE_WIDTH*i+:tx_pkg::SAMPLE_WIDTH] <= lut[dac_phase_quantized[i]];
      end
    end
  end
endgenerate

endmodule
