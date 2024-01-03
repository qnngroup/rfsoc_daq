// Axis_Parallel_If.sv - Reed Foster
// multiple axi-stream interfaces in parallel
interface Axis_Parallel_If #(
  parameter DWIDTH = 32,
  parameter CHANNELS = 1
);

logic [CHANNELS-1:0][DWIDTH - 1:0]  data;
logic [CHANNELS-1:0]                ready;
logic [CHANNELS-1:0]                valid;
logic [CHANNELS-1:0]                last;
logic [CHANNELS-1:0]                ok;

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

// Similar to Axis_If interface send_samples method.
// Sends n_samples on each parallel channel
// Waits until all channels complete sending samples
task automatic send_samples(
  ref clk,
  input int n_samples,
  input bit rand_arrivals,
  input bit reset_valid,
  input bit ignore_ready
);
  int samples_sent [CHANNELS]; // track number of samples sent for each channel
  logic [CHANNELS-1:0] done; // 1 bit for each parallel channel to track if it's sent n_samples yet
  // reset
  done = '0;
  for (int i = 0; i < CHANNELS; i++) begin
    samples_sent[i] = 0;
  end
  valid <= '1; // enable all channels
  while (~done) begin
    @(posedge clk);
    for (int i = 0; i < CHANNELS; i++) begin
      if (ok[i] | (valid[i] & ignore_ready)) begin
        if (samples_sent[i] == n_samples - 1) begin
          done[i] = 1'b1;
        end else begin
          samples_sent[i] = samples_sent[i] + 1;
        end
      end
    end
    if (rand_arrivals) begin
      valid <= $urandom_range((1 << CHANNELS) - 1) & (~done);
    end
  end
  if (reset_valid) begin
    valid <= '0;
    @(posedge clk);
  end
endtask

endinterface


