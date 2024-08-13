
`timescale 1ns/1ps
module segmented_buffer_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT);

localparam int BUFFER_READ_LATENCY = 4;
localparam int AXI_MM_WIDTH = 128;

logic adc_reset;
logic adc_clk = 0;
localparam int ADC_CLK_RATE_HZ = 512_000_000;
always #(0.5s/ADC_CLK_RATE_HZ) adc_clk = ~adc_clk;

logic ps_reset;
logic ps_clk = 0;
localparam int PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

// data in
Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_samples_in ();
Realtime_Parallel_If #(.DWIDTH(buffer_pkg::TSTAMP_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_timestamps_in ();

// realtime
logic adc_digital_trigger;
logic adc_discriminator_reset;

// data out
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) ps_readout_data ();
// status
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*$clog2(buffer_pkg::SAMPLE_BUFFER_DEPTH))) ps_samples_write_depth ();
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*$clog2(buffer_pkg::TSTAMP_BUFFER_DEPTH))) ps_timestamps_write_depth ();
// configuration
Axis_If #(.DWIDTH(3)) ps_capture_arm_start_stop ();
Axis_If #(.DWIDTH(buffer_pkg::BANKING_MODE_WIDTH)) ps_capture_banking_mode ();
Axis_If #(.DWIDTH(1)) ps_capture_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_readout_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_readout_start ();

segmented_buffer #(
  .BUFFER_READ_LATENCY(BUFFFER_READ_LATENCY),
  .AXI_MM_WIDTH(AXI_MM_WIDTH)
) dut_i (
  .adc_clk,
  .adc_reset,
  .adc_samples_in,
  .adc_timestamps_in,
  .adc_digital_trigger_in,
  .adc_discriminator_reset,
  .ps_clk,
  .ps_reset,
  .ps_readout_data,
  .ps_samples_write_depth,
  .ps_timestamps_write_depth,
  .ps_capture_arm_start_stop,
  .ps_capture_banking_mode,
  .ps_capture_sw_reset,
  .ps_readout_sw_reset,
  .ps_readout_start
);

segmented_buffer_tb #(
  .AXI_MM_WIDTH(AXI_MM_WIDTH)
) tb_i (
  .adc_clk,
  .adc_reset,
  .adc_samples_in,
  .adc_timestamps_in,
  .adc_digital_trigger_in,
  .adc_discriminator_reset,
  .ps_clk,
  .ps_reset,
  .ps_readout_data,
  .ps_samples_write_depth,
  .ps_timestamps_write_depth,
  .ps_capture_arm_start_stop,
  .ps_capture_banking_mode,
  .ps_capture_sw_reset,
  .ps_readout_sw_reset,
  .ps_readout_start
);

enum {MANUAL_STOP, FULL} stop_mode;

initial begin
  debug.display("### TESTING SEGMENTED BUFFER TOPLEVEL ###", sim_util_pkg::DEFAULT);

 
  stop_mode = stop_mode.first;

  do begin: samples_cnt
    // mid-test reset
    adc_reset <= 1'b1;
    ps_reset <= 1'b1;

    adc_digital_trigger <= 1'b0;

    tb_i.init ();

    repeat (10) @(posedge ps_clk);
    ps_reset <= 1'b0;
    @(posedge adc_clk);
    adc_reset <= 1'b0;
    // send data
    case (stop_mode)
      MANUAL_STOP:
        repeat (100) @(posedge ps_clk)
      FULL:
        do @(posedge adc_clk); while (dut_i.adc_capture_full === '0);

    // clear queues
    tb_i.clear_write_depth();
    tb_i.clear_received_data();
    tb_i.clear_sent_data();
    stop_mode = stop_mode.next;
  end while (stop_mode != stop_mode.first);

  debug.finish();
end

endmodule
