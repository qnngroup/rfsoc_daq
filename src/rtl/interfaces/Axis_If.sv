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
modport Master_Full (
  input   ready,
  output  valid,
  output  data,
  output  last,
  input   ok
);

modport Slave_Full (
  output  ready,
  input   valid,
  input   data,
  input   last,
  input   ok
);

// master/slave stream with backpressure
modport Master_Stream (
  input   ready,
  output  valid,
  output  data,
  input   ok
);

modport Slave_Stream (
  output  ready,
  input   valid,
  input   data,
  input   ok
);

// master/slave stream with no backpressure
modport Master_Realtime (
  output  valid,
  output  data
);

modport Slave_Realtime (
  input   valid,
  input   data
);

////////////////////////////////
// Utitlities for testbenches //
////////////////////////////////

// Combined with a process that updates data_in whenever
// ok = valid && ready is high, this task sends samples to
// an Axis_If interface.
// Can optionally toggle the valid signal randomly to test
// handshaking logic of modules
task automatic send_samples(
  ref clk, // reference to clock signal in testbench
  input int n_samples, // number of samples to send
  input bit rand_arrivals, // if 1, toggle valid, otherwise leave it high
  input bit reset_valid, // if 1, reset valid signal after sending the samples
  input bit ignore_ready // if 1, ignore ready signal (useful for realtime interfaces which don't assign ready)
);
  int samples_sent;
  // reset
  samples_sent = 0;
  valid <= 1'b1;
  while (samples_sent < n_samples) begin
    @(posedge clk);
    if (ok | (valid & ignore_ready)) begin
      samples_sent = samples_sent + 1'b1;
    end
    if (rand_arrivals) begin
      valid <= $urandom() & 1'b1;
    end // else do nothing; intf.valid is already 1'b1
  end
  if (reset_valid) begin
    valid <= '0;
    @(posedge clk);
  end
endtask

// Wait until the last transfer goes through on an Axis_If interface,
// or until a timeout is reached. Can optionally toggle the ready signal
// to test backpressure handling logic of modules
task automatic do_readout(
  ref clk, // reference to clock signal in testbench
  input bit rand_ready, // if 1, toggle ready, otherwise leave it high
  input int timeout // number of clock cycles to wait for if last is never asserted
);
  int cycle_count;
  cycle_count = 0;
  ready <= 1'b0;
  // wait a bit before actually doing the readout
  repeat (500) @(posedge clk);
  ready <= 1'b1;
  // give up after timeout clock cycles if last is not achieved
  while ((!(last & ok)) & (cycle_count < timeout)) begin
    @(posedge clk);
    cycle_count = cycle_count + 1;
    if (rand_ready) begin
      ready <= $urandom() & 1'b1;
    end
  end
  @(posedge clk);
  ready <= 1'b0;
endtask

endinterface
