// Realtime_Parallel_If.sv - Reed Foster
// multiple axi-stream interfaces without backpressure in parallel
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

/* verilator lint_off MULTIDRIVEN */

// Similar to Axis_Parallel_If interface send_samples method.
// Doesn't use ready signal
task automatic send_samples(
  ref clk,
  input int n_samples,
  input bit rand_arrivals,
  input bit reset_valid
);
  int samples_sent [CHANNELS]; // track number of samples sent for each channel
  logic [CHANNELS-1:0] done; // 1 bit for each parallel channel to track if it's sent n_samples yet
  // reset
  done = '0;
  for (int i = 0; i < CHANNELS; i++) begin
    samples_sent[i] = 0;
  end
  valid <= '1; // enable all channels
  while (~done !== '0) begin
    @(posedge clk);
    for (int i = 0; i < CHANNELS; i++) begin
      if (valid[i]) begin
        if (samples_sent[i] == n_samples - 1) begin
          done[i] = 1'b1;
        end else begin
          samples_sent[i] = samples_sent[i] + 1;
        end
      end
    end
    if (rand_arrivals) begin
      valid <= CHANNELS'($urandom_range((1 << CHANNELS) - 1)) & (~done);
    end
  end
  if (reset_valid) begin
    valid <= '0;
    @(posedge clk);
  end
endtask

/* verilator lint_off MULTIDRIVEN */

endinterface
