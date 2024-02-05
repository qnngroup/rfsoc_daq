// sample_discriminator_test.sv - Reed Foster
// update configuration registers, wait a few cycles to synchronize, then
// reset the analog hysteresis and sample_count

`timescale 1ns / 1ps
module sample_discriminator_test();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT); // printing, error tracking

logic adc_reset;
logic adc_clk = 0;
localparam ADC_CLK_RATE_HZ = 512_000_000;
always #(0.5s/ADC_CLK_RATE_HZ) adc_clk = ~adc_clk;

logic ps_reset;
logic ps_clk = 0;
localparam PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

initial begin
  debug.display("### TESTING SAMPLE DISCRIMINATOR ###", sim_util_pkg::DEFAULT);
  debug.finish();
end

endmodule
