
`timescale 1ns/1ps
module segmented_buffer_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::VERBOSE);

localparam int DISC_MAX_DELAY_CYCLES = 64;
localparam int BUFFER_READ_LATENCY = 4;

logic adc_reset;
logic adc_clk = 0;
localparam int ADC_CLK_RATE_HZ = 512_000_000;
always #(0.5s/ADC_CLK_RATE_HZ) adc_clk = ~adc_clk;

logic ps_reset;
logic ps_clk = 0;
localparam int PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

segmented_buffer #(
  .DISC_MAX_DELAY_CYCLES(DISC_MAX_DELAY_CYCLES),
  .BUFFER_READ_LATENCY(BUFFFER_READ_LATENCY)
) dut_i (
  .adc_clk,
  .adc_reset,
  .adc_data_in,
  .adc_digital_trigger_in,
);


endmodule
