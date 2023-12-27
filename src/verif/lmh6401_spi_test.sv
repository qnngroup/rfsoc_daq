// lmh6401_spi_test.sv - Reed Foster
// Check that the lmh6401_spi module is correctly serializing data and only
// ever pulls one CS line low (i.e. only one slave is active at a time)
// Output is compared to input bit-by-bit at the end of the test by comparing
// queues of sent bits and received bits

import sim_util_pkg::*;

`timescale 1ns / 1ps
module lmh6401_spi_test();

sim_util_pkg::debug #(.VERBOSITY(DEFAULT)) dbg = new; // printing, error tracking

logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

logic reset;

localparam NUM_CHANNELS = 4;

logic [$clog2(NUM_CHANNELS)-1:0] addr_in;
logic [15:0] data_in;
logic data_in_valid, data_in_ready;
logic [NUM_CHANNELS-1:0] cs_n;
logic sck, sck_d;
logic sdi;

bit sent [NUM_CHANNELS][$];
bit received [NUM_CHANNELS][$];

task automatic check_single_cs_active();
  bit active;
  active = 0;
  for (int channel = 0; channel < NUM_CHANNELS; channel++) begin
    if (cs_n[channel] === 0) begin
      if (active) begin
        dbg.error($sformatf(
          "multiple CS_N active at the same time: cs_n = %b",
          cs_n)
        );
      end else begin
        active = 1;
      end
    end
  end
endtask

always @(posedge clk) begin
  sck_d <= sck;
  if (reset) begin
    data_in <= '0;
    addr_in <= '0;
  end else begin
    if (data_in_valid && data_in_ready) begin
      // send new random data and address
      data_in <= $urandom_range(0, 15'h7fff);
      addr_in <= $urandom_range(0, NUM_CHANNELS-1);
      // MSB should get set to zero
      sent[addr_in].push_front(1'b0);
      for (int i = 14; i >= 0 ; i--) begin
        sent[addr_in].push_front(data_in[i]);
      end
    end
    for (int channel = 0; channel < NUM_CHANNELS; channel++) begin
      if (cs_n[channel] === 0) begin
        if (sck & (~sck_d)) begin
          // only save data on rising clock edge
          received[channel].push_front(sdi);
        end
      end
    end
    // check to make sure only a single cs is active
    check_single_cs_active();
  end
end

task check_results();
  for (int channel = 0; channel < NUM_CHANNELS; channel++) begin
    dbg.display($sformatf(
      "received[%0d].size() = %0d",
      channel,
      received[channel].size()),
      VERBOSE
    );
    dbg.display($sformatf(
      "sent[%0d].size() = %0d",
      channel,
      sent[channel].size()),
      VERBOSE
    );
    if (received[channel].size() != sent[channel].size()) begin
      dbg.error($sformatf(
        "mismatched sizes for channel %d; got a different number of samples than expected",
        channel)
      );
    end
    while (received[channel].size() > 0 && sent[channel].size() > 0) begin
      if (sent[channel][$] !== received[channel][$]) begin
        dbg.error($sformatf(
          "mismatch on channel %0d: got %x, expected %x",
          channel,
          received[channel][$],
          sent[channel][$])
        );
      end
      sent[channel].pop_back();
      received[channel].pop_back();
    end
  end
endtask

lmh6401_spi #(
  .AXIS_CLK_FREQ(100_000_000),
  .SPI_CLK_FREQ(1_000_000),
  .NUM_CHANNELS(NUM_CHANNELS)
) dut_i (
  .clk, .reset,
  .addr_in,
  .data_in,
  .data_in_valid,
  .data_in_ready,
  .cs_n,
  .sck,
  .sdi
);

initial begin
  dbg.display("### running test for lmh6401_spi ###", DEFAULT);
  reset <= 1;
  data_in_valid <= '0;
  repeat (500) @(posedge clk);
  reset <= 0;
  repeat (500) @(posedge clk);
  // toggle data_in_valid;
  repeat (500) begin
    data_in_valid <= $urandom() & 1'b1;
    @(posedge clk);
    if (data_in_valid && data_in_ready) begin
      // wait 16 cycles of SCK
      repeat (16) @(negedge sck);
    end
    while (!data_in_ready) @(posedge clk);
  end
  data_in_valid <= 1'b0;
  repeat (16) @(negedge sck);
  while (!data_in_ready) @(posedge clk);
  repeat (100) @(posedge clk);
  check_results();
  dbg.finish();
end

endmodule
