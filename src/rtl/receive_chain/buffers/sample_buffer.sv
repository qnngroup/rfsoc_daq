// sample_buffer.sv - Reed Foster
// Buffer for storing samples from multiple independent ADC channels.
// The buffer is organized by banks, which can be grouped arbitrarly
// based on the banking mode.
// This allows for flexible use of multiple channels: if fewer than the
// maximum number of channels are required for use, then the banks typically
// dedicated to the now-unused channels can be used to expand the buffer
// capacity of the active channels.
//
// For independent banking mode, each input channel has its own separate bank
// For single-channel mode, only the first input channel can write to the
// sample buffer (but it has more storage as a result)
// For dual-channel mode, the first two input channels can write to the sample
// buffer
// For quad-channel mode, ...
//
// A channel multiplexer switch can be used to change which channels are
// active so that any physical channel can be routed to the first input
// channel of this module (allowing high-capacity buffering in single-channel
// mode for any physical input channel)
//
// TODO implement with dual clocks: fast clock for writing, slow clock for
// reading
// - writing should be able to achieve 512MHz due to independent nature of the
//    banked memory (so even major congestion has little impact on timing)
// - output mux presents a challenge for 512MHz due to congestion
//    (every bank output has to go to the same area for multiplexing, leading
//    to large routing delays: ~2ns to go 1/4 of the way across the chip,
//    which blows the slack budget in one go)

