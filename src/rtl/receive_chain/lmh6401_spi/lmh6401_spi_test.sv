// lmh6401_spi_test.sv - Reed Foster
// Check that the lmh6401_spi module is correctly serializing data and only
// ever pulls one CS line low (i.e. only one slave is active at a time)
// Output is compared to input bit-by-bit at the end of the test by comparing
// queues of sent bits and received bits

import sim_util_pkg::*;

`timescale 1ns / 1ps
module lmh6401_spi_test();

sim_util_pkg::debug debug = new(DEFAULT); // printing, error tracking

logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

logic reset;

localparam NUM_CHANNELS = 4;

Axis_If #(.DWIDTH($clog2(NUM_CHANNELS) + 16)) command_in ();
SPI_Parallel_If #(.CHANNELS(NUM_CHANNELS)) spi ();

logic [$clog2(NUM_CHANNELS)-1:0] addr_in;
logic [15:0] data_in;
assign command_in.data = {addr_in, data_in};
logic sck_d;

bit sent [NUM_CHANNELS][$];
bit received [NUM_CHANNELS][$];

task automatic check_single_cs_active();
  bit active;
  active = 0;
  for (int channel = 0; channel < NUM_CHANNELS; channel++) begin
    if (spi.cs_n[channel] === 0) begin
      if (active) begin
        debug.error($sformatf(
          "multiple CS_N active at the same time: cs_n = %b",
          spi.cs_n)
        );
      end else begin
        active = 1;
      end
    end
  end
endtask

always @(posedge clk) begin
  sck_d <= spi.sck;
  if (reset) begin
    {addr_in, data_in} <= '0;
  end else begin
    if (command_in.ok) begin
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
      if (spi.cs_n[channel] === 0) begin
        if (spi.sck & (~sck_d)) begin
          // only save data on rising clock edge
          received[channel].push_front(spi.sdi);
        end
      end
    end
    // check to make sure only a single cs is active
    check_single_cs_active();
  end
end

task check_results();
  for (int channel = 0; channel < NUM_CHANNELS; channel++) begin
    debug.display($sformatf(
      "received[%0d].size() = %0d",
      channel,
      received[channel].size()),
      VERBOSE
    );
    debug.display($sformatf(
      "sent[%0d].size() = %0d",
      channel,
      sent[channel].size()),
      VERBOSE
    );
    if (received[channel].size() != sent[channel].size()) begin
      debug.error($sformatf(
        "mismatched sizes for channel %0d; got %0d samples, expected %0d",
        channel,
        received[channel].size(),
        sent[channel].size())
      );
    end
    while (received[channel].size() > 0 && sent[channel].size() > 0) begin
      if (sent[channel][$] !== received[channel][$]) begin
        debug.error($sformatf(
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
  .command_in,
  .spi
);

initial begin
  debug.display("### running test for lmh6401_spi ###", DEFAULT);
  reset <= 1'b1;
  command_in.valid <= '0;
  repeat (500) @(posedge clk);
  reset <= 0;
  repeat (500) @(posedge clk);
  // toggle command_in.valid;
  repeat (500) begin
    command_in.valid <= $urandom() & 1'b1;
    @(posedge clk);
    if (command_in.ok) begin
      // wait 16 cycles of SCK
      repeat (16) @(negedge spi.sck);
    end
    while (!command_in.ready) @(posedge clk);
  end
  command_in.valid <= 1'b0;
  repeat (16) @(negedge spi.sck);
  while (!command_in.ready) @(posedge clk);
  repeat (100) @(posedge clk);
  check_results();
  debug.finish();
end

endmodule
