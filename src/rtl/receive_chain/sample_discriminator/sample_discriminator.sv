// sample discriminator - Reed Foster
// Saves samples when events of interest occur
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
module sample_discriminator #
  parameter int NEGATIVE_DELAY_CYCLES = 512, // capture up to 1 microsecond before event @ 512 MHz
  parameter int TIMER_BITS = 32
) (
  input logic adc_clk, adc_reset,
  Realtime_Parallel_If.Slave adc_data_in,
  Realtime_Parallel_If.Master adc_data_out,
  Realtime_Parallel_If.Master adc_timestamps_out,
  input logic adc_reset_state,

  input logic [tx_pkg::CHANNELS-1:0] adc_digital_trigger_in,

  input logic ps_clk, ps_reset,
  Axis_If.Slave ps_thresholds, // {threshold_high, threshold_low} for each channel
  Axis_If.Slave ps_timer_cfg, // {start delay, stop delay} for each channel (32-bit quantities)
  Axis_If.Slave ps_trigger_select // {trigger_source} for each channel, $clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS)-bit quantity (0 is first analog channel, rx_pkg::CHANNELS is first digital channel, etc.)
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
logic [rx_pkg::CHANNELS-1:0][TIMER_BITS-1:0] adc_start_delay;
logic [rx_pkg::CHANNELS-1:0][TIMER_BITS-1:0] adc_stop_delay;
Axis_If #(.DWIDTH(TIMER_BITS*rx_pkg::CHANNELS)) adc_timer_cfg_sync ();
assign adc_timer_cfg_sync.ready = 1'b1; // always accept new config
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_start_delay <= '0;
    adc_stop_delay <= '0;
  end else begin
    if (adc_timer_cfg_sync.ok) begin
      for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
        adc_start_delay[channel] <= adc_timer_cfg_sync.data[(2*channel)*TIMER_BITS+:TIMER_BITS];
        adc_stop_delay[channel] <= adc_timer_cfg_sync.data[(2*channel+1)*TIMER_BITS+:TIMER_BITS];
      end
    end
  end
end
axis_config_reg_cdc #(
  .DWIDTH(2*TIMER_BITS*rx_pkg::CHANNELS)
) timer_cfg_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_timer_cfg),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_timer_cfg_sync)
);

// triggering source/mode
localparam int TRIGGER_SELECT_WIDTH = $clog2(rx_pkg::CHANNELS + tx_pkg::CHANNELS);
logic [rx_pkg::CHANNELS-1:0][TRIGGER_SELECT_WIDTH-1:0] adc_trigger_source;
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*(TRIGGER_SELECT_WIDTH))) adc_trigger_select_sync ();
assign adc_trigger_select_sync.ready = 1'b1; // always accept new config
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
      // assign each trigger to its respective analog trigger channel
      adc_trigger_source[channel] <= TRIGGER_SELECT_WIDTH'(channel);
    end
  end else begin
    if (adc_trigger_select_sync.ok) begin
      adc_trigger_source <= adc_trigger_select_sync.data;
    end
  end
end
axis_config_reg_cdc #(
  .DWIDTH(TRIGGER_SELECT_WIDTH)
) trigger_select_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_trigger_select),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_trigger_select_sync)
);

logic [NEGATIVE_DELAY_CYCLES-1:0][rx_pkg::CHANNELS-1:0][rx_pkg::DATA_WIDTH-1:0] adc_data_pipe;
logic [rx_pkg::CHANNELS-1:0] adc_data_any_above_high, adc_data_all_below_low, adc_data_all_below_low_d;
logic [rx_pkg::CHANNELS-1:0] adc_acquire;

logic [rx_pkg::CHANNELS+tx_pkg::CHANNELS-1:0] adc_triggers;
assign adc_triggers = {adc_digital_trigger_in, adc_any_above_high};

logic [rx_pkg::CHANNELS-1:0] adc_trigger_muxed; // mux
logic [rx_pkg::CHANNELS-1:0][TIMER_BITS-1:0] adc_start_timer, adc_low_timer, adc_stop_timer;
logic [rx_pkg::CHANNELS-1:0] adc_start_timer_done, adc_low_timer_done, adc_stop_timer_done;

always_ff @(posedge adc_clk) begin
  if (adc_data_in.valid) begin
    // pipeline to achieve negative trigger->acquire delay
    adc_data_pipe <= {adc_data_pipe[NEGATIVE_DELAY_CYCLES-2:0], adc_data_in.data};

    // process amplitude triggering
    adc_data_any_above_high <= '0;
    adc_data_all_below_low <= '1;
    for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
      for (int sample = 0; sample < rx_pkg::PARALLEL_SAMPLES; sample++) begin
        if ($signed(adc_data_in.data[channel][sample*rx_pkg::SAMPLE_WIDTH+:rx_pkg::SAMPLE_WIDTH])
            > $signed(adc_thresholds_high[channel])) begin
          adc_data_any_above_high[channel] <= 1'b1;
        end
        if ($signed(adc_data_in.data[channel][sample*rx_pkg::SAMPLE_WIDTH+:rx_pkg::SAMPLE_WIDTH])
            > $signed(adc_thresholds_low[channel])) begin
          adc_data_all_below_low[channel] <= 1'b0;
        end
      end
    end
    adc_data_all_below_low_d <= adc_data_all_below_low;

    // mux triggers
    for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
      adc_trigger_muxed[channel] <= adc_triggers[adc_trigger_source[channel]];
    end

    // run counters
    for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin

      // timer-based acquisition stop has the same start signal as the delay
      if (adc_trigger_muxed[channel]) begin
        adc_start_timer[channel] <= adc_start_delay[channel];
        adc_stop_timer[channel] <= adc_stop_delay[channel];
        adc_start_timer_done[channel] <= 1'b0;
        adc_stop_timer_done[channel] <= 1'b0;
      end else begin
        if (adc_start_timer[channel] == 0) begin
          adc_start_timer_done <= 1'b1;
        end else begin
          adc_start_timer[channel] <= adc_start_timer[channel] - 1'b1;
        end
        if (adc_stop_timer[channel] == 0) begin
          adc_stop_timer_done <= 1'b1;
        end else begin
          adc_stop_timer[channel] <= adc_stop_timer[channel] - 1'b1;
        end
      end

      // same delay for the all_below_low signal as the start signal
      if (adc_data_all_below_low_d) begin
        adc_low_timer[channel] <= adc_start_delay[channel];
        adc_low_timer_done[channel] <= 1'b0;
      end else begin
        if (adc_low_timer[channel] == 0) begin
          adc_low_timer_done <= 1'b1;
        end else begin
          adc_low_timer[channel] <= adc_low_timer[channel] - 1'b1;
        end
      end
    end

  end
end

endmodule
