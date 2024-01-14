// sample discriminator - Reed Foster
// If input sample is above some threshold (w/ hysteresis), it is passed through,
// otherwise it is dropped. If the preceeding sample was below the low threshold,
// then a timestamp is also sent out
// In addition to the timestamp, the number of saved samples up to the event that
// triggered timestamp creation is reported.
// This allows the timestamp to be associated with a specific sample that was saved.
// The sample count (not the timestamp) and hysteresis tracker are reset every time a new capture is started.
module sample_discriminator #( 
  parameter int SAMPLE_WIDTH = 16,
  parameter int PARALLEL_SAMPLES = 16,
  parameter int CHANNELS = 8,
  parameter int SAMPLE_INDEX_WIDTH = 14, // ideally keep the sum of this and CLOCK_WIDTH at most 64
  parameter int CLOCK_WIDTH = 50 // rolls over roughly every 3 days at 4GS/s (100 days at 32MS/s)
) (
  input wire clk, reset,
  Realtime_Parallel_If.Slave data_in,
  Realtime_Parallel_If.Master data_out,
  Realtime_Parallel_If.Master timestamps_out,
  Axis_If.Slave config_in, // {threshold_high, threshold_low} for each channel
  input wire reset_state
);

assign config_in.ready = 1'b1; // always accept a new threshold

localparam int TIMESTAMP_WIDTH = SAMPLE_INDEX_WIDTH + CLOCK_WIDTH;

typedef logic signed [SAMPLE_WIDTH-1:0] signed_sample_t;

// high/low threshold for hysteresis
logic [CHANNELS-1:0][SAMPLE_WIDTH-1:0] threshold_low, threshold_high;
// delay data input to match latency of hysteresis-tracking circuit
logic [CHANNELS-1:0][PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] data_in_reg;
logic [CHANNELS-1:0] data_in_valid;
// timer and latency-matching pipeline stage
logic [CHANNELS-1:0][CLOCK_WIDTH-1:0] timer, timer_d;
// sample index to associate timestamp with a saved sample
logic [CHANNELS-1:0][SAMPLE_INDEX_WIDTH-1:0] sample_index;

// hysteresis-tracking logic
logic [CHANNELS-1:0] is_high, is_high_d;
logic [CHANNELS-1:0] new_is_high;

assign new_is_high = is_high & (~is_high_d);

// update thresholds from config interface
always_ff @(posedge clk) begin
  if (reset) begin
    threshold_low <= '0;
    threshold_high <= '0;
  end else begin
    if (config_in.ok) begin
      for (int i = 0; i < CHANNELS; i++) begin
        threshold_high[i] <= config_in.data[2*SAMPLE_WIDTH*i+SAMPLE_WIDTH+:SAMPLE_WIDTH];
        threshold_low[i] <= config_in.data[2*SAMPLE_WIDTH*i+:SAMPLE_WIDTH];
      end
    end
  end
end

// since there are multiple parallel samples, check to see if any of
// them exceed the high threshold or if all of them are below the low
// threshold
logic [CHANNELS-1:0] any_above_high, all_below_low;
always_comb begin
  for (int i = 0; i < CHANNELS; i++) begin
    any_above_high[i] = 1'b0;
    all_below_low[i] = 1'b1;
    for (int j = 0; j < PARALLEL_SAMPLES; j++) begin
      if (signed_sample_t'(data_in.data[i][j*SAMPLE_WIDTH+:SAMPLE_WIDTH]) > signed_sample_t'(threshold_high[i])) begin
        any_above_high[i] = 1'b1;
      end
      if (signed_sample_t'(data_in.data[i][j*SAMPLE_WIDTH+:SAMPLE_WIDTH]) > signed_sample_t'(threshold_low[i])) begin
        all_below_low[i] = 1'b0;
      end
    end
  end
end

always_ff @(posedge clk) begin
  // pipeline stage for timer to match sample_index delay
  timer_d <= timer;
  timestamps_out.valid <= new_is_high;
  for (int i = 0; i < CHANNELS; i++) begin
    timestamps_out.data[i] <= {timer_d[i], sample_index[i]};
  end

  // pipeline stage to match latency of is_high SR flipflop
  data_in_valid <= data_in.valid;
  data_in_reg <= data_in.data;

  // match delay of sample_index
  data_out.data <= data_in_reg;
  data_out.valid <= data_in_valid & is_high;

  // is_high SR flipflop, sample_index, and timer
  if (reset) begin
    is_high <= '0;
    is_high_d <= '0;
    timer <= '0;
    sample_index <= '0;
  end else begin
    // update sample_index, timer and is_high for each channel
    for (int i = 0; i < CHANNELS; i++) begin
      if (reset_state) begin
        // don't reset timer, since we want
        // to be able to track the arrival time of
        // samples between multiple captures
        //
        // reset is_high_d so that we can correctly capture a
        // new sample if it arrives immediately after reset_state
        // is deasserted
        is_high_d[i] <= 1'b0;
        // reset sample_index
        sample_index[i] <= '0;
        if (data_in.valid[i] && any_above_high[i]) begin
          // keep is_high if input data is valid and above threshold
          // that way we don't miss the first sample
          is_high[i] <= 1'b1;
        end else begin
          // only reset is_high if the current data is not high
          is_high[i] <= 1'b0;
        end
      end else begin
        // update is_high_d every cycle
        is_high_d[i] <= is_high[i];
        if (data_in_valid[i] && is_high[i]) begin
          // only update sample index when we send out a valid sample that has
          // met the criteria of the discriminator
          sample_index[i] <= sample_index[i] + 1'b1;
        end
        // update is_high only when we get a new, valid sample
        if (data_in.valid[i]) begin
          if (any_above_high[i]) begin
            is_high[i] <= 1'b1;
          end else if (all_below_low[i]) begin
            is_high[i] <= 1'b0;
          end
        end
      end
      // update timer (input sample counter)
      if (data_in.valid[i]) begin
        timer[i] <= timer[i] + 1'b1;
      end
    end
  end
end

endmodule
