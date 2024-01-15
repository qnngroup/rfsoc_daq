// sparse_sample_buffer - Reed Foster
// performs threshold-based sample discrimination on multiple channels and
// saves the results (raw data and timestamps) in a banked sample buffer
module sparse_sample_buffer #(
  parameter int CHANNELS = 2, // number of input channels
  parameter int TSTAMP_BUFFER_DEPTH = 1024, // depth of timestamp buffer
  parameter int DATA_BUFFER_DEPTH = 32768, // depth of data/sample buffer
  parameter int AXI_MM_WIDTH = 128, // width of DMA AXI-stream interface
  parameter int PARALLEL_SAMPLES = 1, // number of parallel samples per clock cycle per channel
  parameter int SAMPLE_WIDTH = 16, // width in bits of each sample
  parameter int APPROX_CLOCK_WIDTH = 48 // requested width of timestamp
) (
  input wire clk, reset,
  output logic [31:0] timestamp_width, // output so that PS can correctly parse output data
  output logic capture_done,
  Realtime_Parallel_If.Slave data_in, // all channels in parallel
  Axis_If.Master data_out,
  Axis_If.Slave sample_discriminator_config, // {threshold_high, threshold_low} for each channel
  // banking mode (0: 1 channel, 1: 2 channels, 2: 4 channels, 3: 8 channels)
  Axis_If.Slave buffer_config, // {banking_mode}, can only be updated when buffer is in IDLE state
  Axis_If.Slave buffer_start_stop, // {start, stop}
  input wire start_aux // auxiliary trigger for capture start
);

// always allow capture to be started/stopped manually
assign buffer_start_stop.ready = 1'b1;

localparam int SAMPLE_INDEX_WIDTH = $clog2(DATA_BUFFER_DEPTH*CHANNELS);
localparam int TIMESTAMP_WIDTH = SAMPLE_WIDTH * ((SAMPLE_INDEX_WIDTH + APPROX_CLOCK_WIDTH + (SAMPLE_WIDTH - 1)) / SAMPLE_WIDTH);
assign timestamp_width = TIMESTAMP_WIDTH;

// when either buffer fills up, it triggers a stop on the other with the stop_aux input
logic [1:0] buffer_full;

// discriminator outputs
Realtime_Parallel_If #(.DWIDTH(TIMESTAMP_WIDTH), .CHANNELS(CHANNELS)) disc_timestamps();
Realtime_Parallel_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES), .CHANNELS(CHANNELS)) disc_data();
// config interfaces to timestamp and data buffers
Axis_If #(.DWIDTH($clog2($clog2(CHANNELS)+1))) buffer_timestamp_config ();
Axis_If #(.DWIDTH($clog2($clog2(CHANNELS)+1))) buffer_data_config ();
Axis_If #(.DWIDTH(2)) buffer_timestamp_start_stop ();
Axis_If #(.DWIDTH(2)) buffer_data_start_stop ();
// raw buffer outputs
Axis_If #(.DWIDTH(TIMESTAMP_WIDTH)) buffer_timestamp_out ();
Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) buffer_data_out ();
// resized buffer outputs that are ready for multiplexing
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) buffer_timestamp_out_resized ();
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) buffer_data_out_resized ();

// only accept a new configuration when both buffers are ready
assign buffer_config.ready = buffer_timestamp_config.ready & buffer_data_config.ready;
// share buffer_config data/valid between both buffers so their configuration is synchronized
assign buffer_timestamp_config.data = buffer_config.data;
assign buffer_timestamp_config.valid = buffer_config.valid;
assign buffer_timestamp_config.last = 1'b0; // unused; tie to 0 to suppress warnings
assign buffer_data_config.data = buffer_config.data;
assign buffer_data_config.valid = buffer_config.valid;
assign buffer_data_config.last = 1'b0; // unused; tie to 0 to suppress warnings

// share buffer_start_stop
assign buffer_timestamp_start_stop.data = buffer_start_stop.data;
assign buffer_timestamp_start_stop.valid = buffer_start_stop.valid;
assign buffer_timestamp_start_stop.last = 1'b0; // unused; tie to 0 to suppress warnings
assign buffer_data_start_stop.data = buffer_start_stop.data;
assign buffer_data_start_stop.valid = buffer_start_stop.valid;
assign buffer_data_start_stop.last = 1'b0; // unused; tie to 0 to suppress warnings

(* MARK_DEBUG = "TRUE" *)
logic start;
(* MARK_DEBUG = "TRUE" *)
logic start_aux_d;
always_ff @(posedge clk) begin
  if (reset) begin
    start <= '0;
    start_aux_d <= '0;
  end else begin
    start_aux_d <= start_aux;
    if (buffer_start_stop.ok) begin
      start <= buffer_start_stop.data[1];
    end else begin
      start <= 1'b0; // reset start so we just get a pulse (sample_buffer does the same thing)
    end
  end
end

(* MARK_DEBUG = "TRUE" *)
logic trigger_enabled; // TODO actually put this logic inside the sample buffer / buffer_bank

