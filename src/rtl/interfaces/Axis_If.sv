// Axis_If.sv - Reed Foster
// single axi-stream interface
interface Axis_If #(
  parameter DWIDTH = 32
);

logic [DWIDTH - 1:0]  data;
logic                 ready;
logic                 valid;
logic                 last;
logic                 ok;

assign ok = ready & valid;

// master/slave packetized interface
modport Master (
  input   ready,
  output  valid,
  output  data,
  output  last,
  input   ok
);

modport Slave (
  output  ready,
  input   valid,
  input   data,
  input   last,
  input   ok
);

endinterface
