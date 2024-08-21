// buffer.sv - Reed Foster
// Save samples from ADC (either raw or processed samples) into a large buffer
// at a high rate. The buffer can later be read out at a slower rate over DMA
// so that further signal processing and analysis can be performed on the
// sample data
//
// Implemented as a collection of BRAM/URAM buffers with independent
// read/write clocks, as well as state machine to handle configuration updates
//
// Datastream interfaces
// - adc_data: data,valid pairs for rx_pkg::CHANNELS parallel stream interfaces
// - ps_readout_data: DMA data, always outputs
//
// Realtime I/O:
// - adc_capture_hw_start: input, hardware trigger for starting capture
// - adc_capture_hw_stop: input, hardware trigger for stopping capture
// - adc_capture_full: output, goes high when buffer fills up
//
// Configuration/command registers:
// - arm:
//    - arm the buffer for hardware-triggered capture
//    - 1-bit quantity
// - banking_mode:
//    - select how many channels are active
//    - enables deeper storage of sample data when fewer channels are active
//    - active_channels = 1 << banking_mode
//    - buffer_pkg::BANKING_MODE_WIDTH-bit quantity
// - capture/readout sw_reset:
//    - reset state machine and counters for capture and readout logic
//    - capture sw_reset can be asserted at any time
//        - capture reset will require re-arming of the buffer (performed
//          automatically by writing to the ps_capture_start register in the
//          segmented_buffer module) to save samples again
//    - readout sw_reset can only be asserted when the readout hardware is in
//      the DMA_ACTIVE state (this allows for re-trying failed DMA transfers)
//      and only resets to DMA_READY so that capture cannot be triggered again
//      (unless capture sw_reset is also asserted)
//    - 1-bit quantities
// - readout_start:
//    - initiate a readout of data
//
// Status registers:
// - ps_capture_write_depth:
//    - outputted every time a capture finishes
//    - flattened 2D array [rx_pkg::CHANNELS][$clog2(BUFFER_DEPTH)+1]
//    - for each channel, MSB indicates if buffer is full
//    - LSBs indicate the number of samples stored in the corresponding
//      bank

