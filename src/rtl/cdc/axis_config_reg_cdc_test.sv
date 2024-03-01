// axis_config_reg_cdc_test.sv - Reed Foster

`timescale 1ns/1ps

module axis_config_reg_cdc_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT);

typedef logic [7:0] sample_t;
sim_util_pkg::queue #(.T(sample_t)) data_q_util = new;
sim_util_pkg::queue #(.T(int)) last_q_util = new;

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
localparam SLOW_CLK_RATE_HZ = 100_000_000;
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

axis_driver #(.DWIDTH(8)) f2s_driver_i (.clk(fast_clk), .intf(f2s_src));
axis_driver #(.DWIDTH(8)) s2f_driver_i (.clk(slow_clk), .intf(s2f_src));

axis_receiver #(
  .DWIDTH(8)
) f2s_receiver_i (
  .clk(slow_clk),
  .ready_rand(1'b1),
  .ready_en(1'b1),
  .intf(f2s_dest)
);

axis_receiver #(
  .DWIDTH(8)
) s2f_receiver_i (
  .clk(fast_clk),
  .ready_rand(1'b1),
  .ready_en(1'b1),
  .intf(s2f_dest)
);

initial begin
  debug.display("### TESTING AXI-STREAM CONFIGURATION REGISTER CDC ###", sim_util_pkg::DEFAULT);
  slow_reset <= 1'b1;
  fast_reset <= 1'b1;
  f2s_driver_i.init();
  s2f_driver_i.init();
  repeat (100) @(posedge slow_clk);
  slow_reset <= 1'b0;
  @(posedge fast_clk);
  fast_reset <= 1'b0;
  
  repeat (10) @(posedge slow_clk);

  @(posedge fast_clk);
  repeat (100) begin
    f2s_driver_i.send_samples(20, 1'b1, 1'b1);
    if ($urandom_range(0,100) < 20) begin
      f2s_driver_i.send_last();
    end
  end

  @(posedge slow_clk);
  repeat (100) begin
    s2f_driver_i.send_samples(20, 1'b1, 1'b1);
    if ($urandom_range(0,100) < 20) begin
      s2f_driver_i.send_last();
    end
  end

  repeat (50) @(posedge slow_clk);

  debug.display("checking data for fast->slow CDC", sim_util_pkg::VERBOSE);
  data_q_util.compare(debug, f2s_driver_i.data_q, f2s_receiver_i.data_q);
  debug.display("checking last for fast->slow CDC", sim_util_pkg::VERBOSE);
  last_q_util.compare(debug, f2s_driver_i.last_q, f2s_receiver_i.last_q);
  debug.display("checking data for slow->fast CDC", sim_util_pkg::VERBOSE);
  data_q_util.compare(debug, s2f_driver_i.data_q, s2f_receiver_i.data_q);
  debug.display("checking last for slow->fast CDC", sim_util_pkg::VERBOSE);
  last_q_util.compare(debug, s2f_driver_i.last_q, s2f_receiver_i.last_q);
 
  f2s_driver_i.clear_queues();
  s2f_driver_i.clear_queues();

  debug.finish();
end

endmodule
