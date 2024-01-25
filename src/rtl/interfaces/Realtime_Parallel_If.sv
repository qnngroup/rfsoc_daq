// Realtime_Parallel_If.sv - Reed Foster
// multiple axi-stream interfaces without backpressure in parallel
`timescale 1ns/1ps
interface Realtime_Parallel_If #(
  parameter DWIDTH = 32,
  parameter CHANNELS = 1
);

logic [CHANNELS-1:0][DWIDTH - 1:0]  data;
logic [CHANNELS-1:0]                valid;

// master/slave packetized interface
modport Master (
  output  valid,
  output  data
);

modport Slave (
  input   valid,
  input   data
);

endinterface
