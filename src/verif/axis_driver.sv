// axis_driver.sv - Reed Foster
// Test utility for Axis_If.Master interfaces
// Tasks for sending a sequence of samples (no timeout)
// Or sending a single sample with a timeout

`timescale 1ns/1ps
module axis_driver #(
  parameter DWIDTH = 32
) (
  input logic clk,
  Axis_If.Master intf
);

localparam int WORD_WIDTH = 32;
localparam int NUM_WORDS = (DWIDTH + WORD_WIDTH - 1)/WORD_WIDTH;

logic [DWIDTH-1:0] data_q [$];
int last_q [$];

always @(posedge clk) begin
  if (intf.valid & intf.ready) begin
    data_q.push_front(intf.data);
    if (intf.last) begin
      last_q.push_front(data_q.size());
    end
  end
end

task automatic init ();
  intf.last <= 1'b0;
  intf.data <= '0;
  intf.valid <= 1'b0;
endtask

task automatic set_valid (
  input bit valid
);
  intf.valid <= valid;
endtask

task automatic clear_queues ();
  while (data_q.size() > 0) data_q.pop_back();
  while (last_q.size() > 0) last_q.pop_back();
endtask

task automatic send_samples(
  input int n_samples, // number of samples to send
  input bit rand_arrivals, // if 1, toggle valid, otherwise leave it high
  input bit reset_valid // if 1, reset valid signal after sending the samples
);
  logic [DWIDTH-1:0] samples [$];
  logic [NUM_WORDS*WORD_WIDTH-1:0] temp_data;
  for (int i = 0; i < n_samples; i++) begin
      for (int word = 0; word < NUM_WORDS; word++) begin
        temp_data[word*WORD_WIDTH+:WORD_WIDTH] = $urandom();
      end
    samples.push_front(temp_data[DWIDTH-1:0]);
  end
  send_queue(samples, n_samples, rand_arrivals, reset_valid, 1'b0);
endtask

task automatic send_queue(
  inout logic [DWIDTH-1:0] samples [$],
  input int n_samples, // number of samples to send
  input bit rand_arrivals, // if 1, toggle valid, otherwise leave it high
  input bit reset_valid, // if 1, reset valid signal after sending the samples
  input bit last // if 1, send last else don't
);
  int samples_sent;
  // reset
  samples_sent = 0;
  while (samples_sent < n_samples) begin
    intf.data <= samples.pop_back();
    if (last && samples_sent == n_samples - 1) begin
      intf.last <= 1'b1;
    end
    do begin
      intf.valid <= $urandom() | (~rand_arrivals);
      @(posedge clk);
    end while (~(intf.valid & intf.ready));
    samples_sent = samples_sent + 1;
  end
  if (last) begin
    intf.last <= 1'b0;
  end
  if (reset_valid) begin
    intf.valid <= '0;
    @(posedge clk);
  end
endtask

task automatic send_last();
  intf.valid <= 1'b1;
  intf.last <= 1'b1;
  do begin @(posedge clk); end while (~(intf.valid & intf.ready));
  intf.valid <= 1'b0;
  intf.last <= 1'b0;
endtask

// Update registers with an Axis_If interface
// must be augmented with a process or other statement to actually update the
// data
task automatic send_sample_with_timeout(
  input int timeout,
  input logic [DWIDTH-1:0] data,
  output logic success
);
  int timer;
  timer = 0;
  success = 1'b0;
  intf.valid <= 1'b1;
  intf.data <= data;
  do begin
    @(posedge clk);
    timer = timer + 1;
    success = intf.valid & intf.ready;
  end while ((timer < timeout) & (~(intf.valid & intf.ready)));
  intf.valid <= 1'b0;
endtask

task automatic disable_valid();
  intf.valid <= 1'b0;
endtask

endmodule
