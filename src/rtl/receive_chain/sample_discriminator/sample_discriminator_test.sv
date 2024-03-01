// sample_discriminator_test.sv - Reed Foster
// test sample_discriminator with various delays, digital/analog triggering,
// various thresholds for the analog trigger, enable/disable of the
// discriminator
//
// for each test:
// update configuration registers, wait a few cycles to synchronize, then
// reset the analog hysteresis and sample_count (with adc_reset_state)
//
// when disabled, check that all samples got through and that no timestamps were sent
//

`timescale 1ns / 1ps
module sample_discriminator_test();

sim_util_pkg::debug debug = new(sim_util_pkg::DEBUG); // printing, error tracking

logic adc_reset;
logic adc_clk = 0;
localparam int ADC_CLK_RATE_HZ = 512_000_000;
always #(0.5s/ADC_CLK_RATE_HZ) adc_clk = ~adc_clk;

logic ps_reset;
logic ps_clk = 0;
localparam int PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_data_in ();
Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_data_out ();
Realtime_Parallel_If #(.DWIDTH(buffer_pkg::TSTAMP_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_timestamps_out ();
logic adc_reset_state;
logic [tx_pkg::CHANNELS-1:0] adc_digital_trigger_in;

localparam int MAX_DELAY_CYCLES = 64;
localparam int TIMER_BITS = $clog2(MAX_DELAY_CYCLES);
Axis_If #(.DWIDTH(2*rx_pkg::CHANNELS*rx_pkg::SAMPLE_WIDTH)) ps_thresholds ();
Axis_If #(.DWIDTH(3*rx_pkg::CHANNELS*TIMER_BITS)) ps_delays ();
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS))) ps_trigger_select ();
Axis_If #(.DWIDTH(rx_pkg::CHANNELS)) ps_disable_discriminator ();

sample_discriminator_tb #(
  .MAX_DELAY_CYCLES(MAX_DELAY_CYCLES)
) tb_i (
  .adc_clk,
  .adc_reset,
  .adc_data_in,
  .adc_data_out,
  .adc_timestamps_out,
  .ps_clk,
  .ps_thresholds,
  .ps_delays,
  .ps_trigger_select,
  .ps_disable_discriminator
);

sample_discriminator #(
  .MAX_DELAY_CYCLES(MAX_DELAY_CYCLES)
) dut_i (
  .adc_clk,
  .adc_reset,
  .adc_data_in,
  .adc_data_out,
  .adc_timestamps_out,
  .adc_reset_state,
  .adc_digital_trigger_in,
  .ps_clk,
  .ps_reset,
  .ps_thresholds,
  .ps_delays,
  .ps_trigger_select,
  .ps_disable_discriminator
);

initial begin
  debug.display("### TESTING SAMPLE DISCRIMINATOR ###", sim_util_pkg::DEFAULT);

  tb_i.init();
  ps_reset <= 1'b1;
  adc_reset <= 1'b1;
  adc_reset_state <= 1'b0;
  adc_digital_trigger_in <= '0;

  repeat (10) @(posedge ps_clk);
  ps_reset <= 1'b0;
  @(posedge adc_clk);
  adc_reset <= 1'b0;

  repeat (100) @(posedge adc_clk);
  tb_i.enable_send();

  repeat (50) @(posedge adc_clk);
  tb_i.set_input_range(
    .min('0),
    .max(24)
  );
  repeat (50) @(posedge adc_clk);
  debug.display($sformatf(
    "sent_data = %0p",
    tb_i.adc_data_in_tx_i.data_q[0]),
    sim_util_pkg::DEBUG
  );
  

  // test digital trigger
  // test analog trigger

  debug.finish();
end

endmodule