`timescale 1ns/1ps
module sample_buffer #(
  parameter int CHANNELS = 8, // number of ADC channels
  parameter int BUFFER_DEPTH = 8192, // maximum capacity across all channels
  parameter int PARALLEL_SAMPLES = 16, // 4.096 GS/s @ 256 MHz
  parameter int SAMPLE_WIDTH = 16 // 12-bit ADC
) (
  input wire clk, reset,
  Realtime_Parallel_If.Slave data_in, // all channels in parallel
  Axis_If.Master data_out,
  Axis_If.Slave config_in, // {banking_mode}, can only be updated when buffer is in IDLE state
  Axis_If.Slave start_stop, // {start, stop}
  // stop_aux allows parallel operation of separate buffers
  // (e.g. for timestamp/data buffers in sparse sample buffer)
  // when one buffer fills, it can trigger a stop on all other buffers
  // start_aux allows the AWG or another signal source to trigger capture
  input wire stop_aux, start_aux,
  output logic capture_started, buffer_full
);

assign start_stop.ready = 1'b1; // don't apply backpressure, always allow start/stop of capture

// There are $clog2(CHANNELS) + 1 banking modes for CHANNELS ADC channels
// e.g. for 8 channels: single-channel mode, dual-channel, 4-channel, and 8-channel modes
// e.g. for 16 channels: single-channel mode, dual-channel, 4-channel, 8-channel, and 16-channel modes
localparam int N_BANKING_MODES = $clog2(CHANNELS) + 1;
logic [$clog2(N_BANKING_MODES)-1:0] banking_mode;
logic [$clog2(CHANNELS+1)-1:0] n_active_channels; // will have an extra bit so we can represent n from [0,...CHANNELS]
assign n_active_channels = 1'b1 << banking_mode;
logic start, stop;
assign capture_started = start;

// Only allow the configuration to be updated when the banks are idling
always_ff @(posedge clk) begin
  if (reset) begin
    config_in.ready <= 1'b1;
  end else begin
    if (start) begin
      config_in.ready <= 1'b0;
    end
    if (data_out.ok & data_out.last) begin
      config_in.ready <= 1'b1;
    end
  end
end

/////////////////////////////////////////////////////
// Process new configuration data
/////////////////////////////////////////////////////
// Capture is only automatically stopped when (one of) the final bank(s) fills up
// Use the appropriate mask on banks_full to decide when to stop capture.
// For 8 channels:
// if banking_mode == 0: mask = 0x80 (10000000)
// if banking_mode == 1: mask = 0xc0 (11000000)
// if banking_mode == 2: mask = 0xf0 (11110000)
// if banking_mode == 3: mask = 0xff (11111111)
logic [CHANNELS-1:0] full_mask;
always_ff @(posedge clk) begin
  if (reset) begin
    start <= '0;
    stop <= '0;
    banking_mode <= '0;
  end else begin
    if (config_in.ok) begin
      for (int channel = 0; channel < CHANNELS; channel++) begin
        if (channel > ((1 << config_in.data) - 1)) begin
          full_mask[CHANNELS-1-channel] <= 1'b0;
        end else begin
          full_mask[CHANNELS-1-channel] <= 1'b1;
        end
      end
      banking_mode <= config_in.data;
    end
    if (start_stop.valid) begin
      start <= start_stop.data[1];
      stop <= start_stop.data[0];
    end else begin
      // reset start/stop so they are only a pulse
      start <= '0;
      stop <= '0;
    end
  end
end

// logic to track when banks fill up and trigger the stop of other banks when
// one bank fills up
logic [CHANNELS-1:0] banks_full, banks_full_latch;
logic banks_stop;
// output a flag when the buffer fills up so we can stop other buffers running in parallel
assign buffer_full = |(full_mask & banks_full);
assign banks_stop = stop | stop_aux | buffer_full;

// latch banks_full: when operating with banking_mode < MAX_BANKING_MODE,
// multiple banks are assigned to the same input channel. They are filled in
// order, so later banks are only accessed after earlier banks are filled up.
// if the input data is sparse (i.e. the valid signal is not high very often),
// which can happen at lower sample rates and a readout is initiated before
// all of the banks fill up, then earlier banks can be fully read out while
// new data is still coming in.
// 
// banks_full_latch pretends previous banks are still full even after they've
// been fully read out. When arriving data is sparse in time, a previous bank
// may be read out before the currently selected bank is done capturing samples,
// causing it to erroneously stop sample capture (since it's data_in.valid signal goes low)
// *essentially*: as soon as a bank is full, treat it as if it's full until all of the banks
// are read out (instead of treating it as no longer full once it is read out)
always_ff @(posedge clk) begin
  if (reset) begin
    banks_full_latch <= '0;
  end else begin
    if (data_out.last && data_out.ok) begin
      // reset when we're done reading out all banks
      banks_full_latch <= '0;
    end else begin
      for (int i = 0; i < CHANNELS; i++) begin
        if (banks_full[i]) begin
          banks_full_latch[i] <= 1'b1;
        end
      end
    end
  end
end


// bundle of axistreams for each bank output
Axis_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) all_banks_out ();

// select which bank we're actively reading out
logic [$clog2(CHANNELS)-1:0] bank_select;
always_ff @(posedge clk) begin
  if (reset) begin
    bank_select <= '0;
  end else begin
    if (start) begin
      bank_select <= '0;
    end else if (all_banks_out.ok[bank_select] && all_banks_out.last[bank_select]) begin
      if (bank_select == $clog2(CHANNELS)'(CHANNELS - 1)) begin
        bank_select <= '0;
      end else begin
        bank_select <= bank_select + 1'b1;
      end
    end
  end
end

// mux outputs from banks
always_ff @(posedge clk) begin
  if (reset) begin
    data_out.data <= '0;
    data_out.valid <= 1'b0;
    data_out.last <= '0;
  end else begin
    if (data_out.ready) begin
      data_out.data <= all_banks_out.data[bank_select];
      data_out.valid <= all_banks_out.valid[bank_select];
      // only take last signal from the final bank, and only when the final bank is selected
      data_out.last <= (bank_select == $clog2(CHANNELS)'(CHANNELS - 1)) && all_banks_out.last[bank_select];
    end
  end
end

// only supply a ready signal to the bank currently selected for readout
always_comb begin
  for (int i = 0; i < CHANNELS; i++) begin
    if ($clog2(CHANNELS)'(i) == bank_select) begin
      all_banks_out.ready[i] = data_out.ready;
    end else begin
      all_banks_out.ready[i] = 1'b0; // stall all other banks until we're done reading out the current one
    end
  end
end

// generate banks
genvar i;
generate
  for (i = 0; i < CHANNELS; i++) begin: bank_i
    // only a single interface, but PARALLEL_SAMPLES wide
    // CHANNELS is used for multiple parallel interfaces with separate valid/ready
    Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) bank_in ();
    Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) bank_out ();

    logic first_sample;

    logic [$clog2(CHANNELS+1)-1:0] channel_id;

    assign channel_id = $clog2(CHANNELS+1)'(i) % n_active_channels;

    // connect bank_out to all_banks_out
    // mux first sample from the bank with the channel ID
    assign all_banks_out.data[i] = first_sample ? (SAMPLE_WIDTH*PARALLEL_SAMPLES)'(channel_id) : bank_out.data;
    assign all_banks_out.valid[i] = bank_out.valid;
    assign all_banks_out.last[i] = bank_out.last;
    assign bank_out.ready = all_banks_out.ready[i];

    assign bank_in.last = 1'b0; // unused; tie to 0 to suppress warnings

    sample_buffer_bank #(
      .BUFFER_DEPTH(BUFFER_DEPTH),
      .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
      .SAMPLE_WIDTH(SAMPLE_WIDTH)
    ) bank_i (
      .clk,
      .reset,
      .data_in(bank_in),
      .data_out(bank_out),
      .start(start | start_aux),
      .stop(banks_stop),
      .full(banks_full[i]),
      .first(first_sample)
    );

    // mux the channels of data_in depending on banking_mode
    logic valid_d; // match latency of registered data input
    // when chaining banks in series, which bank should the current bank i wait for
    always_comb begin
      if ((n_active_channels != $clog2(CHANNELS+1)'(CHANNELS)) && ($clog2(CHANNELS+1)'(i) >= n_active_channels)) begin
        // if the banking mode is not fully-independent (i.e. fewer than the
        // maximum number of channels are in use), then only activate the
        // current bank if previous banks are full
        bank_in.valid = valid_d & (banks_full[$clog2(CHANNELS)'($clog2(CHANNELS+1)'(i) - n_active_channels)] | banks_full_latch[$clog2(CHANNELS)'($clog2(CHANNELS+1)'(i) - n_active_channels)]);
      end else begin
        bank_in.valid = valid_d;
      end
    end
    always_ff @(posedge clk) begin
      bank_in.data <= data_in.data[$clog2(CHANNELS)'(channel_id)];
      valid_d <= data_in.valid[$clog2(CHANNELS)'(channel_id)];
    end
  end
endgenerate

endmodule
