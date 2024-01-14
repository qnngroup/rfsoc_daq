// axis_config_reg_cdc_test.sv - Reed Foster

`timescale 1ns/1ps

import sim_util_pkg::*;

module axis_config_reg_cdc_test ();

sim_util_pkg::debug debug = new(DEFAULT);

Axis_If #(.DWIDTH(8)) f2s_src ();
Axis_If #(.DWIDTH(8)) f2s_dest ();
Axis_If #(.DWIDTH(8)) s2f_src ();
Axis_If #(.DWIDTH(8)) s2f_dest ();

logic fast_reset;
logic fast_clk = 0;
localparam FAST_CLK_RATE_HZ = 384_000_000;
always #(0.5s/FAST_CLK_RATE_HZ) fast_clk = ~fast_clk;

logic slow_reset;
logic slow_clk = 0;
localparam SLOW_CLK_RATE_HZ = 384_000_000;
always #(0.5s/SLOW_CLK_RATE_HZ) slow_clk = ~slow_clk;

axis_config_reg_cdc #(
  .DWIDTH(8)
) dut_f2s_i (
  .src_clk(fast_clk),
  .src_reset(fast_reset),
  .dest_clk(slow_clk),
  .dest_reset(slow_reset),
  .src(f2s_src),
  .dest(f2s_dest)
);

axis_config_reg_cdc #(
  .DWIDTH(8)
) dut_s2f_i (
  .src_clk(slow_clk),
  .src_reset(slow_reset),
  .dest_clk(fast_clk),
  .dest_reset(fast_reset),
  .src(s2f_src),
  .dest(s2f_dest)
);

logic [7:0] f2s_sent [$];
logic [7:0] f2s_received [$];
logic [7:0] f2s_last_sent [$];
logic [7:0] f2s_last_received [$];
logic [7:0] s2f_sent [$];
logic [7:0] s2f_received [$];
logic [7:0] s2f_last_sent [$];
logic [7:0] s2f_last_received [$];

logic f2s_enable_send, s2f_enable_send;

always @(posedge fast_clk) begin
  if (fast_reset) begin
    f2s_src.data <= '0;
  end else begin
    f2s_src.valid <= $urandom() & f2s_enable_send;
    f2s_src.last <= $urandom_range(0,100) < 20;
    s2f_dest.ready <= $urandom() & 1'b1;
    if (f2s_src.ok) begin
      f2s_sent.push_front(f2s_src.data);
      f2s_src.data <= $urandom_range(0, 8'hff);
      if (f2s_src.last) begin
        f2s_last_sent.push_front(f2s_sent.size());
      end
    end
    if (s2f_dest.ok) begin
      s2f_received.push_front(s2f_dest.data);
      if (s2f_dest.last) begin
        s2f_last_received.push_front(s2f_received.size());
      end
    end
  end
end

always @(posedge slow_clk) begin
  if (slow_reset) begin
    s2f_src.data <= '0;
  end else begin
    s2f_src.valid <= $urandom() & s2f_enable_send;
    s2f_src.last <= $urandom_range(0,100) < 20;
    f2s_dest.ready <= $urandom() & 1'b1;
    if (s2f_src.ok) begin
      s2f_sent.push_front(s2f_src.data);
      s2f_src.data <= $urandom_range(0, 8'hff);
      if (s2f_src.last) begin
        s2f_last_sent.push_front(s2f_sent.size());
      end
    end
    if (f2s_dest.ok) begin
      f2s_received.push_front(f2s_dest.data);
      if (f2s_dest.last) begin
        f2s_last_received.push_front(f2s_received.size());
      end
    end
  end
end

task automatic check_results(
  inout logic [7:0] sent [$],
  inout logic [7:0] received [$]
);
  if (sent.size() !== received.size()) begin
    debug.error($sformatf(
      "sent.size() = %0d != received.size() = %0d",
      sent.size(),
      received.size())
    );
  end
  while ((sent.size() > 0) & (received.size > 0)) begin
    if (sent[$] !== received[$]) begin
      debug.error($sformatf(
        "sample mismatch, got %x expected %x",
        received[$],
        sent[$])
      );
    end
    sent.pop_back();
    received.pop_back();
  end
endtask

initial begin
  debug.display("### TESTING AXI-STREAM CONFIGURATION REGISTER CDC ###", DEFAULT);
  slow_reset <= 1'b1;
  fast_reset <= 1'b1;
  s2f_enable_send <= 1'b0;
  f2s_enable_send <= 1'b0;
  repeat (100) @(posedge slow_clk);
  slow_reset <= 1'b0;
  @(posedge fast_clk);
  fast_reset <= 1'b0;
  
  repeat (10) @(posedge slow_clk);
  s2f_enable_send <= 1'b1;
  @(posedge fast_clk);
  f2s_enable_send <= 1'b1;

  // send some data
  repeat (10000) @(posedge slow_clk);
  // stop sending data, finish any transfers in progress
  s2f_enable_send <= 1'b0;
  @(posedge fast_clk);
  f2s_enable_send <= 1'b0;

  repeat (50) @(posedge slow_clk);

  debug.display("checking data for fast->slow CDC", VERBOSE);
  check_results(f2s_sent, f2s_received);
  debug.display("checking last for fast->slow CDC", VERBOSE);
  check_results(f2s_last_sent, f2s_last_received);
  debug.display("checking data for slow->fast CDC", VERBOSE);
  check_results(s2f_sent, s2f_received);
  debug.display("checking last for slow->fast CDC", VERBOSE);
  check_results(s2f_last_sent, s2f_last_received);

  debug.finish();
end

endmodule
