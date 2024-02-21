// sample_buffer_bank_test.sv - Reed Foster
// test for the individual banks

`timescale 1ns / 1ps
module sample_buffer_bank_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT); // printing, error tracking

logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

logic reset;

logic start, stop;
logic full;

localparam int PARALLEL_SAMPLES = 2;
localparam int SAMPLE_WIDTH = 16;

Axis_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH)) data_in ();
Axis_If #(.DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH)) data_out ();

sample_buffer_bank #(
  .BUFFER_DEPTH(1024),
  .PARALLEL_SAMPLES(2),
  .SAMPLE_WIDTH(16)
) dut_i (
  .clk,
  .reset,
  .data_in,
  .data_out,
  .start,
  .stop,
  .full,
  .first()
);

axis_driver #(
  .DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH)
) driver_i (
  .clk,
  .intf(data_in)
);

logic readout_enable;
axis_receiver #(
  .DWIDTH(PARALLEL_SAMPLES*SAMPLE_WIDTH)
) receiver_i (
  .clk,
  .ready_rand(1'b1),
  .ready_en(readout_enable),
  .intf(data_out)
);

// check that the DUT correctly saved everything
task check_results();
  // check last is the right size
  if (receiver_i.last_q.size() !== 1) begin
    debug.error($sformatf("expected exactly one tlast event, got %0d", receiver_i.last_q.size()));
  end else begin
    if (receiver_i.last_q[$] != driver_i.data_q.size() + 2) begin
      debug.error($sformatf("expected last on sample %0d, got it on %0d", driver_i.data_q.size() + 2,receiver_i.last_q[$]));
    end
  end
  while (receiver_i.last_q.size() > 0) receiver_i.last_q.pop_back();
  // pop first sample received since it is intended to be overwritten in
  // multibank buffer
  receiver_i.data_q.pop_back();
  debug.display($sformatf("driver_i.data_q.size() = %0d", driver_i.data_q.size()), sim_util_pkg::VERBOSE);
  debug.display($sformatf("receiver_i.data_q.size() = %0d", receiver_i.data_q.size()), sim_util_pkg::VERBOSE);
  if ((driver_i.data_q.size() + 1) != receiver_i.data_q.size()) begin
    debug.error($sformatf(
      "mismatch in amount of sent/received data (sent %0d, received %0d)",
      driver_i.data_q.size() + 1,
      receiver_i.data_q.size())
    );
  end
  if (receiver_i.data_q[$] != driver_i.data_q.size()) begin
    debug.error($sformatf(
      "incorrect sample count reported by buffer (sent %0d, reported %0d)",
      driver_i.data_q.size(),
      receiver_i.data_q[$])
    );
  end
  receiver_i.data_q.pop_back(); // remove sample count
  while (driver_i.data_q.size() > 0 && receiver_i.data_q.size() > 0) begin
    // data from channel 0 can be reordered with data from channel 2
    if (driver_i.data_q[$] != receiver_i.data_q[$]) begin
      debug.error($sformatf(
        "data mismatch error (received %x, sent %x)",
        receiver_i.data_q[$],
        driver_i.data_q[$])
      );
    end
    driver_i.data_q.pop_back();
    receiver_i.data_q.pop_back();
  end
endtask

task automatic do_readout (input int timeout);
  int cycle_count;
  cycle_count = 0;
  readout_enable <= 1'b1;
  data_out.ready <= 1'b0;
  repeat (100) @(posedge clk);
  data_out.ready <= 1'b1;
  while ((!(data_out.last & data_out.ok)) & (cycle_count < timeout)) begin
    @(posedge clk);
    data_out.ready <= $urandom();
    cycle_count = cycle_count + 1;
  end
  @(posedge clk);
  data_out.ready <= 1'b0;
  readout_enable <= 1'b0;
endtask

initial begin
  debug.display("### TESTING SAMPLE_BUFFER_BANK ###", sim_util_pkg::DEFAULT);
  reset <= 1'b1;
  start <= 1'b0;
  stop <= 1'b0;
  driver_i.disable_valid();
  repeat (100) @(posedge clk);
  reset <= 1'b0;
  repeat (50) @(posedge clk);
  // start
  start <= 1'b1;
  @(posedge clk);
  start <= 1'b0;
  repeat (100) @(posedge clk);
  // send samples
  driver_i.send_samples(32, 1'b1, 1'b1);
  driver_i.send_samples(64, 1'b0, 1'b1);
  driver_i.send_samples(32, 1'b1, 1'b1);
  repeat (50) @(posedge clk);
  stop <= 1'b1;
  @(posedge clk);
  stop <= 1'b0;
  do_readout(100000);
  debug.display("checking results for test with a few samples", sim_util_pkg::VERBOSE);
  check_results();
  // do more tests

  // test with one sample
  // start
  start <= 1'b1;
  @(posedge clk);
  start <= 1'b0;
  repeat (100) @(posedge clk);
  // send samples
  driver_i.send_samples(1, 1'b0, 1'b1);
  repeat (50) @(posedge clk);
  stop <= 1'b1;
  @(posedge clk);
  stop <= 1'b0;
  do_readout(1000);
  debug.display("checking results for test with one sample", sim_util_pkg::VERBOSE);
  check_results();

  // test with no samples
  // start
  start <= 1'b1;
  @(posedge clk);
  start <= 1'b0;
  repeat (100) @(posedge clk);
  // don't send samples
  repeat (50) @(posedge clk);
  stop <= 1'b1;
  @(posedge clk);
  stop <= 1'b0;
  do_readout(1000);
  debug.display("checking results for test with no samples", sim_util_pkg::VERBOSE);
  check_results();

  // fill up buffer
  // start
  start <= 1'b1;
  @(posedge clk);
  start <= 1'b0;
  repeat (100) @(posedge clk);
  // send samples
  driver_i.send_samples(256, 1'b1, 1'b1);
  driver_i.send_samples(512, 1'b0, 1'b1);
  driver_i.send_samples(256, 1'b1, 1'b1);
  repeat (50) @(posedge clk);
  stop <= 1'b1;
  @(posedge clk);
  stop <= 1'b0;
  do_readout(100000);
  debug.display("checking results for test with 1024 samples (full buffer)", sim_util_pkg::VERBOSE);
  check_results();
  repeat (500) @(posedge clk);
  debug.finish();
end

endmodule
