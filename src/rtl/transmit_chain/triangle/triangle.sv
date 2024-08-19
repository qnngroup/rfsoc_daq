// triangle.sv - Reed Foster
// Triangle wave generator, useful for IV measurements

`timescale 1ns/1ps
module triangle #(
  parameter int PHASE_BITS, // 32 -> ~2 Hz resolution at 6 GS/s
  parameter int CHANNELS,
  parameter int PARALLEL_SAMPLES,
  parameter int SAMPLE_WIDTH
) (
  input logic ps_clk, ps_reset,
  Axis_If.Slave ps_phase_inc, // {phase_inc} for each channel

  input logic dac_clk, dac_reset,
  Realtime_Parallel_If.Master dac_data_out,

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

localparam int LATENCY = 2;
logic [LATENCY-1:0] dac_data_valid;
assign dac_data_out.valid = {CHANNELS{dac_data_valid[LATENCY-1]}};

always_ff @(posedge dac_clk) begin
  if (dac_reset) begin
    dac_phase_inc_reg <= '0;
    dac_cycle_phase <= '0;
    dac_sample_phase <= '0;
    dac_sample_phase_d <= '0;
    dac_data_valid <= '0;
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
    end
    dac_data_valid <= {dac_data_valid[LATENCY-2:0], 1'b1};
    dac_sample_phase_d <= dac_sample_phase;
  end
end

// generate triggers
logic [CHANNELS-1:0][PARALLEL_SAMPLES-1:0] dac_phase_MSB0;
logic [CHANNELS-1:0][PARALLEL_SAMPLES-1:0] dac_phase_MSB1, dac_phase_MSB1_d;
always_comb begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
      dac_phase_MSB1[channel][sample] = dac_sample_phase[channel][sample][PHASE_BITS-2];
      dac_phase_MSB0[channel][sample] = dac_sample_phase[channel][sample][PHASE_BITS-1];
      // not super accurate for large phase increment, but good enough if the
      // phase varies slowly (i.e. as long as you're not not trying to generate
      // triangle waves with a fundamental of 3GHz, you're fine)
    end
  end
end
// if some, but not all signals are in the second quadrant (MSBs = 01) and all signals are either
// in the first or second quadrant (MSBs = 0X), then
logic [CHANNELS-1:0] dac_rising_edge;
logic [CHANNELS-1:0] dac_crossing_in_batch;
logic [CHANNELS-1:0] dac_crossing_between_batch;
always_ff @(posedge dac_clk) begin
  dac_phase_MSB1_d <= dac_phase_MSB1;
  for (int channel = 0; channel < CHANNELS; channel++) begin
    // make sure all of the following are met to send a trigger:
    // - we're on a rising edge
    //    (dac_phase_MSB0 is zero for all samples)
    dac_rising_edge[channel] <= &(~dac_phase_MSB0[channel]);
    // - crossing either in this batch or the previous batch
    //    (dac_phase_MSB1 is not all 1's or dac_phase_MSB1 is all 1's and dac_phase_MSB1_d is all 0's)
    dac_crossing_in_batch[channel] <= (~(&dac_phase_MSB1[channel])) & (|dac_phase_MSB1[channel]);
    dac_crossing_between_batch[channel] <= (&dac_phase_MSB1[channel]) & (&(~dac_phase_MSB1_d[channel]));
  end
  dac_trigger <= dac_rising_edge & (dac_crossing_in_batch | dac_crossing_between_batch);
end

// convert the phases into outputs
logic [CHANNELS-1:0][PARALLEL_SAMPLES-1:0][PHASE_BITS-1:0] dac_out_full; // full-precision output
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
