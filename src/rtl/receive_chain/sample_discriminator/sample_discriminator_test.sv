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

Realtime_Parallel_If #(.DWIDTH(rx_pkg::SAMPLE_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_data_in ();
Realtime_Parallel_If #(.DWIDTH(rx_pkg::SAMPLE_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_data_out ();
Realtime_Parallel_If #(.DWIDTH(buffer_pkg::TSTAMP_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_timestamps_out ();
logic adc_reset_state;
logic [tx_pkg::CHANNELS-1:0] adc_digital_trigger_in;

localparam int MAX_DELAY_CYCLES = 64;
localparam int TIMER_BITS = $clog2(MAX_DELAY_CYCLES);
Axis_If #(.DWIDTH(2*rx_pkg::CHANNELS*rx_pkg::SAMPLE_WIDTH)) ps_thresholds ();
Axis_If #(.DWIDTH(3*rx_pkg::CHANNELS*rx_pkg::TIMER_BITS)) ps_delays ();
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS))) ps_trigger_select ();
Axis_If #(.DWIDTH(rx_pkg::CHANNELS)) ps_disable_discriminator ();

sample_discriminator_tb #(
  .MAX_DELAY_CYCLES(MAX_DELAY_CYCLES)
) tb_i (
  .clk(ps_clk),
  .thresholds(ps_thresholds),
  .delays(ps_delays),
  .trigger_select(ps_trigger_select),
  .disable_discriminator(ps_disable_discriminator)
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

// always save output data
rx_pkg::sample_t received_data [$];
logic [buffer_pkg::TSTAMP_WIDTH-1:0] received_timestamps [$];
always_ff @(posedge adc_clk) begin
  for (int channel = 0; channel < rx_pkg::CHANNELS; channel++) begin
    if (adc_data_out.valid[channel]) begin
      for (int sample = 0; sample < rx_pkg::PARALLEL_SAMPLES; sample++) begin
        received_data.push_front(adc_data_out.data[channel][sample*rx_pkg::SAMPLE_WIDTH+:SAMPLE_WIDTH]);
      end
    end
    if (adc_timestamps_out.valid[channel]) begin
      received_timestamps.push_front(adc_timestamps_out.data[channel]);
    end
  end
end

initial begin
  debug.display("### TESTING SAMPLE DISCRIMINATOR ###", sim_util_pkg::DEFAULT);
  debug.finish();

  adc_data_in.valid <= '0;
end

endmodule
