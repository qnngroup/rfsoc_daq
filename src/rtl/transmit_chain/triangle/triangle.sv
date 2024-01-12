// triangle.sv - Reed Foster
// Triangle wave generator, useful for IV measurements

module triangle #(
  parameter int PHASE_BITS = 32, // ~ 2 Hz resolution at 6 GS/s
  parameter int CHANNELS = 8,
  parameter int PARALLEL_SAMPLES = 16,
  parameter int SAMPLE_WIDTH = 16
) (
  input wire ps_clk, ps_reset,
  Axis_If.Slave_Stream ps_phase_inc, // {phase_inc} for each channel

  input wire dac_clk, dac_reset,
  Axis_Parallel_If.Master_Realtime dac_data_out,

  output logic [CHANNELS-1:0] dac_trigger // send a trigger at zero crossing going up
);

Axis_If #(.DWIDTH(CHANNELS*PHASE_BITS)) dac_phase_inc ();

axis_config_reg_cdc #(
  .DWIDTH(CHANNELS*PHASE_BITS)
) ps_to_dac_triangle_phase_inc_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_phase_inc),
  .dest_clk(dac_clk),
  .dest_reset(dac_reset),
  .dest(dac_phase_inc)
);

assign dac_phase_inc.ready = 1'b1; // always accept new phase inc

logic [CHANNELS-1:0][PARALLEL_SAMPLES-1:0][PHASE_BITS-1:0] dac_phase_inc_reg;
logic [CHANNELS-1:0][PARALLEL_SAMPLES-1:0][PHASE_BITS-1:0] dac_sample_phase, dac_sample_phase_d;
logic [CHANNELS-1:0][PHASE_BITS-1:0] dac_cycle_phase;

localparam int LATENCY = 4;
logic [CHANNELS-1:0][LATENCY-1:0] data_valid;
always_comb begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    dac_data_out.valid[channel] = data_valid[channel][LATENCY-1];
  end
end

always_ff @(posedge dac_clk) begin
  if (dac_reset) begin
    dac_phase_inc_reg <= '0;
    dac_cycle_phase <= '0;
    dac_sample_phase <= '0;
    dac_sample_phase_d <= '0;
    data_valid <= '0;
  end else begin
    // load new phase_inc
    if (dac_phase_inc.valid) begin
      for (int channel = 0; channel < CHANNELS; channel++) begin
        for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
          // phase_inc[0] = 1*phase_inc.data
          // phase_inc[1] = 2*phase_inc.data
          // ...
          // the final entry in phase_inc is used to update the cycle_phase
          dac_phase_inc_reg[channel][sample] <= dac_phase_inc.data[channel*PHASE_BITS+:PHASE_BITS] * (sample + 1);
        end
      end
    end
    for (int channel = 0; channel < CHANNELS; channel++) begin
      // increment the phases in parallel
      dac_cycle_phase[channel] <= dac_cycle_phase[channel] + dac_phase_inc_reg[channel][PARALLEL_SAMPLES-1];
      // first sample_phase is just the cycle_phase
      // the following sample_phase[sample>0] are derived from
      // the cycle_phase plus some phase increment
      dac_sample_phase[channel][0] <= dac_cycle_phase[channel];
      for (int sample = 1; sample < PARALLEL_SAMPLES; sample++) begin
        dac_sample_phase[channel][sample] <= dac_cycle_phase[channel] + dac_phase_inc_reg[channel][sample-1];
      end
      // match startup latency of addition pipeline
      data_valid[channel] <= {data_valid[channel][LATENCY-2:0], 1'b1};
    end
    dac_sample_phase_d <= dac_sample_phase;
  end
end

// convert the phases into outputs
logic [CHANNELS-1:0][PARALLEL_SAMPLES-1:0][PHASE_BITS-1:0] dac_out_full; // full-precision output
logic [CHANNELS-1:0][2*PARALLEL_SAMPLES-1:0] dac_phase_MSB0;
logic [CHANNELS-1:0][2*PARALLEL_SAMPLES-1:0] dac_phase_MSB1;
always_comb begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
      dac_phase_MSB1[channel][sample] = dac_sample_phase[channel][sample][PHASE_BITS-2];
      dac_phase_MSB1[channel][PARALLEL_SAMPLES+sample] = dac_sample_phase_d[channel][sample][PHASE_BITS-2];
      dac_phase_MSB0[channel][sample] = dac_sample_phase[channel][sample][PHASE_BITS-1];
      dac_phase_MSB0[channel][PARALLEL_SAMPLES+sample] = dac_sample_phase_d[channel][sample][PHASE_BITS-1];
      // not super accurate for large phase increment, but good enough if the
      // phase varies slowly (i.e. as long as you're not not trying to generate
      // triangle waves with a fundamental of 3GHz, you're fine)
    end
  end
end
// if some, but not all signals are in the second quadrant (01) and all signals are either
// in the first or second quadrant (0X), then
always_ff @(posedge dac_clk) begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    // make sure all of the following are met to send a trigger:
    // - we're on a rising edge (dac_phase_MSB0 is zero for all samples)
    // - some of the samples are in the upper half (dac_phase_MSB1 has nonzero bits)
    // - not all of the samples are in the upper half (dac_phase_MSB1 has zero bits)
    dac_trigger[channel] <= (&(~dac_phase_MSB0[channel])) & (|dac_phase_MSB1[channel]) & (~(&dac_phase_MSB1[channel]));
  end
end

always_ff @(posedge dac_clk) begin
  if (dac_reset) begin
    dac_out_full <= '0;
    dac_data_out.data <= '0;
  end else begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
        if (~dac_phase_MSB0[channel][sample]) begin
          dac_out_full[channel][sample] <= {1'b1, {(PHASE_BITS-1){1'b0}}} + {dac_sample_phase[channel][sample][PHASE_BITS-2:0], 1'b0};
        end else begin
          dac_out_full[channel][sample] <= {1'b0, {(PHASE_BITS-1){1'b1}}} - {dac_sample_phase[channel][sample][PHASE_BITS-2:0], 1'b0};
        end
        dac_data_out.data[channel][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= dac_out_full[channel][sample][PHASE_BITS-1-:SAMPLE_WIDTH];
      end
    end
  end
end

endmodule
