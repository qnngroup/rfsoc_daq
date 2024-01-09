// axis_config_reg_cdc.sv - Reed Foster
// Clock domain crossing for module configuration registers that use
// AXI-stream

module axis_config_reg_cdc #(
  parameter int DWIDTH = 16
) (
  input wire src_clk, src_reset,
  Axis_If.Slave_Stream src,

  input wire dest_clk, dest_reset,
  Axis_If.Master_Stream dest
);

///////////////////////////////////////////////////
// Source clock domain backpressure handling
///////////////////////////////////////////////////
logic src_send, src_rcv;
logic [DWIDTH-1:0] src_data;
// only allow new data if we aren't currently transferring data
assign src.ready = ~(src_send | src_rcv);

always_ff @(posedge src_clk) begin
  src_data <= src.data;
  if (src_reset) begin
    src_send <= 1'b0;
  end else begin
    if (src.ok & ~src_rcv) begin
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
logic [DWIDTH-1:0] dest_data;
logic transfer_done;

always_ff @(posedge dest_clk) begin
  dest.data <= dest_data;
  if (dest_reset) begin
    dest_ack <= 1'b0;
    transfer_done <= 1'b0;
    dest.valid <= 1'b0;
  end else begin
    // once dest_out has data, dest_req is asserted
    // wait until ready goes high before sending ack
    if (dest_req & dest.ready) begin
      dest_ack <= 1'b1;
      if (transfer_done) begin
        // transfer occurred already, so deassert valid
        dest.valid <= 1'b0;
      end else begin
        dest.valid <= 1'b1;
        transfer_done <= 1'b1;
      end
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
  .WIDTH(DWIDTH)
) cdc_handshake_i (
  .dest_clk,
  .dest_out(dest_data),
  .dest_req, // out
  .dest_ack, // in
  .src_clk,
  .src_in(src_data),
  .src_rcv, // out
  .src_send // in
);

endmodule
