// axis_config_reg_cdc.sv - Reed Foster
// Clock domain crossing for module configuration registers that use
// AXI-stream

`timescale 1ns/1ps
module axis_config_reg_cdc #(
  parameter int DWIDTH = 16
) (
  input wire src_clk, src_reset,
  Axis_If.Slave src,

  input wire dest_clk, dest_reset,
  Axis_If.Master dest
);

///////////////////////////////////////////////////
// Source clock domain backpressure handling
///////////////////////////////////////////////////
logic src_send, src_rcv, src_empty;
logic [DWIDTH:0] src_packet; // extra bit for last flag
// only allow new data if we aren't currently transferring data
assign src.ready = ~(src_send | src_rcv) | src_empty;

always_ff @(posedge src_clk) begin
  src_packet <= {src.last, src.data};
  if (src_reset) begin
    src_empty <= 1'b1;
    src_send <= 1'b0;
  end else begin
    if (src.ok & ~src_rcv) begin
      src_empty <= 1'b0;
      src_send <= 1'b1;
    end else if (src_send & src_rcv) begin
      src_send <= 1'b0;
    end
  end
end

///////////////////////////////////////////////////
// Destination clock domain backpressure handling
///////////////////////////////////////////////////
logic dest_req, dest_ack;
logic [DWIDTH:0] dest_packet; // extra bit for last flag
logic transfer_done;

always_ff @(posedge dest_clk) begin
  {dest.last, dest.data} <= dest_packet;
  if (dest_reset) begin
    dest_ack <= 1'b0;
    transfer_done <= 1'b0;
    dest.valid <= 1'b0;
  end else begin
    // once dest_out has data, dest_req is asserted
    // wait until ready goes high before sending ack
    if (dest.ok) begin
      dest.valid <= 1'b0; // reset valid after transfer occurs
      dest_ack <= 1'b1;
      transfer_done <= 1'b1;
    end else if (~transfer_done) begin
      dest.valid <= dest_req;
    end else if (dest_ack & (~dest_req)) begin
      // transaction is done when ack is still high
      // but sync module deasserts req
      // reset ack, also reset transfer_done
      dest_ack <= 1'b0;
      transfer_done <= 1'b0;
    end
  end
end

///////////////////////////////////////////////////
// Synchronizer
///////////////////////////////////////////////////
xpm_cdc_handshake #(
  .DEST_EXT_HSK(1), // use external handshake
  .DEST_SYNC_FF(4), // four FF synchronizer for src->dest
  .INIT_SYNC_FF(0), // disable behavioral initialization of sync FFs
  .SIM_ASSERT_CHK(1), // enable simulation message reporting for misuse
  .SRC_SYNC_FF(4), // four FF synchronizer for dest->src
  .WIDTH(1+DWIDTH)
) cdc_handshake_i (
  .dest_clk,
  .dest_out(dest_packet),
  .dest_req, // out
  .dest_ack, // in
  .src_clk,
  .src_in(src_packet),
  .src_rcv, // out
  .src_send // in
);

endmodule
