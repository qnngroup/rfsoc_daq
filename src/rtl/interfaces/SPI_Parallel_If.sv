// SPI_Parallel_If.sv - Reed Foster
// interface for single master to drive multiple SPI slave devices

`timescale 1ns/1ps

interface SPI_Parallel_If #(
  parameter CHANNELS = 8
);

logic [CHANNELS-1:0] cs_n;
logic sck;
logic sdi;

modport Out (
  output cs_n,
  output sck,
  output sdi
);

endinterface
