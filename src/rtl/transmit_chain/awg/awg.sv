// awg.sv - Reed Foster
// Arbitrary waveform generator
// Simple buffer that loads a waveform from DMA and then transmits the
// waveform when triggered from an axi-stream interface
// Also outputs a trigger signal which can be used by the receive signal chain
// to start a capture
//

// TODO reimplement dma_write_depth so that we don't get ragged DMA data
// for now, just be careful

`timescale 1ns/1ps
module awg #(
  parameter int DEPTH = 2048
) (
  // DMA/PS clock domain: 150 MHz
  input wire dma_clk, dma_reset,
  // Datapath
  Axis_If.Slave dma_data_in,

  // Configuration registers
  // dma_write_depth:
  //  For each channel, specify the desired frame depth for each channel.
  //  Also put the receive state machine into the DMA_ACCEPTING state.
  //  Need to put restrictions on this so that we always get a clean
  //  transition between subsequent channels when performing the DMA
  //  E.g. with tx_pkg::DATA_WIDTH = 2*tx_pkg::AXI_MM_WIDTH, DEPTH must be
  //  a multiple of 2
  //  1+$clog2(DEPTH)*tx_pkg::CHANNELS bits
  Axis_If.Slave dma_write_depth,
  // dma_trigger_out_config:
  //  For each channel, specify how the trigger signal is generated
  //    0: no trigger output
  //    1: trigger is outputted at the start of a burst
  //    2: trigger is outputted at the start of each frame in the burst
  //  2*tx_pkg::CHANNELS bits
  Axis_If.Slave dma_trigger_out_config,
  // dma_awg_burst_length:
  //  For each channel, specify the number of times the buffer memory should
  //  be read out (i.e. how many frames per burst)
  //  64*tx_pkg::CHANNELS bits
  Axis_If.Slave dma_awg_burst_length,
  // dma_awg_start_stop
  //  {start, stop}, commands the awg to start sending data or stop sending
  //  data
  //  synchronized to RFDAC clock domain
  Axis_If.Slave dma_awg_start_stop,
  // dma_transfer_error
  //  2 bit: MSB indicates early tlast from DMA, LSB indicates no tlast from DMA
  Axis_If.Master dma_transfer_error,

  // RFDAC clock domain: 384 MHz
  input wire dac_clk, dac_reset,
  // Datapath
  Realtime_Parallel_If.Master dac_data_out,

  // Trigger outputs (per channel)
  // All outputs will go to a separate trigger module which can be configured
  // to perform a logical operation on the triggers so that only a single
  // trigger signal needs to be passed to the receive chain
  // The trigger module will also synchronize the trigger signal from the
  // RFDAC clock domain to the RFADC clock domain and apply a variable delay
  output logic [tx_pkg::CHANNELS-1:0] dac_trigger
);

assign dma_transfer_error.last = 1'b1; // always send just a packet as a single word

////////////////////////////////////////////////////////////////////////
// DMA/PS clock domain logic
////////////////////////////////////////////////////////////////////////

// state machine:
// in DAC_IDLE, can accept configuration changes
// in DMA_ACCEPTING, can accept new waveform data
// in DMA_BLOCKING, cannot accept any changes
// in normal operation:
// state = DAC_IDLE:
//   1. configure triggers and burst length
//   2. send a word to dma_write_depth to initiate a DMA transfer
//   3. state <- DMA_ACCEPTING
// state = DMA_ACCEPTING:
//   1. send data over DMA
//   2. when DMA transfer is complete, state <- DMA_BLOCKING
// state = DMA_BLOCKING:
//   1. wait for DAC to stop, then return to state <- DAC_IDLE
enum {DMA_IDLE, DMA_ACCEPTING, DMA_BLOCKING} dma_write_state;

Axis_If #(.DWIDTH(tx_pkg::DATA_WIDTH)) dma_write_data ();
logic dma_write_enable;
logic [$clog2(DEPTH)-1:0] dma_write_address;
logic [$clog2(tx_pkg::CHANNELS)-1:0] dma_write_channel;
logic [tx_pkg::DATA_WIDTH-1:0] dma_write_data_reg;
logic [tx_pkg::CHANNELS-1:0] dma_write_done;

// configs from register map
logic [tx_pkg::CHANNELS-1:0][$clog2(DEPTH)-1:0] dma_address_max_reg;
logic [tx_pkg::CHANNELS-1:0][1:0] dma_trigger_out_config_reg;
logic [tx_pkg::CHANNELS-1:0][63:0] dma_awg_burst_length_reg;
logic dma_awg_start, dma_awg_stop;

// signal synchronized from RFDAC domain indicating burst read of buffers is complete
logic dma_awg_done;

// assign ready/valid signals to register map interfaces
assign dma_write_depth.ready = dma_write_state == DMA_IDLE;
assign dma_trigger_out_config.ready = dma_write_state == DMA_IDLE;
assign dma_awg_burst_length.ready = dma_write_state == DMA_IDLE;
assign dma_write_data.ready = dma_write_state == DMA_ACCEPTING;
// allow starting bursts as long as the buffer isn't being written to:
assign dma_awg_start_stop.ready = dma_write_state != DMA_ACCEPTING;

logic dma_awg_config_done, dma_awg_config_done_pulse; // asserted when dma_write_state enters DMA_ACCEPTING
always_ff @(posedge dma_clk) begin
  if (dma_reset) begin
    dma_awg_config_done <= 1'b0;
    dma_awg_config_done_pulse <= 1'b0;
  end else begin
    if (dma_write_state == DMA_ACCEPTING) begin
      if (dma_awg_config_done_pulse) begin
        dma_awg_config_done_pulse <= 1'b0;
      end
      if (~dma_awg_config_done) begin
        dma_awg_config_done <= 1'b1;
        dma_awg_config_done_pulse <= 1'b1;
      end
    end else if (dma_write_state == DMA_IDLE) begin
      dma_awg_config_done <= 1'b0;
    end
  end
end

// state machine update
always_ff @(posedge dma_clk) begin
  if (dma_reset) begin
    dma_write_state <= DMA_IDLE;
  end else begin
    unique case (dma_write_state)
      DMA_IDLE: if (dma_write_depth.valid & dma_write_depth.ready) dma_write_state <= DMA_ACCEPTING;
      DMA_ACCEPTING: begin
        if ((dma_write_data.valid & dma_write_data.ready & dma_write_data.last) // normal operation
            || (dma_write_enable // didn't get tlast, but finished writing to buffer
                & (dma_write_channel == $clog2(tx_pkg::CHANNELS)'(tx_pkg::CHANNELS - 1))
                & (dma_write_address == dma_address_max_reg[dma_write_channel]))) begin
          dma_write_state <= DMA_BLOCKING;
        end
      end
      DMA_BLOCKING: if (dma_awg_stop || dma_awg_done) dma_write_state <= DMA_IDLE;
    endcase
  end
end

// update configurations from register map
always_ff @(posedge dma_clk) begin
  if (dma_reset) begin
    dma_address_max_reg <= '0;
    dma_trigger_out_config_reg <= '0;
    dma_awg_burst_length_reg <= '0;
    {dma_awg_start, dma_awg_stop} <= '0;
  end else begin
    if (dma_write_depth.valid & dma_write_depth.ready) begin
      for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
        dma_address_max_reg[channel] <= dma_write_depth.data[channel*$clog2(DEPTH)+:$clog2(DEPTH)];
      end
    end
    if (dma_trigger_out_config.valid & dma_trigger_out_config.ready) begin
      dma_trigger_out_config_reg <= dma_trigger_out_config.data;
    end
    if (dma_awg_burst_length.valid & dma_awg_burst_length.ready) begin
      for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
        dma_awg_burst_length_reg[channel] <= dma_awg_burst_length.data[channel*64+:64] - 1;
      end
    end
    if (dma_awg_start_stop.valid & dma_awg_start_stop.ready) begin
      {dma_awg_start, dma_awg_stop} <= dma_awg_start_stop.data;
    end else begin
      {dma_awg_start, dma_awg_stop} <= '0; // reset to 0 so it's just a pulse
    end
  end
end

// update write pointer and channel select
always_ff @(posedge dma_clk) begin
  dma_write_data_reg <= dma_write_data.data;
  if (dma_reset) begin
    dma_write_channel <= '0;
    dma_write_address <= '0;
    dma_write_enable <= 1'b0;
    dma_write_done <= '0;
  end else begin
    dma_write_enable <= dma_write_data.valid & dma_write_data.ready;
    if (dma_write_state == DMA_IDLE) begin
      dma_write_address <= '0;
      dma_write_channel <= '0;
      dma_write_done <= '0;
    end else begin
      if (dma_write_enable) begin
        if (dma_write_address == dma_address_max_reg[dma_write_channel]) begin
          dma_write_address <= '0;
          dma_write_done[dma_write_channel] <= 1'b1;
          if (dma_write_channel == $clog2(tx_pkg::CHANNELS)'(tx_pkg::CHANNELS - 1)) begin
            dma_write_channel <= '0;
          end else begin
            dma_write_channel <= dma_write_channel + 1'b1;
          end
        end else begin
          dma_write_address <= dma_write_address + 1'b1;
        end
      end
    end
  end
end

// check for tlast error
logic dma_tlast_reg;
always_ff @(posedge dma_clk) begin
  dma_tlast_reg <= dma_write_data.last;
  if (dma_reset) begin
    dma_transfer_error.data <= '0;
    dma_transfer_error.valid <= 1'b0;
  end else begin
    if (dma_transfer_error.valid & dma_transfer_error.ready) begin
      dma_transfer_error.valid <= 1'b0; // reset each time we read it
    end
    if (dma_write_depth.valid & dma_write_depth.ready) begin
      // reset the status each time we start a new DMA
      dma_transfer_error.data <= '0;
      dma_transfer_error.valid <= 1'b0;
    end else begin
      if (dma_write_enable) begin
        if ((dma_write_channel == $clog2(tx_pkg::CHANNELS)'(tx_pkg::CHANNELS - 1)) & (dma_write_address == dma_address_max_reg[dma_write_channel])) begin
          if (~dma_tlast_reg) begin
            // we were expecting tlast, but didn't get it
            dma_transfer_error.data[0] <= 1'b1;
            dma_transfer_error.valid <= 1'b1;
          end else begin
            // no error
            dma_transfer_error.data <= '0;
            dma_transfer_error.valid <= 1'b1;
          end
        end else begin
          if (dma_tlast_reg) begin
            // we weren't expecting tlast, but got one anyway
            dma_transfer_error.data[1] <= 1'b1;
            dma_transfer_error.valid <= 1'b1;
          end
        end
      end
    end
  end
end

// axis_width_converter to step tx_pkg::AXI_MM_WIDTH to BURST_WIDTH
axis_width_converter #(
  .DWIDTH_IN(tx_pkg::AXI_MM_WIDTH),
  .DWIDTH_OUT(tx_pkg::DATA_WIDTH)
) dma_width_conv_i (
  .clk(dma_clk),
  .reset(dma_reset),
  .data_in(dma_data_in),
  .data_out(dma_write_data)
);

////////////////////////////////////////////////////////////////////////
// RFDAC clock domain
////////////////////////////////////////////////////////////////////////

// state machine
enum {DAC_IDLE, DAC_ACTIVE} dac_read_state;

// output signals
logic [2:0] dac_data_out_valid;
logic [1:0][tx_pkg::CHANNELS-1:0][tx_pkg::DATA_WIDTH-1:0] dac_buffer_out_reg;
logic [tx_pkg::CHANNELS-1:0][tx_pkg::DATA_WIDTH-1:0] dac_data_out_reg;
logic [tx_pkg::CHANNELS-1:0][$clog2(DEPTH)-1:0] dac_read_address;
logic [tx_pkg::CHANNELS-1:0][63:0] dac_frame_counter;
logic [2:0][tx_pkg::CHANNELS-1:0] dac_trigger_pipe; // match latency of BRAM output registers

// tracking of when each channel finishes
logic [1:0][tx_pkg::CHANNELS-1:0] dac_awg_channels_done;
logic dac_awg_done;
logic [1:0][tx_pkg::CHANNELS-1:0] dac_data_select; // switch between BRAM output and zero
always_ff @(posedge dac_clk) dac_awg_done <= &dac_awg_channels_done[1];

logic dac_awg_config_done; // synchronized from DMA/PS domain, used as write enable for CDC'd configurations for DAC readout of buffer

logic dac_started; // goes high on first transition from DAC_IDLE to DAC_ACTIVE

always_ff @(posedge dac_clk) begin
  if (dac_reset) begin
    dac_data_out_valid <= '0;
    dac_data_out.valid <= '0;
  end else begin
    dac_data_out.valid <= {tx_pkg::CHANNELS{dac_data_out_valid[2]}};
    dac_data_out_valid <= {dac_data_out_valid[1:0], dac_started};
  end
end

always_ff @(posedge dac_clk) begin
  dac_data_out.data <= dac_data_out_reg;
  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    if (dac_data_select[1][channel]) begin
      dac_data_out_reg[channel] <= '0;
    end else begin
      dac_data_out_reg[channel] <= dac_buffer_out_reg[1][channel];
    end
  end
end

// update which data source is selected (tie to zero or BRAM output)
always_ff @(posedge dac_clk) begin
  if (dac_reset) begin
    dac_data_select <= '0;
  end else begin
    dac_data_select[1] <= dac_data_select[0];
    for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
      if (dac_awg_channels_done[0][channel] || (dac_read_state == DAC_IDLE)) begin
        dac_data_select[0][channel] <= 1'b1;
      end else begin
        dac_data_select[0][channel] <= 1'b0;
      end
    end
  end
end

// syncrhonized start/stop from DMA/PS domain
logic dac_awg_start, dac_awg_stop;
// synchronized address_max_reg from DMA/PS domain
logic [tx_pkg::CHANNELS-1:0][$clog2(DEPTH)-1:0] dac_address_max_sync, dac_address_max_reg;
logic [tx_pkg::CHANNELS-1:0][63:0] dac_awg_burst_length_sync, dac_awg_burst_length_reg;
// synchronized trigger config from DMA/PS domain
logic [tx_pkg::CHANNELS-1:0][1:0] dac_trigger_out_config_sync, dac_trigger_out_config_reg;

// update state machine
always_ff @(posedge dac_clk) begin
  if (dac_reset) begin
    dac_read_state <= DAC_IDLE;
  end else begin
    unique case (dac_read_state)
      DAC_IDLE: if (dac_awg_start) dac_read_state <= DAC_ACTIVE;
      DAC_ACTIVE: if (dac_awg_stop || dac_awg_done) dac_read_state <= DAC_IDLE;
    endcase
  end
end

always_ff @(posedge dac_clk) begin
  if (dac_reset) begin
    dac_started <= 1'b0;
  end else begin
    if (dac_awg_start) begin
      dac_started <= 1'b1;
    end
  end
end

// update dac_read_address, dac_awg_channels_done, and dac_trigger
always_ff @(posedge dac_clk) begin
  dac_trigger <= dac_trigger_pipe[2];
  dac_trigger_pipe[2:1] <= dac_trigger_pipe[1:0];
  if (dac_reset) begin
    dac_frame_counter <= '0;
    dac_read_address <= '0;
    dac_awg_channels_done <= '0;
    dac_trigger_pipe <= '0;
  end else begin
    unique case (dac_read_state)
      DAC_IDLE: begin
        dac_frame_counter <= '0;
        dac_read_address <= '0;
        dac_awg_channels_done <= '0;
        dac_trigger_pipe[0] <= '0;
      end
      DAC_ACTIVE: begin
        for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
          // update dac_read_address and dac_awg_channels_done
          if (dac_read_address[channel] == dac_address_max_reg[channel]) begin
            dac_read_address[channel] <= '0;
            // check to see how many bursts we have left
            if (dac_frame_counter[channel] == dac_awg_burst_length_reg[channel]) begin
              dac_frame_counter[channel] <= '0;
            end else begin
              dac_frame_counter[channel] <= dac_frame_counter[channel] + 1'b1;
            end
          end else begin
            dac_read_address[channel] <= dac_read_address[channel] + 1'b1;
          end
          dac_awg_channels_done[1][channel] <= dac_awg_channels_done[0][channel];
          if ((dac_read_address[channel] == dac_address_max_reg[channel])
              & (dac_frame_counter[channel] == dac_awg_burst_length_reg[channel])) begin
            dac_awg_channels_done[0][channel] <= 1'b1;
          end
          // generate dac_trigger
          dac_trigger_pipe[0][channel] <= 1'b0;
          if (~dac_awg_channels_done[0][channel]) begin
            if (dac_read_address[channel] == 0) begin
              if (dac_trigger_out_config_reg[channel] == 2) begin
                // output every frame
                dac_trigger_pipe[0][channel] <= 1'b1;
              end
              if (dac_frame_counter[channel] == 0) begin
                if (dac_trigger_out_config_reg[channel] == 1) begin
                  // only output on first frame
                  dac_trigger_pipe[0][channel] <= 1'b1;
                end
              end
            end
          end
        end
      end
    endcase
  end
end

////////////////////////////////////////////////////////////////////////
// Synchronization / domain-crossing logic
////////////////////////////////////////////////////////////////////////
// synchronize start/stop to RFDAC clock domain
xpm_cdc_pulse #(
  .DEST_SYNC_FF(4), // 4 synchronization stages
  .INIT_SYNC_FF(0), // don't allow behavioral initialization
  .REG_OUTPUT(1), // register the output
  .RST_USED(1), // use resets
  .SIM_ASSERT_CHK(1) // report potential violations
) start_cdc_i (
  .src_clk(dma_clk),
  .src_rst(dma_reset),
  .src_pulse(dma_awg_start),
  .dest_clk(dac_clk),
  .dest_rst(dac_reset),
  .dest_pulse(dac_awg_start)
);
xpm_cdc_pulse #(
  .DEST_SYNC_FF(4), // 4 synchronization stages
  .INIT_SYNC_FF(0), // don't allow behavioral initialization
  .REG_OUTPUT(1), // register the output
  .RST_USED(1), // use resets
  .SIM_ASSERT_CHK(1) // report potential violations
) stop_cdc_i (
  .src_clk(dma_clk),
  .src_rst(dma_reset),
  .src_pulse(dma_awg_stop),
  .dest_clk(dac_clk),
  .dest_rst(dac_reset),
  .dest_pulse(dac_awg_stop)
);
// synchronize awg_done to DMA/PS clock domain
xpm_cdc_pulse #(
  .DEST_SYNC_FF(4), // 4 synchronization stages
  .INIT_SYNC_FF(0), // don't allow behavioral initialization
  .REG_OUTPUT(1), // register the output
  .RST_USED(1), // use resets
  .SIM_ASSERT_CHK(1) // report potential violations
) awg_done_cdc_i (
  .src_clk(dac_clk),
  .src_rst(dac_reset),
  .src_pulse(dac_awg_done),
  .dest_clk(dma_clk),
  .dest_rst(dma_reset),
  .dest_pulse(dma_awg_done)
);

// dma_address_max_reg does not change when the DAC-side is reading out the
// buffers, so any metastability will not be an issue.
// same is true of dma_awg_burst_length_reg and dma_trigger_out_config_reg
// regardless, we should do a proper CDC so that the tools don't complain
// probably could do a set_false_path, but just use a CDC
// xpm_cdc_array_single is designed for separate (i.e. independent) bits that
// are packed into an array for convenience. Since our signal isn't changing
// anytime near where we want to read it, it's fine to use this module
xpm_cdc_array_single #(
  .DEST_SYNC_FF(4), // four synchronization stages
  .INIT_SYNC_FF(0), // disable behavioral initialization in simulation
  .SIM_ASSERT_CHK(1), // report violations when simulating
  .SRC_INPUT_REG(1), // register input
  .WIDTH(tx_pkg::CHANNELS*$clog2(DEPTH))
) dma_to_dac_address_max_cdc_i (
  .src_clk(dma_clk),
  .src_in(dma_address_max_reg),
  .dest_clk(dac_clk),
  .dest_out(dac_address_max_sync)
);
xpm_cdc_array_single #(
  .DEST_SYNC_FF(4), // four synchronization stages
  .INIT_SYNC_FF(0), // disable behavioral initialization in simulation
  .SIM_ASSERT_CHK(1), // report violations when simulating
  .SRC_INPUT_REG(1), // register input
  .WIDTH(tx_pkg::CHANNELS*64)
) dma_to_dac_burst_length_cdc_i (
  .src_clk(dma_clk),
  .src_in(dma_awg_burst_length_reg),
  .dest_clk(dac_clk),
  .dest_out(dac_awg_burst_length_sync)
);
xpm_cdc_array_single #(
  .DEST_SYNC_FF(4), // four synchronization stages
  .INIT_SYNC_FF(0), // disable behavioral initialization in simulation
  .SIM_ASSERT_CHK(1), // report violations when simulating
  .SRC_INPUT_REG(1), // register input
  .WIDTH(tx_pkg::CHANNELS*2)
) dma_to_dac_trigger_config_cdc_i (
  .src_clk(dma_clk),
  .src_in(dma_trigger_out_config_reg),
  .dest_clk(dac_clk),
  .dest_out(dac_trigger_out_config_sync)
);
// register with an enable signal to make sure we're always comparing valid data
always_ff @(posedge dac_clk) begin
  if (dac_awg_config_done) begin
    dac_trigger_out_config_reg <= dac_trigger_out_config_sync;
    dac_awg_burst_length_reg <= dac_awg_burst_length_sync;
    dac_address_max_reg <= dac_address_max_sync;
  end
end

// synchronize AWG configuration done signal 
xpm_cdc_pulse #(
  .DEST_SYNC_FF(10), // 10 synchronization stages (extra delay)
  .INIT_SYNC_FF(0), // don't allow behavioral initialization
  .REG_OUTPUT(1), // register the output
  .RST_USED(1), // use resets
  .SIM_ASSERT_CHK(1) // report potential violations
) awg_config_done_cdc_i (
  .src_clk(dma_clk),
  .src_rst(dma_reset),
  .src_pulse(dma_awg_config_done_pulse),
  .dest_clk(dac_clk),
  .dest_rst(dac_reset),
  .dest_pulse(dac_awg_config_done)
);

// buffers
genvar channel;
generate
  for (channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    logic [tx_pkg::DATA_WIDTH-1:0] buffer [DEPTH];
    
    // Write to the currently selected buffer as long as we haven't completed
    // the write.
    // This is necessary in case the DMA TLAST signal doesn't arrive, which
    // could happen if the user doesn't properly configure the frame lengths
    always_ff @(posedge dma_clk) begin
      if ((channel == dma_write_channel) & dma_write_enable & (~dma_write_done[channel])) begin
        buffer[dma_write_address] <= dma_write_data_reg;
      end
    end
    
    // read all buffers simultaneously
    always_ff @(posedge dac_clk) begin
      dac_buffer_out_reg[0][channel] <= buffer[dac_read_address[channel]];
      dac_buffer_out_reg[1][channel] <= dac_buffer_out_reg[0][channel];
    end
  end
endgenerate

endmodule
