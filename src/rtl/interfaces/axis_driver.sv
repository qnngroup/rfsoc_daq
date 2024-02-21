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
  if (intf.ok) begin
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

task automatic clear_queues ();
  while (data_q.size() > 0) data_q.pop_back();
  while (last_q.size() > 0) last_q.pop_back();
endtask

task automatic send_samples(
  input int n_samples, // number of samples to send
  input bit rand_arrivals, // if 1, toggle valid, otherwise leave it high
  input bit reset_valid // if 1, reset valid signal after sending the samples
);
  int samples_sent;
  logic [NUM_WORDS*WORD_WIDTH-1:0] temp_data;
  // reset
  samples_sent = 0;
  intf.valid <= 1'b1;
  while (samples_sent < n_samples) begin
    @(posedge clk);
    if (intf.ok) begin
      for (int word = 0; word < NUM_WORDS; word++) begin
        temp_data[word*WORD_WIDTH+:WORD_WIDTH] = $urandom();
      end
      intf.data <= temp_data[DWIDTH-1:0];
      samples_sent = samples_sent + 1'b1;
    end
    if (rand_arrivals) begin
      intf.valid <= $urandom();
    end // else do nothing; intf.valid is already 1'b1
  end
  if (reset_valid) begin
    intf.valid <= '0;
    @(posedge clk);
  end
endtask

task automatic send_last();
  intf.valid <= 1'b1;
  intf.last <= 1'b1;
  do begin @(posedge clk); end while (~intf.ok);
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
  while ((timer < timeout) & (~success)) begin
    timer = timer + 1;
    if (intf.ok) begin
      success = 1'b1;
    end
    @(posedge clk);
  end
  intf.valid <= 1'b0;
endtask

task automatic disable_valid();
  intf.valid <= 1'b0;
endtask

endmodule
