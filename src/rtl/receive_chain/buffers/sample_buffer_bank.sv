// sample_buffer_bank.sv - Reed Foster
// individual banks used in sample_buffer
// each bank has a buffer as well as a state machine for handling capture of
// samples into the buffer and readout of the buffer
// the buffer outputs two quantities before reading out the saved sequence of
// samples:
//  - which channel the contents belong to (implemented as 0 in this module,
//    but muxed in the sample_buffer)
//  - number of captured samples
module sample_buffer_bank #(
  parameter int BUFFER_DEPTH = 1024,
  parameter int PARALLEL_SAMPLES = 16, // 4.096 GS/s @ 256 MHz
  parameter int SAMPLE_WIDTH = 16 // 12-bit ADC
) (
  input wire clk, reset,
  Axis_If.Slave data_in, // one channel
  Axis_If.Master data_out,
  input logic start, stop,
  output logic full, first
);

enum {IDLE, CAPTURE, SEND_ID, SEND_NUM_SAMPLES, SEND_SAMPLES} state;
// IDLE: wait for start (either from user or from previous bank filling up in
// a high-memory, low-channel count banking mode)
// CAPTURE: save samples until full or until stop is supplied
// SEND_ID: output an empty sample (to be overwritten by
// sample_buffer with the channel index)
// SEND_NUM_SAMPLES: output number of captured samples
// SEND_SAMPLES: output samples

assign data_in.ready = state == CAPTURE;

logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] buffer [BUFFER_DEPTH];
logic [$clog2(BUFFER_DEPTH)-1:0] write_addr, read_addr;
logic [2:0][PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] data_out_reg;
logic [PARALLEL_SAMPLES*SAMPLE_WIDTH-1:0] data_out_muxed;
logic [3:0] data_out_valid; // extra valid to match latency of BRAM
logic [3:0] data_out_last;
logic buffer_has_data, readout_begun;
assign data_out.data = data_out_muxed;
assign data_out.valid = data_out_valid[3];
assign data_out.last = data_out_last[3];

// state machine
always_ff @(posedge clk) begin
  if (reset) begin
    state <= IDLE;
  end else begin
    unique case (state)
      IDLE: if (start) state <= CAPTURE;
      // transition out of capture mode either when a manual stop is received or the buffer fills
      CAPTURE: if (stop || (data_in.ok && (write_addr == BUFFER_DEPTH - 1))) state <= SEND_ID;
      // SEND_ID and SEND_NUM_SAMPLES are additional "wait" states used to send
      // out information about the contents captured in the buffer:
      //   - which channel the conents belong to
      //   - how many samples were saved
      SEND_ID: if (data_out.ok) state <= SEND_NUM_SAMPLES;
      // only transition after successfully sending out number of captured samples:
      SEND_NUM_SAMPLES: if (data_out.ok) begin
        if (data_out.last) begin
          // no data was saved, so there's nothing to send
          state <= IDLE;
        end else begin
          state <= SEND_SAMPLES;
        end
      end
      SEND_SAMPLES: if (data_out.last && data_out.ready && data_out.valid) state <= IDLE;
    endcase
  end
end

// sample buffer logic
always_ff @(posedge clk) begin
  if (reset) begin
    write_addr <= '0;
    read_addr <= '0;
    data_out_muxed <= '0;
    data_out_valid <= '0;
    data_out_last <= '0;
    buffer_has_data <= '0;
    readout_begun <= '0;
    full <= '0;
    first <= '0;
  end else begin
    unique case (state)
      IDLE: begin
        write_addr <= '0;
        read_addr <= '0;
        data_out_muxed <= '0;
        data_out_valid <= '0;
        data_out_last <= '0;
        buffer_has_data <= '0;
        readout_begun <= '0;
        full <= '0;
        first <= '0;
      end
      CAPTURE: begin
        if (data_in.valid) begin
          buffer[write_addr] <= data_in.data;
          write_addr <= write_addr + 1'b1;
          buffer_has_data <= 1'b1;
          if (write_addr == BUFFER_DEPTH - 1) begin
            full <= 1'b1;
          end
        end
      end
      SEND_ID: begin
        // output a separate signal to indicate when the first sample is being
        // sent out. This allows the sample_buffer to mux the output of the
        // sample_buffer_bank with the ID of the channel whose data is stored
        // in the bank
        first <= 1'b1;
        data_out_muxed <= '1;
        if (data_out.ok) begin
          data_out_valid[3] <= 1'b0;
        end else begin
          data_out_valid[3] <= 1'b1;
        end
      end
      SEND_NUM_SAMPLES: begin
        first <= '0;
        if (write_addr > 0) begin
          data_out_muxed <= write_addr;
        end else if (buffer_has_data) begin
          // if write_addr == 0 but we've written to the buffer, then it's full
          data_out_muxed <= BUFFER_DEPTH;
        end else begin
          data_out_muxed <= '0; // we don't have any data to send
          data_out_last[3] <= 1'b1;
        end
        if (data_out.ok) begin
          // transaction will go through, so we should reset data_out_valid so
          // that we don't accidentally send the sample count twice
          data_out_valid[3] <= 1'b0;
          // also reset last in case we don't have any data to send and the
          // sample count is the only thing we're outputting
          data_out_last[3] <= 1'b0;
        end else begin
          data_out_valid[3] <= 1'b1;
        end
      end
      SEND_SAMPLES: begin
        first <= '0;
        if (data_out.ok || (!data_out.valid)) begin
          data_out_reg[0] <= buffer[read_addr];
          data_out_reg[1] <= data_out_reg[0];
          data_out_reg[2] <= data_out_reg[1];
          data_out_muxed <= data_out_reg[2];
          // in case the entire buffer was filled, we would never read anything out if we don't add
          // the option to increment the address when readout hasn't been begun but the read/write
          // addresses are both zero
          // it is not possible to enter the SEND_SAMPLES state with an empty buffer, so we know if both are zero,
          // then the buffer must be full
          if ((read_addr != write_addr) || (!readout_begun)) begin
            readout_begun <= 1'b1;
            read_addr <= read_addr + 1'b1;
            data_out_valid <= {data_out_valid[2:0], 1'b1};
            if (read_addr + 1'b1 == write_addr) begin
              data_out_last <= {data_out_last[2:0], 1'b1};
            end
          end else begin
            // no more samples are read out
            data_out_valid <= {data_out_valid[2:0], 1'b0};
            data_out_last <= {data_out_last[2:0], 1'b0};
          end
        end
      end
    endcase
  end
end

endmodule
