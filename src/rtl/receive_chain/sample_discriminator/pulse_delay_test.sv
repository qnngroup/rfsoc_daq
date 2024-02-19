// pulse_delay_test.sv - Reed Foster
// Tests pulse_delay module

`timescale 1ns/1ps
module pulse_delay_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT); // printing, error tracking

logic reset;
logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

localparam int TIMER_BITS = 8;
logic [TIMER_BITS-1:0] delay;
logic in_pls;
logic [1:0] out_pls;

pulse_delay #(
  .TIMER_BITS(TIMER_BITS),
  .RETRIGGER_MODE(0)
) dut_no_retrigger_i (
  .clk,
  .reset,
  .delay,
  .in_pls,
  .out_pls(out_pls[0])
);

pulse_delay #(
  .TIMER_BITS(TIMER_BITS),
  .RETRIGGER_MODE(1)
) dut_retrigger_i (
  .clk,
  .reset,
  .delay,
  .in_pls,
  .out_pls(out_pls[1])
);

int timer = 0;
always @(posedge clk) timer <= timer + 1;

int expected_times [2][$];
int received_times [2][$];
always @(posedge clk) begin
  if (in_pls) begin
    debug.display($sformatf(
      "got in_pls at t = %0d",
      timer),
      sim_util_pkg::DEBUG
    );
    for (int i = 0; i < 2; i++) begin
      debug.display($sformatf(
        "expected_times[%0d][0] = %0d",
        i,
        expected_times[i][0]),
        sim_util_pkg::DEBUG
      );
      if (expected_times[i][0] <= timer) begin
        expected_times[i].push_front(timer+delay+1);
      end else begin
        if (i == 1) begin
          expected_times[i][0] = timer+delay+1;
        end
      end
    end
  end
  if (out_pls[0]) begin
    received_times[0].push_front(timer);
  end
  if (out_pls[1]) begin
    received_times[1].push_front(timer);
  end
end

task check_results();
  for (int i = 0; i < 2; i++) begin
    debug.display($sformatf(
      "checking results for dut[%0d]",
      i),
      sim_util_pkg::DEBUG
    );
    if (expected_times[i].size() !== received_times[i].size()) begin
      debug.error($sformatf(
        "expected_times.size() != received_times.size() (%0d != %0d)",
        expected_times[i].size(),
        received_times[i].size())
      );
    end
    while (expected_times[i].size() > 0 && received_times[i].size() > 0) begin
      if (expected_times[i][$] !== received_times[i][$]) begin
        debug.error($sformatf(
          "time mismatch: expected %0d, got %0d",
          expected_times[i][$],
          received_times[i][$])
        );
      end
      expected_times[i].pop_back();
      received_times[i].pop_back();
    end
  end
endtask

initial begin
  debug.display("### TESTING PULSE DELAY ###", sim_util_pkg::DEFAULT);
  reset <= 1'b1;
  delay <= '0;
  in_pls <= 1'b0;
  repeat (10) @(posedge clk);
  reset <= 1'b0;
  repeat (2) @(posedge clk);

  repeat (10) begin
    repeat (10) begin
      in_pls <= 1'b1;
      @(posedge clk);
      in_pls <= 1'b0;
      @(posedge clk);
      repeat ($urandom_range(1, 2*(delay+1))) @(posedge clk);
    end
    delay <= $urandom_range(1, 10);
    repeat (2) @(posedge clk);
  end

  // wait to make sure we get the final output
  repeat (delay) @(posedge clk);
  check_results();
  
  debug.finish();
end

endmodule
