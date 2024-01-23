`timescale 1ns/1ps
module xpm_cdc_pulse #(
  parameter integer DEST_SYNC_FF    = 4,
  parameter integer INIT_SYNC_FF    = 0,
  parameter integer REG_OUTPUT      = 0,
  parameter integer RST_USED        = 1,
  parameter integer SIM_ASSERT_CHK  = 0,
  parameter integer VERSION         = 0
) (
  input  wire       src_clk,
  input  wire       src_pulse,
  input  wire       dest_clk,
  input  wire       src_rst,
  input  wire       dest_rst,
  output wire       dest_pulse
);

endmodule

`timescale 1ns/1ps
module xpm_cdc_array_single # (
  parameter integer DEST_SYNC_FF    = 4,
  parameter integer INIT_SYNC_FF    = 0,
  parameter integer SIM_ASSERT_CHK  = 0,
  parameter integer SRC_INPUT_REG   = 1,
  parameter integer VERSION         = 0,
  parameter integer WIDTH           = 2
) (
  input  wire             src_clk,
  input  wire [WIDTH-1:0] src_in,
  input  wire             dest_clk,
  output wire [WIDTH-1:0] dest_out
);

endmodule

`timescale 1ns/1ps
module xpm_cdc_handshake #(
  // Module parameters
  parameter integer DEST_EXT_HSK    = 1,
  parameter integer DEST_SYNC_FF    = 4,
  parameter integer INIT_SYNC_FF    = 0,
  parameter integer SIM_ASSERT_CHK  = 0,
  parameter integer SRC_SYNC_FF     = 4,
  parameter integer VERSION         = 0,
  parameter integer WIDTH           = 1
) (
  // Module ports
  input  wire             src_clk,
  input  wire [WIDTH-1:0] src_in,
  input  wire             src_send,
  output wire             src_rcv,

  input  wire             dest_clk,
  output wire [WIDTH-1:0] dest_out,
  output wire             dest_req,
  input  wire             dest_ack
);

endmodule
