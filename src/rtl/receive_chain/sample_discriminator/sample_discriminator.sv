// sample discriminator - Reed Foster
// Starts saving samples when events of interest occur
// Event can be specified by a digital trigger or analog trigger
// Various event sources can be multiplexed to each capture channel
// E.g. a digital trigger may be used across multiple capture channels,
// or each capture channel could use its own analog trigger
//
// Currently, the only supported trigger behavior is threshold-based
//
// Once activated, a capture channel will save samples until either
// a low trigger is tripped, or a stop delay timeout occurs
//
// An optional start delay can be used to create a delay between a trigger
// event and when the capture channel goes active

`timescale 1ns/1ps
module sample_discriminator #(
  parameter int MAX_DELAY_CYCLES = 64 // capture up to 128 ns before event @ 512 MHz
) (
  input logic adc_clk, adc_reset,
  Realtime_Parallel_If.Slave adc_data_in,
  Realtime_Parallel_If.Master adc_data_out,
  Realtime_Parallel_If.Master adc_timestamps_out,
  input logic adc_reset_state,

  input logic [tx_pkg::CHANNELS-1:0] adc_digital_trigger_in,

  input logic ps_clk, ps_reset,
  // {threshold_high, threshold_low} for each channel
  Axis_If.Slave ps_thresholds,
  // {digital delay, stop delay, start delay} for each channel ($clog2(MAX_DELAY_CYCLES)-bit quantities)
  Axis_If.Slave ps_delays,
  // {trigger_source} for each channel, $clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS)-bit quantity (0 is first analog channel, rx_pkg::CHANNELS is first digital channel, etc.)
  Axis_If.Slave ps_trigger_select,
  // 1b for each channel, bypasses discriminator if high
  Axis_If.Slave ps_disable_discriminator
);

//////////////////////////////////
// CDC configuration registers
//////////////////////////////////

// thresholds for analog trigger comparator
logic [rx_pkg::CHANNELS-1:0][rx_pkg::SAMPLE_WIDTH-1:0] adc_thresholds_low;
logic [rx_pkg::CHANNELS-1:0][rx_pkg::SAMPLE_WIDTH-1:0] adc_thresholds_high;
Axis_If #(.DWIDTH(2*rx_pkg::SAMPLE_WIDTH*rx_pkg::CHANNELS)) adc_thresholds_sync ();
assign adc_thresholds_sync.ready = 1'b1; // always accept new config
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_thresholds_low <= '0;
    adc_thresholds_high <= '0;
  end else begin
    if (adc_thresholds_sync.ok) begin
      for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
        adc_thresholds_low[channel] <= adc_thresholds_sync.data[(2*channel)*rx_pkg::SAMPLE_WIDTH+:rx_pkg::SAMPLE_WIDTH];
        adc_thresholds_high[channel] <= adc_thresholds_sync.data[(2*channel+1)*rx_pkg::SAMPLE_WIDTH+:rx_pkg::SAMPLE_WIDTH];
      end
    end
  end
end
axis_config_reg_cdc #(
  .DWIDTH(2*rx_pkg::SAMPLE_WIDTH*rx_pkg::CHANNELS)
) threshold_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_thresholds),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_thresholds_sync)
);

// start/stop delay
localparam int DISC_LATENCY = 2; // extra latency for pipeline because of sample discriminator
localparam int TIMER_BITS = $clog2(MAX_DELAY_CYCLES);
logic [rx_pkg::CHANNELS-1:0][$clog2(MAX_DELAY_CYCLES+DISC_LATENCY)-1:0] adc_pipe_delay;
logic [rx_pkg::CHANNELS-1:0][$clog2(2*MAX_DELAY_CYCLES)-1:0] adc_total_delay;
logic [rx_pkg::CHANNELS-1:0][$clog2(MAX_DELAY_CYCLES+1)-1:0] adc_digital_delay;
Axis_If #(.DWIDTH(3*TIMER_BITS*rx_pkg::CHANNELS)) adc_delays_sync ();
assign adc_delays_sync.ready = 1'b1; // always accept new config
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_pipe_delay <= '0;
    adc_total_delay <= '0;
    adc_digital_delay <= '0;
  end else begin
    if (adc_delays_sync.ok) begin
      for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
        // just start delay for data/valid pipeline delay
        adc_pipe_delay[channel] <= adc_delays_sync.data[(3*channel)*TIMER_BITS+:TIMER_BITS] + DISC_LATENCY;
        // start + stop delay for total
        adc_total_delay[channel] <= adc_delays_sync.data[(3*channel+1)*TIMER_BITS+:TIMER_BITS]
                                    + adc_delays_sync.data[(3*channel)*TIMER_BITS+:TIMER_BITS];
        adc_digital_delay[channel] <= adc_delays_sync.data[(3*channel+2)*TIMER_BITS+:TIMER_BITS];
      end
    end
  end
end
axis_config_reg_cdc #(
  .DWIDTH(3*TIMER_BITS*rx_pkg::CHANNELS)
) delays_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_delays),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_delays_sync)
);

// triggering source/mode
localparam int TRIGGER_SELECT_WIDTH = $clog2(rx_pkg::CHANNELS + tx_pkg::CHANNELS);
logic [rx_pkg::CHANNELS-1:0][TRIGGER_SELECT_WIDTH-1:0] adc_trigger_source;
logic [rx_pkg::CHANNELS-1:0] adc_trigger_is_digital;
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*TRIGGER_SELECT_WIDTH)) adc_trigger_select_sync ();
assign adc_trigger_select_sync.ready = 1'b1; // always accept new config
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
      // assign each trigger to its respective analog trigger channel
      adc_trigger_source[channel] <= TRIGGER_SELECT_WIDTH'(channel);
    end
    adc_trigger_is_digital <= '0;
  end else begin
    if (adc_trigger_select_sync.ok) begin
      adc_trigger_source <= adc_trigger_select_sync.data;
      for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
        adc_trigger_is_digital[channel] <= adc_trigger_select_sync.data[channel*TRIGGER_SELECT_WIDTH+:TRIGGER_SELECT_WIDTH] >= rx_pkg::CHANNELS;
      end
    end
  end
end
axis_config_reg_cdc #(
  .DWIDTH(rx_pkg::CHANNELS*TRIGGER_SELECT_WIDTH)
) trigger_select_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_trigger_select),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_trigger_select_sync)
);

logic [rx_pkg::CHANNELS-1:0] adc_active_mask;
Axis_If #(.DWIDTH(rx_pkg::CHANNELS)) adc_disable_discriminator_sync ();
assign adc_disable_discriminator_sync.ready = 1'b1; // always accept new config
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_active_mask <= '0;
  end else begin
    if (adc_disable_discriminator_sync.ok) begin
      adc_active_mask <= adc_disable_discriminator_sync.data;
    end
  end
end
axis_config_reg_cdc #(
  .DWIDTH(rx_pkg::CHANNELS)
) disable_discriminator_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_disable_discriminator),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_disable_discriminator_sync)
);

// main logic

// track state of each channel
// DISABLED: don't save samples
// PRECAPTURE: save samples, ignore
enum {DISABLED, PRECAPTURE, CAPTURE, POSTCAPTURE} adc_states [rx_pkg::CHANNELS];
logic [rx_pkg::CHANNELS-1:0] adc_active, adc_active_d;
always_comb begin
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    // if the discriminator is bypassed for the current channel, always output 1,
    // otherwise, only output a 1 when in the PRECAPTURE or CAPTURE state
    adc_active[channel] = (adc_states[channel] != DISABLED) | adc_active_mask[channel];
  end
end

always_ff @(posedge adc_clk) adc_active_d <= adc_active;

logic [MAX_DELAY_CYCLES+DISC_LATENCY-1:0][rx_pkg::CHANNELS-1:0][rx_pkg::DATA_WIDTH-1:0] adc_data_pipe;
logic [MAX_DELAY_CYCLES+DISC_LATENCY-1:0][rx_pkg::CHANNELS-1:0] adc_valid_pipe;
logic [rx_pkg::CHANNELS-1:0] adc_data_any_above_high, adc_data_all_below_low;
always_ff @(posedge adc_clk) begin
  adc_data_pipe <= {adc_data_pipe[MAX_DELAY_CYCLES+DISC_LATENCY-2:0], adc_data_in.data};
  adc_valid_pipe <= {adc_valid_pipe[MAX_DELAY_CYCLES+DISC_LATENCY-2:0], adc_data_in.valid};

  // amplitude-based triggering
  adc_data_any_above_high <= '0;
  adc_data_all_below_low <= adc_data_in.valid & (~adc_reset_state);
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    for (int sample = 0; sample < rx_pkg::PARALLEL_SAMPLES; sample++) begin
      if (rx_pkg::sample_t'(adc_data_in.data[channel][sample*rx_pkg::SAMPLE_WIDTH+:rx_pkg::SAMPLE_WIDTH])
          > rx_pkg::sample_t'(adc_thresholds_high[channel])) begin
        adc_data_any_above_high[channel] <= adc_data_in.valid[channel] & (~adc_reset_state);
      end
      if (rx_pkg::sample_t'(adc_data_in.data[channel][sample*rx_pkg::SAMPLE_WIDTH+:rx_pkg::SAMPLE_WIDTH])
          > rx_pkg::sample_t'(adc_thresholds_low[channel])) begin
        adc_data_all_below_low[channel] <= 1'b0;
      end
    end
  end
end

// select data and valid output from delay pipelines based on start_delay
always_ff @(posedge adc_clk) begin
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    adc_data_out.data[channel] <= adc_data_pipe[adc_pipe_delay[channel]][channel];
    adc_data_out.valid[channel] <= adc_valid_pipe[adc_pipe_delay[channel]][channel] & adc_active[channel];
  end
end

// combine analog triggers and digital triggers
// also apply delay to digital triggers
logic [rx_pkg::CHANNELS+tx_pkg::CHANNELS-1:0] adc_stop_triggers;
logic [rx_pkg::CHANNELS-1:0] adc_digital_trigger_in_d;
logic [MAX_DELAY_CYCLES+1-1:0][tx_pkg::CHANNELS-1:0] adc_digital_trigger_in_pipe;
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_digital_trigger_in_pipe <= '0;
  end else begin
    if (adc_reset_state) begin
      adc_digital_trigger_in_pipe <= '0;
    end else begin
      adc_digital_trigger_in_pipe <= {adc_digital_trigger_in_pipe[MAX_DELAY_CYCLES-2:0], adc_digital_trigger_in};
    end
  end
end

always_ff @(posedge adc_clk) begin
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    if (adc_trigger_is_digital[channel]) begin
      if (adc_digital_delay[channel] == 0) begin
        adc_digital_trigger_in_d[channel] <= adc_digital_trigger_in[adc_trigger_source[channel] - rx_pkg::CHANNELS];
      end else begin
        adc_digital_trigger_in_d[channel] <= adc_digital_trigger_in_pipe[adc_digital_delay[channel] - 1][adc_trigger_source[channel] - rx_pkg::CHANNELS];
      end
    end else begin
      adc_digital_trigger_in_d[channel] <= 1'b0;
    end
  end
end

assign adc_stop_triggers = {{tx_pkg::CHANNELS{1'b0}}, adc_data_all_below_low};
logic [rx_pkg::CHANNELS-1:0] adc_fsm_start, adc_fsm_start_d, adc_fsm_stop, adc_fsm_stop_d;
logic [2*MAX_DELAY_CYCLES-1:0][rx_pkg::CHANNELS-1:0] adc_fsm_stop_pipe;
always_ff @(posedge adc_clk) begin
  if (adc_reset_state) begin
    adc_fsm_start <= '0;
    adc_fsm_stop <= '0;
  end else begin
    // mux triggers
    for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
      if (adc_trigger_is_digital[channel]) begin
        adc_fsm_start[channel] <= adc_digital_trigger_in_d[channel];
      end else begin
        adc_fsm_start[channel] <= adc_data_any_above_high[adc_trigger_source[channel]];
      end
      adc_fsm_stop[channel] <= adc_stop_triggers[adc_trigger_source[channel]];
    end
  end
end

// delay stop with a shiftreg/pipeline delay so we don't miss any stop signals
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_fsm_stop_pipe <= '0;
  end else begin
    if (adc_reset_state) begin
      adc_fsm_stop_pipe <= '0;
    end else begin
      adc_fsm_stop_pipe <= {adc_fsm_stop_pipe, adc_fsm_stop};
    end
  end
end

// delay start signal with a pulse_delay counter which is reset to COUNT_MAX
// every time an input pulse arrives so we don't miss any_above_high
generate
  for (genvar channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    // invalid for total_delay == 0, but start_d doesn't get used if total_delay == 0
    pulse_delay #(
      .TIMER_BITS($clog2(2*MAX_DELAY_CYCLES))
    ) adc_start_pulse_delay_i (
      .clk(adc_clk),
      .reset(adc_reset | adc_reset_state),
      .delay(adc_total_delay[channel] - 1),
      .in_pls(adc_fsm_start[channel]),
      .out_pls(adc_fsm_start_d[channel])
    );
  end
endgenerate

always_comb begin
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    // invalid for total_delay == 0, but stop_d doesn't get used if total_delay == 0
    adc_fsm_stop_d[channel] = adc_fsm_stop_pipe[adc_total_delay[channel]-1][channel];
  end
end

// timestamps
logic [rx_pkg::CHANNELS-1:0][buffer_pkg::SAMPLE_INDEX_WIDTH-1:0] adc_sample_index;
logic [buffer_pkg::CLOCK_WIDTH-1:0] adc_time;
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_time <= '0;
    adc_sample_index <= '0;
  end else begin
    adc_time <= adc_time + 1'b1;
    if (adc_reset_state) begin
      adc_sample_index <= '0;
    end else begin
      for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
        if (adc_data_out.valid[channel]) begin
          adc_sample_index[channel] <= adc_sample_index[channel] + 1;
        end
      end
    end
  end
end

// output timestamps
logic [rx_pkg::CHANNELS-1:0] adc_timestamp_valid;
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_timestamp_valid <= '0;
  end else begin
    // only valid when we first get a start signal
    for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
      if (adc_active[channel] & (~adc_active_d[channel])) begin
        adc_timestamp_valid[channel] <= 1'b1;
      end else begin
        adc_timestamp_valid[channel] <= 1'b0;
      end
    end
  end
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    adc_timestamps_out.data[channel] <= {adc_time, adc_sample_index[channel]};
    adc_timestamps_out.valid[channel] <= adc_timestamp_valid[channel];
  end
end

// state machine transitions
always_ff @(posedge adc_clk) begin
  if (adc_reset | adc_reset_state) begin
    for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
      adc_states[channel] <= DISABLED;
    end
  end else begin
    for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
      // problem if adc_total_delay == 0 and trigger is digital
      unique case (adc_states[channel])
        DISABLED: if (adc_fsm_start[channel]) adc_states[channel] <=
                    (|adc_total_delay[channel]) ? PRECAPTURE : CAPTURE;
        PRECAPTURE: begin
          if (adc_fsm_start_d[channel]) begin
            adc_states[channel] <= adc_trigger_is_digital[channel] ? POSTCAPTURE : CAPTURE;
          end
        end
        CAPTURE: begin
          if (adc_fsm_start[channel]) begin
            adc_states[channel] <= (|adc_total_delay[channel]) ? PRECAPTURE : CAPTURE;
          end else begin
            if (|adc_total_delay[channel]) begin
              if (adc_fsm_stop_d[channel]) adc_states[channel] <= DISABLED;
            end else begin
              if (adc_trigger_is_digital[channel]) begin
                // wait until data is valid
                if (adc_valid_pipe[2][channel]) adc_states[channel] <= DISABLED;
              end
              if (adc_fsm_stop[channel]) adc_states[channel] <= DISABLED;
            end
          end
        end
        POSTCAPTURE: begin
          adc_states[channel] <= DISABLED;
        end
      endcase
    end
  end
end


endmodule