(* MARK_DEBUG = "TRUE" *)
logic capture_done_dbg;
assign capture_done_dbg = capture_done;

assign capture_done = |buffer_full;
always_ff @(posedge clk) begin
  if (reset) begin
    trigger_enabled <= 1'b1;
  end else begin
    if (data_out.last & data_out.ok) begin
      trigger_enabled <= 1'b1;
    end else if ((start_aux & ~start_aux_d) | start) begin // if we start a capture, reset trigger enable
      trigger_enabled <= 1'b0;
    end
  end
end

(* MARK_DEBUG = "TRUE" *)
logic dma_valid_dbg;
(* MARK_DEBUG = "TRUE" *)
logic dma_ready_dbg;
(* MARK_DEBUG = "TRUE" *)
logic dma_last_dbg;

assign dma_valid_dbg = data_out.valid;
assign dma_ready_dbg = data_out.ready;
assign dma_last_dbg = data_out.last;

(* MARK_DEBUG = "TRUE" *)
logic triggered_start;
always_ff @(posedge clk) begin
  triggered_start <= trigger_enabled & start_aux & ~start_aux_d;
end

sample_discriminator #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS),
  .SAMPLE_INDEX_WIDTH(SAMPLE_INDEX_WIDTH),
  .CLOCK_WIDTH(TIMESTAMP_WIDTH - SAMPLE_INDEX_WIDTH)
) disc_i (
  .clk,
  .reset,
  .data_in,
  .data_out(disc_data),
  .timestamps_out(disc_timestamps),
  .config_in(sample_discriminator_config),
  .reset_state(start | triggered_start) // reset sample_index count and is_high whenever a new capture is started
);

sample_buffer #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .BUFFER_DEPTH(DATA_BUFFER_DEPTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .CHANNELS(CHANNELS)
) data_buffer_i (
  .clk,
  .reset,
  .data_in(disc_data),
  .data_out(buffer_data_out),
  .config_in(buffer_data_config),
  .start_stop(buffer_data_start_stop),
  .stop_aux(buffer_full[0]), // stop saving data when timestamp buffer is full
  .start_aux(triggered_start), // start capture on rising edge of start_aux, but only if buffer is empty
  .capture_started(),
  .buffer_full(buffer_full[1])
);

sample_buffer #(
  .SAMPLE_WIDTH(TIMESTAMP_WIDTH),
  .BUFFER_DEPTH(TSTAMP_BUFFER_DEPTH),
  .PARALLEL_SAMPLES(1),
  .CHANNELS(CHANNELS)
) timestamp_buffer_i (
  .clk,
  .reset,
  .data_in(disc_timestamps),
  .data_out(buffer_timestamp_out),
  .config_in(buffer_timestamp_config),
  .start_stop(buffer_timestamp_start_stop),
  .stop_aux(buffer_full[1]), // stop saving timestamps when data buffer is full
  .start_aux(triggered_start), // start capture on rising edge of start_aux, but only if buffer is empty
  .capture_started(),
  .buffer_full(buffer_full[0])
);

// merge both buffer outputs into a word that is AXI_MM_WIDTH bits
// first step down/up the width of the outputs

axis_width_converter #(
  .DWIDTH_IN(SAMPLE_WIDTH*PARALLEL_SAMPLES),
  .DWIDTH_OUT(AXI_MM_WIDTH)
) data_width_converter_i (
  .clk,
  .reset,
  .data_in(buffer_data_out),
  .data_out(buffer_data_out_resized)
);

axis_width_converter #(
  .DWIDTH_IN(TIMESTAMP_WIDTH),
  .DWIDTH_OUT(AXI_MM_WIDTH)
) timestamp_width_converter_i (
  .clk,
  .reset,
  .data_in(buffer_timestamp_out),
  .data_out(buffer_timestamp_out_resized)
);

// mux the two outputs
// state machine
// first output all the timestamps, then all the data
enum {TIMESTAMP, DATA} buffer_select;

always_ff @(posedge clk) begin
  if (reset) begin
    buffer_select <= TIMESTAMP;
  end else begin
    unique case (buffer_select)
      TIMESTAMP: if (buffer_timestamp_out_resized.last && buffer_timestamp_out_resized.ok) buffer_select <= DATA;
      DATA: if (buffer_data_out_resized.last && buffer_data_out_resized.ok) buffer_select <= TIMESTAMP;
    endcase
  end
end

// mux data, valid, and last
always_comb begin
  unique case (buffer_select)
    TIMESTAMP: begin
      data_out.data = buffer_timestamp_out_resized.data;
      data_out.valid = buffer_timestamp_out_resized.valid;
      data_out.last = 1'b0; // don't send last for timestamp data
    end
    DATA: begin
      data_out.data = buffer_data_out_resized.data;
      data_out.valid = buffer_data_out_resized.valid;
      data_out.last = buffer_data_out_resized.last;
    end
  endcase
end

assign buffer_timestamp_out_resized.ready = (buffer_select == TIMESTAMP) ? data_out.ready : 1'b0;
assign buffer_data_out_resized.ready = (buffer_select == DATA) ? data_out.ready : 1'b0;

endmodule
