// buffer_dual_clock.sv - Reed Foster
// collection of BRAM buffers with independent read/write clocks

`timescale 1ns/1ps
module buffer_dual_clock #(
  parameter int CHANNELS = 8,
  parameter int BUFFER_DEPTH = 256,
  parameter int DATA_WIDTH = 256,
  parameter int READ_LATENCY = 4
) (
  // ADC clock, reset (512 MHz)
  input wire capture_clk, capture_reset,
  // data
  Realtime_Parallel_If.Slave capture_data,
  // configuration
  // banking mode: 1 << banking_mode active channels (banking_mode == MAX -> independent capture)
  input wire [$clog2($clog2(CHANNELS)+1)-1:0] capture_banking_mode,
  input wire capture_start, // software/PS-triggered start of capture (gated by capture FSM)
  input wire capture_stop, // software/PS-triggered stop of capture (gated by capture FSM)
  output logic capture_full, // asserted when any active buffers* fill
  // *for non-independent banking modes (banking_mode < MAX), buffers are
  // chained together, increasing the write depth
  output logic [CHANNELS-1:0][$clog2(BUFFER_DEPTH+1)-1:0] capture_write_depth,
  input wire capture_sw_reset, // manual software/PS-triggered reset

  // Readout (PS) clock, reset (100 MHz)
  input wire readout_clk, readout_reset,
  Axis_If.Master readout_data,
  // 
  input wire readout_sw_reset,
  input wire readout_start

);

localparam int ADDR_WIDTH = $clog2(BUFFER_DEPTH);
logic [DATA_WIDTH-1:0] memory [CHANNELS][BUFFER_DEPTH];

////////////////////////////////////////////////////////
// Capture clock domain
////////////////////////////////////////////////////////

// register start/stop so that we can detect rising edge
logic capture_start_d, capture_stop_d;
always_ff @(posedge capture_clk) begin
  capture_start_d <= capture_start;
  capture_stop_d <= capture_stop;
end

// enable sample capture on rising edge of start, disable on rising edge of
// stop, or if buffer fills up
logic capture_enabled;

// delay write address to match latency of valid/data pipeline registers
logic [CHANNELS-1:0][ADDR_WIDTH-1:0] capture_write_addr, capture_write_addr_d;
always_ff @(posedge capture_clk) capture_write_addr_d <= capture_write_addr;

// track when banks are full
logic [CHANNELS-1:0] capture_bank_full, capture_bank_full_latch;

always_ff @(posedge capture_clk) begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    capture_write_depth[channel] <= {capture_bank_full_latch[channel], capture_write_addr[channel]};
  end
end

// reset write address and full status when readout is done (CDC'd from
// readout clock domain)
logic capture_dma_done;

// banking mode
logic [$clog2($clog2(CHANNELS)+1)-1:0] capture_banking_mode_reg; // latch input banking mode when capture is started
logic [$clog2(CHANNELS+1)-1:0] capture_active_channels; // [0, ... CHANNELS]
assign capture_active_channels = 1'b1 << capture_banking_mode_reg; // number of active channels

// masks for different channel modes
logic [CHANNELS-1:0] capture_full_mask, capture_valid_mask;

// data in and muxed data to banks
logic [CHANNELS-1:0][DATA_WIDTH-1:0] capture_data_d, capture_buffer_in;

always_ff @(posedge capture_clk) capture_data_d <= capture_data.data;

// mux data based on banking_mode
always_ff @(posedge capture_clk) begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    capture_buffer_in[channel] <= capture_data_d[$clog2(CHANNELS)'($clog2(CHANNELS+1)'(channel) % capture_active_channels)];
  end
end

// valid->write_enable
logic [CHANNELS-1:0] capture_valid_d;
logic [CHANNELS-1:0] capture_write_enable, capture_write_enable_d;

// valid->write_enable path (combinatorial, since we need to update address in a combinatorial loop ??)
always_comb begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    capture_write_enable[channel] = capture_enabled & capture_valid_mask[channel]
                                      & capture_valid_d[$clog2(CHANNELS)'($clog2(CHANNELS+1)'(channel) % capture_active_channels)];
  end
end
// register write_enable and valid
always_ff @(posedge capture_clk) begin
  capture_valid_d <= capture_data.valid;
  capture_write_enable_d <= capture_write_enable;
end

// latch banking mode on capture start
always_ff @(posedge capture_clk) begin
  if (capture_reset) begin
    capture_banking_mode_reg <= '0;
  end else begin
    if (capture_start & ~capture_start_d) begin
      capture_banking_mode_reg <= capture_banking_mode;
    end
  end
end
// latch full mask on capture start
always_ff @(posedge capture_clk) begin
  if (capture_reset) begin
    capture_full_mask <= '0;
  end else begin
    if (capture_start & ~capture_start_d) begin
      for (int channel = 0; channel < CHANNELS; channel++) begin
        // For 8 channels:
        // if banking_mode == 0 (1 active channels): mask = 0x80 (10000000)
        // if banking_mode == 1 (2 active channels): mask = 0xc0 (11000000)
        // if banking_mode == 2 (4 active channels): mask = 0xf0 (11110000)
        // if banking_mode == 3 (8 active channels): mask = 0xff (11111111)
        capture_full_mask[CHANNELS-1-channel] <= channel + 1 > (1 << capture_banking_mode) ? 1'b0 : 1'b1;
      end
    end
  end
end

// update write address
always_comb begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    capture_bank_full[channel] = capture_write_addr[channel] == $clog2(BUFFER_DEPTH)'(BUFFER_DEPTH - 1) & capture_write_enable[channel];
  end
end
always_ff @(posedge capture_clk) begin
  if (capture_reset) begin
    capture_write_addr <= '0;
  end else begin
    if (capture_sw_reset | capture_dma_done) begin
      capture_write_addr <= '0;
    end else begin
      for (int channel = 0; channel < CHANNELS; channel++) begin
        if (capture_write_enable[channel]) begin// & ~capture_bank_full[channel]) begin
          capture_write_addr[channel] <= capture_write_addr[channel] + 1;
        end
      end
    end
  end
end

// update valid mask
always_ff @(posedge capture_clk) begin
  if (capture_reset) begin
    capture_valid_mask <= '0;
  end else begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      if (capture_start & ~capture_start_d) begin
        // initialized almost same as capture_full_mask, just bitswapped
        // For 8 channels:
        // if banking_mode == 0 (1 active channels): mask = 0x01 (10000000)
        // if banking_mode == 1 (2 active channels): mask = 0x03 (11000000)
        // if banking_mode == 2 (4 active channels): mask = 0x0f (11110000)
        // if banking_mode == 3 (8 active channels): mask = 0xff (11111111)
        capture_valid_mask[channel] <= (channel + 1 > (1 << capture_banking_mode)) ? 1'b0 : 1'b1;
      end else begin
        // when a bank fills up, update which bank is active by shifting the
        // bits in the mask based on the current banking mode
        if (capture_bank_full[channel]) begin
          // reset the current valid mask -> we shouldn't write to this bank anymore
          capture_valid_mask[channel] <= 1'b0;
          if (capture_valid_mask[channel]) begin
            // if we're resetting the current valid mask (i.e. it wasn't reset
            // in a previous clock cycle), then set a subsequent mask bit whose
            // distance from the current bit is determined by the banking mode
            if ($clog2(CHANNELS+1)'(channel) + capture_active_channels < $clog2(CHANNELS+1)'(CHANNELS)) begin
              capture_valid_mask[$clog2(CHANNELS)'($clog2(CHANNELS+1)'(channel) + capture_active_channels)] <= 1'b1;
            end
          end
        end
      end
    end
  end
end

// full logic
always_ff @(posedge capture_clk) begin
  if (capture_reset) begin
    capture_bank_full_latch <= '0;
  end else begin
    if (capture_sw_reset | capture_dma_done) begin
      capture_bank_full_latch <= '0;
    end else begin
      for (int channel = 0; channel < CHANNELS; channel++) begin
        if (capture_bank_full[channel]) begin
          capture_bank_full_latch[channel] <= capture_bank_full[channel];
        end
      end
    end
  end
end

assign capture_full = |(capture_full_mask & capture_bank_full_latch);

// update enabled SR flipflop
always_ff @(posedge capture_clk) begin
  if (capture_reset) begin
    capture_enabled <= 1'b0;
  end else begin
    if (capture_start & ~capture_start_d) begin
      capture_enabled <= 1'b1;
    end else if ((capture_stop & ~capture_stop_d) | (|(capture_bank_full & capture_full_mask))) begin
      capture_enabled <= 1'b0;
    end
  end
end

////////////////////////////////////////////////////////
// Readout clock domain
////////////////////////////////////////////////////////
logic [ADDR_WIDTH-1:0] readout_read_addr;
logic [$clog2(CHANNELS)-1:0] readout_bank_select;

logic [CHANNELS-1:0][READ_LATENCY-1:0][DATA_WIDTH-1:0] readout_data_pipe;
logic [READ_LATENCY-1:0][$clog2(CHANNELS)-1:0] readout_bank_select_pipe;
logic [READ_LATENCY-1:0] readout_valid_pipe, readout_last_pipe;

logic readout_enable, readout_active;
logic readout_last;

assign readout_last = (readout_read_addr == ADDR_WIDTH'(BUFFER_DEPTH - 1)) & (readout_bank_select == $clog2(CHANNELS)'(CHANNELS - 1));
assign readout_enable = readout_active & (readout_data.ready | ~readout_data.valid);

logic readout_start_d;
always_ff @(posedge readout_clk) readout_start_d <= readout_start;
logic readout_dma_done;
assign readout_dma_done = readout_data.ok & readout_data.last;

// pipeline for valid/last and bank_select
always_ff @(posedge readout_clk) begin
  if (readout_reset) begin
    readout_valid_pipe <= '0;
    readout_last_pipe <= '0;
    readout_data.valid <= '0;
    readout_data.last <= '0;
    readout_bank_select_pipe <= '0;
  end else begin
    if (readout_data.ready | ~readout_data.valid) begin
      readout_valid_pipe <= {readout_valid_pipe[READ_LATENCY-2:0], readout_active};
      readout_last_pipe <= {readout_last_pipe[READ_LATENCY-2:0], readout_last};
      readout_data.valid <= readout_valid_pipe[READ_LATENCY-1];
      readout_data.last <= readout_last_pipe[READ_LATENCY-1];
      readout_bank_select_pipe <= {readout_bank_select_pipe[READ_LATENCY-2:0], readout_bank_select};
    end
  end
end

// update read address and bank select
always_ff @(posedge readout_clk) begin
  if (readout_reset) begin
    readout_read_addr <= '0;
    readout_bank_select <= '0;
  end else begin
    if (readout_sw_reset | (readout_start & ~readout_start_d)) begin
      readout_read_addr <= '0;
      readout_bank_select <= '0;
    end else begin
      if (readout_enable) begin
        if (readout_read_addr == ADDR_WIDTH'(BUFFER_DEPTH - 1)) begin
          readout_read_addr <= 0;
          if (readout_bank_select == $clog2(CHANNELS)'(CHANNELS - 1)) begin
            readout_bank_select <= 0;
          end else begin
            readout_bank_select <= readout_bank_select + 1;
          end
        end else begin
          readout_read_addr <= readout_read_addr + 1;
        end
      end
    end
  end
end

// SR flip-flop for readout_active
always_ff @(posedge readout_clk) begin
  if (readout_reset) begin
    readout_active <= 1'b0;
  end else begin
    if (readout_start & ~readout_start_d) begin
      readout_active <= 1'b1;
    end else if (readout_last & readout_data.ready) begin
      readout_active <= 1'b0;
    end
  end
end

// mux output
always_ff @(posedge readout_clk) begin
  if (readout_data.ready | ~readout_data.valid) begin
    readout_data.data <= readout_data_pipe[readout_bank_select_pipe[READ_LATENCY-1]][READ_LATENCY-1];
  end
end

////////////////////////////////////////////////////////
// Clock crossing and memory
////////////////////////////////////////////////////////

xpm_cdc_pulse #(
  .DEST_SYNC_FF(4), // 4 synchronization stages
  .INIT_SYNC_FF(0), // don't allow behavioral initialization
  .REG_OUTPUT(1), // register the output
  .RST_USED(1), // use resets
  .SIM_ASSERT_CHK(1) // report potential violations
) dma_done_cdc_i (
  .src_clk(readout_clk),
  .src_rst(readout_reset),
  .src_pulse(readout_dma_done),
  .dest_clk(capture_clk),
  .dest_rst(capture_reset),
  .dest_pulse(capture_dma_done)
);

always_ff @(posedge capture_clk) begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    // write to memory
    if (capture_write_enable_d[channel]) begin
      memory[channel][capture_write_addr_d[channel]] <= capture_buffer_in[channel];
    end
  end
end

always_ff @(posedge readout_clk) begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    if (readout_data.ready | ~readout_data.valid) begin
      readout_data_pipe[channel] <= {readout_data_pipe[channel][READ_LATENCY-2:0], memory[channel][readout_read_addr]};
    end
  end
end


endmodule
