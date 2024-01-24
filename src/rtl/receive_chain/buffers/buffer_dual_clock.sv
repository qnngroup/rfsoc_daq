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
  output logic [CHANNELS-1:0][$clog2(BUFFER_DEPTH)-1:0] capture_write_addr,
  input wire capture_sw_reset, // manual software/PS-triggered reset

  // Readout (PS) clock, reset (100 MHz)
  input wire readout_clk, readout_reset,
  Axis_Parallel_If.Master readout_data,
  // 
  input wire readout_enable

);

localparam int ADDR_WIDTH = $clog2(BUFFER_DEPTH);
logic [DATA_WIDTH-1:0] memory [BUFFER_DEPTH][CHANNELS];

////////////////////////////////////////////////////////
// Capture clock domain
////////////////////////////////////////////////////////

// register start/stop so that we can detect rising edge
logic capture_start_reg, capture_stop_reg;
always_ff @(posedge capture_clk) begin
  capture_start_reg <= capture_start;
  capture_stop_reg <= capture_stop;
end

// manage writing to banks
logic [CHANNELS-1:0][ADDR_WIDTH-1:0] capture_write_addr_d; // delay write address to match latency of valid/data pipeline registers
logic [CHANNELS-1:0] capture_bank_full, capture_bank_full_latch; // track when banks are full

// banking mode
logic [$clog2($clog2(CHANNELS)+1)-1:0] capture_banking_mode_reg; // latch input banking mode when capture is started
logic [$clog2(CHANNELS+1)-1:0] capture_active_channels; // [0, ... CHANNELS]
assign capture_active_channels = 1'b1 << capture_banking_mode_reg; // number of active channels

// masks for different channel modes
logic [CHANNELS-1:0] capture_full_mask, capture_valid_mask;

// data in and muxed data to banks
logic [CHANNELS-1:0][DATA_WIDTH-1:0] capture_data_reg, capture_buffer_in;

// mux data based on banking_mode
always_ff @(posedge capture_clk) begin
  capture_data_reg <= capture_data.data;
  for (int channel = 0; channel < CHANNELS; channel++) begin
    capture_buffer_in[channel] <= capture_data_reg[$clog2(CHANNELS)'(channel % capture_active_channels)];
  end
end

// valid->write_enable
logic [CHANNELS-1:0] capture_valid_reg;
logic [CHANNELS-1:0] capture_write_enable, capture_write_enable_reg;

// valid->write_enable path (combinatorial, since we need to update address in a combinatorial loop ??)
always_comb begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    capture_write_enable[channel] = capture_start_reg & capture_valid_mask[channel]
                                      & capture_valid_reg[$clog2(CHANNELS)'(channel % capture_active_channels)];
  end
end
// register write_enable and valid
always_ff @(posedge capture_clk) begin
  capture_valid_reg <= capture_data.valid;
  capture_write_enable_reg <= capture_write_enable;
end

// latch banking mode on capture start
always_ff @(posedge capture_clk) begin
  if (capture_reset) begin
    capture_banking_mode_reg <= '0;
  end else begin
    if (capture_start & ~capture_start_reg) begin
      capture_banking_mode_reg <= capture_banking_mode;
    end
  end
end
// latch full mask on capture start
always_ff @(posedge capture_clk) begin
  if (capture_reset) begin
    capture_full_mask <= '0;
  end else begin
    if (capture_start & ~capture_start_reg) begin
      for (int channel = 0; channel < CHANNELS; channel++) begin
        // For 8 channels:
        // if banking_mode == 0 (1 active channels): mask = 0x80 (10000000)
        // if banking_mode == 1 (2 active channels): mask = 0xc0 (11000000)
        // if banking_mode == 2 (4 active channels): mask = 0xf0 (11110000)
        // if banking_mode == 3 (8 active channels): mask = 0xff (11111111)
        capture_full_mask[CHANNELS-1-channel] <= channel + 1 > (1 << capture_banking_mode) ? 1'b1 : 1'b0;
      end
    end
  end
end

// update write address
always_comb begin
  for (int channel = 0; channel < CHANNELS; channel++) begin
    capture_bank_full[channel] = capture_write_addr == $clog2(BUFFER_DEPTH)'(BUFFER_DEPTH - 1);
  end
end
always_ff @(posedge capture_clk) begin
  capture_write_addr_d <= capture_write_addr;
  if (capture_reset) begin
    capture_write_addr <= '0;
  end else begin
    if (capture_sw_reset | capture_readout_done) begin
      capture_write_addr <= '0;
    end else begin
      for (int channel = 0; channel < CHANNELS; channel++) begin
        if (capture_write_enable[channel] & ~capture_bank_full[channel]) begin
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
      if (capture_start & ~capture_start_reg) begin
        // initialize to same as capture_full_mask
        // For 8 channels:
        // if banking_mode == 0 (1 active channels): mask = 0x80 (10000000)
        // if banking_mode == 1 (2 active channels): mask = 0xc0 (11000000)
        // if banking_mode == 2 (4 active channels): mask = 0xf0 (11110000)
        // if banking_mode == 3 (8 active channels): mask = 0xff (11111111)
        capture_valid_mask[CHANNELS-1-channel] <= channel + 1 > (1 << capture_banking_mode) ? 1'b1 : 1'b0;
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
            if (channel + capture_active_channels < CHANNELS) begin
              capture_valid_mask[channel + capture_active_channels] <= 1'b1;
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
    if (capture_sw_reset | capture_readout_done) begin
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

assign full = |capture_bank_full_latch;

////////////////////////////////////////////////////////
// Readout clock domain
////////////////////////////////////////////////////////
logic [CHANNELS-1:0][ADDR_WIDTH-1:0] readout_read_addr;


endmodule