`timescale 1ns/1ps
module buffer #(
  parameter int DATA_WIDTH,
  parameter int BUFFER_DEPTH,
  parameter int READ_LATENCY // default 4 to permit UltraRAM inference
) (
  // ADC clock, reset (512 MHz)
  input wire adc_clk, adc_reset,
  // data
  Realtime_Parallel_If.Slave adc_data,
  // realtime ports
  input wire adc_capture_hw_start,
  input wire adc_capture_hw_stop,
  output logic adc_capture_ready, // asserted when adc_capture_state != HOLD_SAMPLES
  output logic adc_capture_full, // asserted when any active buffers fill

  // Readout (PS) clock, reset (100 MHz)
  input wire ps_clk, ps_reset,
  Axis_If.Master ps_readout_data,
  // Configuration
  Axis_If.Slave ps_capture_arm, // arms capture to prepare for hw_start
  Axis_If.Slave ps_capture_banking_mode, // controls capture (active_channels = 1 << banking_mode)
  Axis_If.Slave ps_capture_sw_reset, // ps clock domain; reset capture logic
  Axis_If.Slave ps_readout_sw_reset, // ps clock domain; reset readout logic
  Axis_If.Slave ps_readout_start, // enable DMA over ps_readout_data interface
  // Status
  Axis_If.Master ps_capture_write_depth // number of samples saved per bank; outputted after a capture completes
);

localparam int ADDR_WIDTH = $clog2(BUFFER_DEPTH);
logic [DATA_WIDTH-1:0] memory [rx_pkg::CHANNELS][BUFFER_DEPTH];

////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////
// Capture clock domain
////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////

// capture state machine
enum {CAPTURE_IDLE, TRIGGER_WAIT, SAVE_SAMPLES, HOLD_SAMPLES} adc_capture_state;

////////////////////////////////////////////////////////////
// Configuration and Status registers
// Allows for control/communication between PS and module
////////////////////////////////////////////////////////////

////////////////////////
// get number of active
// channels from
// banking_mode
////////////////////////
logic [$clog2(rx_pkg::CHANNELS+1)-1:0] adc_active_channels;
Axis_If #(.DWIDTH(buffer_pkg::BANKING_MODE_WIDTH)) adc_capture_banking_mode_sync ();
assign adc_capture_banking_mode_sync.ready = adc_capture_state == CAPTURE_IDLE;
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_active_channels <= $clog2(rx_pkg::CHANNELS+1)'(rx_pkg::CHANNELS);
  end else begin
    if (adc_capture_banking_mode_sync.valid & adc_capture_banking_mode_sync.ready) begin
      adc_active_channels <= 1 << adc_capture_banking_mode_sync.data;
    end
  end
end
// CDC for banking mode
axis_config_reg_cdc #(
  .DWIDTH(buffer_pkg::BANKING_MODE_WIDTH)
) capture_banking_mode_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_capture_banking_mode),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_capture_banking_mode_sync)
);

////////////////////////
// sw_reset
////////////////////////
logic adc_capture_reset;
Axis_If #(.DWIDTH(1)) adc_capture_reset_sync ();
assign adc_capture_reset_sync.ready = 1'b1; // always accept sw_reset
assign adc_capture_reset = (adc_capture_reset_sync.data == 1) & adc_capture_reset_sync.valid & adc_capture_reset_sync.ready;
// CDC for capture sw_reset
axis_config_reg_cdc #(
  .DWIDTH(1)
) capture_sw_reset_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_capture_sw_reset),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_capture_reset_sync)
);

////////////////////////
// arm, start, stop
////////////////////////
logic adc_capture_arm;
Axis_If #(.DWIDTH(1)) adc_capture_arm_sync ();
assign adc_capture_ready = (adc_capture_state != HOLD_SAMPLES);
assign adc_capture_arm_sync.ready = adc_capture_ready;
assign adc_capture_arm = (adc_capture_arm_sync.valid & adc_capture_arm_sync.ready) ? adc_capture_arm_sync.data : 1'b0;
// CDC for capture arm/start/stop
axis_config_reg_cdc #(
  .DWIDTH(1)
) capture_arm_cdc_i (
  .src_clk(ps_clk),
  .src_reset(ps_reset),
  .src(ps_capture_arm),
  .dest_clk(adc_clk),
  .dest_reset(adc_reset),
  .dest(adc_capture_arm_sync)
);
// gate start/stop signals from hw_start/hw_stop and sw_start/sw_start based on the current capture state
// arm is gated by the adc_capture_state FSM: adc_capture_state can only transition to
// the TRIGGER_WAIT state from the CAPTURE_IDLE state when arm is applied
logic adc_capture_start_pls, adc_capture_stop_pls;
assign adc_capture_start_pls = (adc_capture_state == TRIGGER_WAIT) & adc_capture_hw_start;
assign adc_capture_stop_pls = adc_capture_hw_stop & (adc_capture_state == SAVE_SAMPLES);
// register start so that we can detect rising edge

// enable sample capture on rising edge of start, disable on rising edge of
// stop, or if buffer fills up
logic adc_capture_active;
logic adc_capture_done_pls;

////////////////////////
// capture depth: track
// number of samples
// that were saved into
// each bank of the buffer
////////////////////////
logic [rx_pkg::CHANNELS-1:0][$clog2(BUFFER_DEPTH):0] adc_capture_write_depth;
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*($clog2(BUFFER_DEPTH)+1))) adc_capture_write_depth_sync ();
assign adc_capture_write_depth_sync.data = adc_capture_write_depth;
assign adc_capture_write_depth_sync.valid = adc_capture_done_pls;
assign adc_capture_write_depth_sync.last = 1'b1; // always final packet
// CDC for capture depth
axis_config_reg_cdc #(
  .DWIDTH(rx_pkg::CHANNELS*($clog2(BUFFER_DEPTH)+1))
) capture_write_depth_cdc_i (
  .src_clk(adc_clk),
  .src_reset(adc_reset),
  .src(adc_capture_write_depth_sync),
  .dest_clk(ps_clk),
  .dest_reset(ps_reset),
  .dest(ps_capture_write_depth)
);

////////////////////////////////////////////////////////////
// Buffer core logic
// Save samples and stop when buffer fills up
////////////////////////////////////////////////////////////

// delay write address to match latency of valid/data pipeline registers
logic [rx_pkg::CHANNELS-1:0][ADDR_WIDTH-1:0] adc_write_addr, adc_write_addr_d;
always_ff @(posedge adc_clk) adc_write_addr_d <= adc_write_addr;

// track when banks are full
logic [rx_pkg::CHANNELS-1:0] adc_bank_full, adc_bank_full_latch;
logic adc_capture_full_d; // delay so we can detect rising edge of capture_full
always_ff @(posedge adc_clk) adc_capture_full_d <= adc_capture_full;

// reset write address and full status when readout is done (CDC'd from readout clock domain)
logic adc_readout_done_pls;

// generate write enables and full signal dependent on number of active channels
// valid_mask and full_mask for different channel modes
// valid_mask is AND'd with muxed adc_valid_d to generate write_enables
logic [rx_pkg::CHANNELS-1:0] adc_capture_full_mask, adc_capture_valid_mask;
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    {adc_capture_full_mask, adc_capture_valid_mask} <= '0;
  end else begin
    for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
      // For 8 channels:
      // if active channels == 1: full_mask = 0x80 (10000000), valid_mask = 0x01 (00000001)
      // if active channels == 2: full_mask = 0xc0 (11000000), valid_mask = 0x03 (00000011)
      // if active channels == 4: full_mask = 0xf0 (11110000), valid_mask = 0x0f (00001111)
      // if active channels == 8: full_mask = 0xff (11111111), valid_mask = 0xff (11111111)
      adc_capture_full_mask[rx_pkg::CHANNELS-1-channel] <= channel + 1 > adc_active_channels ? 1'b0 : 1'b1;
      if (adc_capture_start_pls) begin
        // reset valid_mask 
        adc_capture_valid_mask[channel] <= channel + 1 > adc_active_channels ? 1'b0 : 1'b1;
      end else begin
        // when a bank fills up, update which bank is active by shifting the
        // bits in the mask based on the current banking mode
        if (adc_bank_full[channel]) begin
          // reset the current valid mask -> we shouldn't write to this bank anymore
          adc_capture_valid_mask[channel] <= 1'b0;
          if (adc_capture_valid_mask[channel]) begin
            // if we're resetting the current valid mask (i.e. it wasn't reset
            // in a previous clock cycle), then set a subsequent mask bit whose
            // distance from the current bit is determined by the banking mode
            if ($clog2(rx_pkg::CHANNELS+1)'(channel) + adc_active_channels < $clog2(rx_pkg::CHANNELS+1)'(rx_pkg::CHANNELS)) begin
              adc_capture_valid_mask[$clog2(rx_pkg::CHANNELS)'($clog2(rx_pkg::CHANNELS+1)'(channel) + adc_active_channels)] <= 1'b1;
            end
          end
        end
      end
    end
  end
end

////////////////////////////////////
// Data and valid mux
// Select one or more channels
// depending on banking mode
////////////////////////////////////
// register data in for timing
logic [rx_pkg::CHANNELS-1:0][DATA_WIDTH-1:0] adc_data_d;
always_ff @(posedge adc_clk) adc_data_d <= adc_data.data;

// mux data based on banking_mode (registered for timing)
logic [rx_pkg::CHANNELS-1:0][DATA_WIDTH-1:0] adc_buffer_in;
always_ff @(posedge adc_clk) begin
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    adc_buffer_in[channel] <= adc_data_d[$clog2(rx_pkg::CHANNELS)'($clog2(rx_pkg::CHANNELS+1)'(channel) % adc_active_channels)];
  end
end

// valid is converted to a write_enable based on the current banking mode and
// currently selected bank (through valid_mask)
logic [rx_pkg::CHANNELS-1:0] adc_valid_d; // register for timing
// adc_write_enable is an internal signal used for updating the write address
// adc_write_enable_d is the input to the sample RAM
logic [rx_pkg::CHANNELS-1:0] adc_write_enable, adc_write_enable_d;

// valid->write_enable path (combinatorial, since we need to update address in a combinatorial loop ??)
always_comb begin
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    adc_write_enable[channel] = adc_capture_active & adc_capture_valid_mask[channel]
                                      & adc_valid_d[$clog2(rx_pkg::CHANNELS)'($clog2(rx_pkg::CHANNELS+1)'(channel) % adc_active_channels)];
  end
end
// register write_enable and valid
always_ff @(posedge adc_clk) begin
  adc_valid_d <= adc_data.valid;
  adc_write_enable_d <= adc_write_enable;
end

//////////////////////////////
// Update write address
//////////////////////////////
always_comb begin
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    adc_bank_full[channel] = adc_write_addr[channel] == $clog2(BUFFER_DEPTH)'(BUFFER_DEPTH - 1) & adc_write_enable[channel];
  end
end
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_write_addr <= '0;
  end else begin
    if (adc_capture_reset | adc_readout_done_pls) begin
      adc_write_addr <= '0;
    end else begin
      for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
        if (adc_write_enable[channel]) begin
          adc_write_addr[channel] <= adc_write_addr[channel] + 1;
        end
      end
    end
  end
end
// update write depth output
always_ff @(posedge adc_clk) begin
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    adc_capture_write_depth[channel] <= {adc_bank_full_latch[channel], adc_write_addr[channel]};
  end
end

//////////////////////////////
// Full logic
//////////////////////////////
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_bank_full_latch <= '0;
  end else begin
    if (adc_capture_reset | adc_readout_done_pls) begin
      adc_bank_full_latch <= '0;
    end else begin
      for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
        if (adc_bank_full[channel]) begin
          adc_bank_full_latch[channel] <= adc_bank_full[channel];
        end
      end
    end
  end
end
assign adc_capture_full = |(adc_capture_full_mask & adc_bank_full_latch);

//////////////////////////////
// capture_active (SR flipflop)
// writes to buffer are only
// enabled when capture_active
// is high
//////////////////////////////
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_capture_active <= 1'b0;
  end else begin
    if (adc_capture_reset) begin
      adc_capture_active <= 1'b0;
    end else begin
      if (adc_capture_start_pls) begin
        adc_capture_active <= 1'b1;
      end else if (adc_capture_stop_pls | (|(adc_bank_full & adc_capture_full_mask))) begin
        adc_capture_active <= 1'b0;
      end
    end
  end
end

//////////////////////////////
// update capture_done_pls
//////////////////////////////
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_capture_done_pls <= 1'b0;
  end else begin
    if ((adc_capture_full & ~adc_capture_full_d) | adc_capture_stop_pls) begin
      adc_capture_done_pls <= 1'b1;
    end else begin
      adc_capture_done_pls <= 1'b0;
    end
  end
end

//////////////////////////////
// Capture state machine
// transition logic
//////////////////////////////
always_ff @(posedge adc_clk) begin
  if (adc_reset) begin
    adc_capture_state <= CAPTURE_IDLE;
  end else begin
    if (adc_capture_reset) begin
      adc_capture_state <= CAPTURE_IDLE;
    end else begin
      unique case (adc_capture_state)
        CAPTURE_IDLE: begin
          // if we get an arm signal, go to TRIGGER_WAIT
          if (adc_capture_arm) begin
            adc_capture_state <= TRIGGER_WAIT;
          end
        end
        TRIGGER_WAIT:
          // if we get a hw_start signal, go to SAVE_SAMPLES
          if (adc_capture_start_pls) begin
            adc_capture_state <= SAVE_SAMPLES;
          end
        SAVE_SAMPLES:
          // if we stop capture or buffer gets full, go to HOLD_SAMPLES
          if (adc_capture_stop_pls | adc_capture_full) adc_capture_state <= HOLD_SAMPLES;
        HOLD_SAMPLES:
          // once DMA completes, go to CAPTURE_IDLE
          if (adc_readout_done_pls) adc_capture_state <= CAPTURE_IDLE;
      endcase
    end
  end
end

////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////
// Readout clock domain
////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////

// readout state machine
enum {DMA_IDLE, DMA_READY, DMA_ACTIVE} ps_readout_state;

//////////////////////////
// Configuration/control
//////////////////////////

// software reset
// only allow reset during DMA transfer
assign ps_readout_sw_reset.ready = 1'b1;//ps_readout_state == DMA_ACTIVE;
logic ps_readout_reset;
assign ps_readout_reset = (ps_readout_sw_reset.data == 1) & ps_readout_sw_reset.valid & ps_readout_sw_reset.ready;

// readout start
// only allow DMA transfer to start when we actually have saved data
assign ps_readout_start.ready = ps_readout_state == DMA_READY;
logic ps_readout_start_pls; // pulse high for one cycle

//////////////////////////
// Internal logic
//////////////////////////
// all banks are read out simultaneously, multiple times
// the outputs of the banks are muxed based on bank_select
logic [ADDR_WIDTH-1:0] ps_read_addr;
logic [$clog2(rx_pkg::CHANNELS)-1:0] ps_bank_select;

// pipeline to allow registered output of bank memory
// bank_select needs to be delayed appropriately to match latency of data,valid,last
logic [rx_pkg::CHANNELS-1:0][READ_LATENCY-1:0][DATA_WIDTH-1:0] ps_readout_data_pipe;
logic [READ_LATENCY-1:0] ps_readout_valid_pipe, ps_readout_last_pipe;
logic [READ_LATENCY-1:0][$clog2(rx_pkg::CHANNELS)-1:0] ps_bank_select_pipe;

// high while data is valid
logic ps_readout_active;
// read enable for BRAM, also enable for pipeline registers and address update
logic ps_readout_enable;
// goes high when the final address is read
logic ps_readout_last;

// enable for read_address/bank_select update, also enable for data/valid/last/bank_sel pipelines
assign ps_readout_enable = ps_readout_active & (ps_readout_data.ready | ~ps_readout_data.valid);
assign ps_readout_last = (ps_read_addr == ADDR_WIDTH'(BUFFER_DEPTH - 1)) & (ps_bank_select == $clog2(rx_pkg::CHANNELS)'(rx_pkg::CHANNELS - 1));

// tell readout FSM and capture logic when we're done with readout
logic ps_readout_done_pls;
assign ps_readout_done_pls = ps_readout_data.valid & ps_readout_data.ready & ps_readout_data.last;

// CDC'd from capture clock domain
logic ps_capture_done_pls;

/////////////////////////////
// pipeline for valid/last
// and bank_select
/////////////////////////////
always_ff @(posedge ps_clk) begin
  if (ps_reset) begin
    {ps_readout_valid_pipe, ps_readout_last_pipe} <= '0;
    {ps_readout_data.valid, ps_readout_data.last} <= '0;
    ps_bank_select_pipe <= '0;
  end else begin
    if (ps_readout_reset) begin
      {ps_readout_valid_pipe, ps_readout_last_pipe} <= '0;
      {ps_readout_data.valid, ps_readout_data.last} <= '0;
      ps_bank_select_pipe <= '0;
    end else begin
      if (ps_readout_data.ready | ~ps_readout_data.valid) begin
        ps_readout_valid_pipe <= {ps_readout_valid_pipe[READ_LATENCY-2:0], ps_readout_active};
        ps_readout_last_pipe <= {ps_readout_last_pipe[READ_LATENCY-2:0], ps_readout_last};
        ps_readout_data.valid <= ps_readout_valid_pipe[READ_LATENCY-1];
        ps_readout_data.last <= ps_readout_last_pipe[READ_LATENCY-1];
        ps_bank_select_pipe <= {ps_bank_select_pipe[READ_LATENCY-2:0], ps_bank_select};
      end
    end
  end
end

/////////////////////////////
// update read address
// and bank select
/////////////////////////////
always_ff @(posedge ps_clk) begin
  if (ps_reset) begin
    ps_read_addr <= '0;
    ps_bank_select <= '0;
  end else begin
    if (ps_readout_reset | ps_readout_start_pls) begin
      ps_read_addr <= '0;
      ps_bank_select <= '0;
    end else begin
      if (ps_readout_enable) begin
        if (ps_read_addr == ADDR_WIDTH'(BUFFER_DEPTH - 1)) begin
          ps_read_addr <= 0;
          if (ps_bank_select == $clog2(rx_pkg::CHANNELS)'(rx_pkg::CHANNELS - 1)) begin
            ps_bank_select <= 0;
          end else begin
            ps_bank_select <= ps_bank_select + 1;
          end
        end else begin
          ps_read_addr <= ps_read_addr + 1;
        end
      end
    end
  end
end

/////////////////////////////
// readout_active and
// readout_start_pls
/////////////////////////////
always_ff @(posedge ps_clk) begin
  if (ps_reset) begin
    ps_readout_start_pls <= 1'b0;
    ps_readout_active <= 1'b0;
  end else begin
    // ps_readout_start_pls goes high one cycle before ps_readout_active, so
    // if we have multiple transactions attempted on ps_readout_start, we
    // should block readout_start_pls from going high again or staying high
    //   multiple transactions are possible, since ps_readout_start.ready doesn't go
    //   low for two cycles after readout_start.valid & readout_start.ready & (readout_start.data == 1)
    if (ps_readout_start.valid & ps_readout_start.ready & (ps_readout_start.data == 1) & ~ps_readout_active & ~ps_readout_start_pls) begin
      ps_readout_start_pls <= 1'b1;
    end else begin
      ps_readout_start_pls <= 1'b0;
    end
    if (ps_readout_reset) begin
      ps_readout_active <= 1'b0;
    end else begin
      if (ps_readout_start_pls) begin
        ps_readout_active <= 1'b1;
      end else if (ps_readout_last & ps_readout_data.valid & ps_readout_data.ready) begin
        ps_readout_active <= 1'b0;
      end
    end
  end
end

/////////////////////////////
// mux pipeline output
// to data interface
/////////////////////////////
always_ff @(posedge ps_clk) begin
  if (ps_readout_data.ready | ~ps_readout_data.valid) begin
    ps_readout_data.data <= ps_readout_data_pipe[ps_bank_select_pipe[READ_LATENCY-1]][READ_LATENCY-1];
  end
end

//////////////////////////////
// Readout state machine
// transition logic
//////////////////////////////
always_ff @(posedge ps_clk) begin
  if (ps_reset) begin
    ps_readout_state <= DMA_IDLE;
  end else begin
    if (ps_readout_reset) begin
      ps_readout_state <= DMA_READY;
    end else begin
      unique case (ps_readout_state)
        DMA_IDLE: if (ps_capture_done_pls) ps_readout_state <= DMA_READY;
        DMA_READY: if (ps_readout_start_pls) ps_readout_state <= DMA_ACTIVE;
        DMA_ACTIVE: if (ps_readout_done_pls) ps_readout_state <= DMA_IDLE;
      endcase
    end
  end
end

////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////
// Clock crossing and memory
////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////

/////////////////////////////////////
// CDC for readout done
// (readout clock -> capture clock)
/////////////////////////////////////
xpm_cdc_pulse #(
  .DEST_SYNC_FF(4), // 4 synchronization stages
  .INIT_SYNC_FF(0), // don't allow behavioral initialization
  .REG_OUTPUT(1), // register the output
  .RST_USED(1), // use resets
  .SIM_ASSERT_CHK(1) // report potential violations
) readout_done_cdc_i (
  .src_clk(ps_clk),
  .src_rst(ps_reset),
  .src_pulse(ps_readout_done_pls),
  .dest_clk(adc_clk),
  .dest_rst(adc_reset),
  .dest_pulse(adc_readout_done_pls)
);

/////////////////////////////////////
// CDC for capture done
// (capture clock -> readout clock)
/////////////////////////////////////
xpm_cdc_pulse #(
  .DEST_SYNC_FF(4), // 4 synchronization stages
  .INIT_SYNC_FF(0), // don't allow behavioral initialization
  .REG_OUTPUT(1), // register the output
  .RST_USED(1), // use resets
  .SIM_ASSERT_CHK(1) // report potential violations
) capture_done_cdc_i (
  .src_clk(adc_clk),
  .src_rst(adc_reset),
  .src_pulse(adc_capture_done_pls),
  .dest_clk(ps_clk),
  .dest_rst(ps_reset),
  .dest_pulse(ps_capture_done_pls)
);

/////////////////////////////
// write to memory
/////////////////////////////
always_ff @(posedge adc_clk) begin
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    if (adc_write_enable_d[channel]) begin
      memory[channel][adc_write_addr_d[channel]] <= adc_buffer_in[channel];
    end
  end
end

/////////////////////////////
// read from memory
/////////////////////////////
always_ff @(posedge ps_clk) begin
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    if (ps_readout_data.ready | ~ps_readout_data.valid) begin
      ps_readout_data_pipe[channel] <= {ps_readout_data_pipe[channel][READ_LATENCY-2:0], memory[channel][ps_read_addr]};
    end
  end
end

endmodule
