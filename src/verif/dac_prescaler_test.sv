import sim_util_pkg::*;

`timescale 1ns / 1ps
module dac_prescaler_test ();


logic reset;
logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

localparam int SAMPLE_WIDTH = 16;
localparam int PARALLEL_SAMPLES = 16;
localparam int SCALE_WIDTH = 18;
localparam int SAMPLE_FRAC_BITS = 16;
localparam int SCALE_FRAC_BITS = 16;

typedef logic signed [SAMPLE_WIDTH-1:0] int_t;
typedef logic signed [SCALE_WIDTH-1:0] sc_int_t;

sim_util_pkg::generic #(int_t) util; // abs, max functions on signed sample type
sim_util_pkg::debug #(.VERBOSITY(DEBUG)) dbg = new; // printing, error tracking

Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) data_out_if();
Axis_If #(.DWIDTH(SAMPLE_WIDTH*PARALLEL_SAMPLES)) data_in_if();
Axis_If #(.DWIDTH(SCALE_WIDTH)) scale_factor_if();

sc_int_t scale_factor, scale_factor_d;
assign scale_factor_if.data = scale_factor;
assign scale_factor_if.valid = 1'b1;
localparam int LATENCY = 4;
int_t data_out_test [LATENCY][PARALLEL_SAMPLES];

real d_in;
real scale;

int_t expected [$];
int_t received [$];

always @(posedge clk) begin
  scale_factor_d <= scale_factor;
  if (reset) begin
    data_in_if.data <= '0;
  end else begin
    // save data we send, as well as what it should be transformed into
    if (data_in_if.ok) begin
      for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
        data_in_if.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= $urandom_range({SAMPLE_WIDTH{1'b1}});
        d_in = real'(int_t'(data_in_if.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
        scale = real'(sc_int_t'(scale_factor));
        expected.push_front(int_t'(d_in/(2.0**SAMPLE_FRAC_BITS) * scale/(2.0**SCALE_FRAC_BITS) * 2.0**SAMPLE_FRAC_BITS));
      end
    end
    // save data we got
    if (data_out_if.ok) begin
      for (int i = 0; i < PARALLEL_SAMPLES; i++) begin
        received.push_front(int_t'(data_out_if.data[i*SAMPLE_WIDTH+:SAMPLE_WIDTH]));
      end
    end
  end
end

task check_results();
  dbg.display($sformatf("received.size() = %0d", received.size()), VERBOSE);
  dbg.display($sformatf("expected.size() = %0d", expected.size()), VERBOSE);
  if (received.size() != expected.size()) begin
    dbg.error("mismatched sizes; got a different number of samples than expected");
  end
  // check the values match
  // casting to uint_t seems to perform a rounding operation, so the test data may be slightly too large
  while (received.size() > 0 && expected.size() > 0) begin
    if (util.abs(expected[$] - received[$]) > 1) begin
      dbg.error($sformatf(
        "mismatch: got %x, expected %x",
        received[$],
        expected[$])
      );
    end
    received.pop_back();
    expected.pop_back();
  end
endtask

dac_prescaler #(
  .SAMPLE_WIDTH(SAMPLE_WIDTH),
  .PARALLEL_SAMPLES(PARALLEL_SAMPLES),
  .SCALE_WIDTH(SCALE_WIDTH),
  .SAMPLE_FRAC_BITS(SAMPLE_FRAC_BITS),
  .SCALE_FRAC_BITS(SCALE_FRAC_BITS)
) dut_i (
  .clk,
  .reset,
  .data_out(data_out_if),
  .data_in(data_in_if),
  .scale_factor(scale_factor_if)
);

initial begin
  dbg.display("######################################", DEFAULT);
  dbg.display("# running test for dac_prescaler     #", DEFAULT);
  dbg.display("######################################", DEFAULT);
  reset <= 1'b1;
  data_in_if.data <= '0;
  data_in_if.valid <= 1'b0;
  data_out_if.ready <= 1'b0;
  repeat (500) @(posedge clk);
  reset <= 1'b0;
  scale_factor <= $urandom_range(18'h3ffff);
  repeat(5) @(posedge clk);
  data_in_if.valid <= 1'b1;
  repeat (500) @(posedge clk);
  scale_factor <= $urandom_range(18'h3ffff);
  repeat (500) begin
    @(posedge clk);
    data_in_if.valid <= $urandom_range(0,1) & 1'b1;
    data_out_if.ready <= $urandom_range(0,1) & 1'b1;
  end
  data_in_if.valid <= 1'b0;
  repeat (1000) begin
    @(posedge clk);
    data_out_if.ready <= $urandom_range(0,1) & 1'b1;
  end
  data_out_if.ready <= 1'b1;
  repeat (500) @(posedge clk);
  check_results();
  dbg.finish();
end

endmodule
