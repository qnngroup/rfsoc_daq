// receive_top_test.sv - Reed Foster
// verifies data from ADC is saved correctly
//
// send triangle wave of different frequency for each channel
// check the saved data is a triangle wave on raw ADC channels
// and a square wave on differentiated channels
//
// check multiplexer worked correctly (use non-default multiplexer setting)
//
// make sure samples/timestamps write depth has a non-zero number of
// transactions after each capture
//
// try non-default banking mode
//
// try resetting capture
//
// try resetting readout
//
// try changing discriminator thresholds
//    check to make sure there are no values saved below the low threshold
//    except for at most pre-delay+post-delay per timestamp
//
// try changing delay settings
//
// try changing trigger source (use non-default trigger pattern)
//    if triggering on differentiated channel, should get rising edges only
//
// test digital triggers
//    use non-default trigger setup (i.e. use the digital triggers)
//    just check that we're able to save some data (i.e. readout is possible)
//    after applying a digital trigger

`timescale 1ns / 1ps
module receive_top_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT); // printing, error tracking

logic adc_reset;
logic adc_clk = 0;
localparam ADC_CLK_RATE_HZ = 512_000_000;
always #(0.5s/ADC_CLK_RATE_HZ) adc_clk = ~adc_clk;

logic ps_reset;
logic ps_clk = 0;
localparam PS_CLK_RATE_HZ = 100_000_000;
always #(0.5s/PS_CLK_RATE_HZ) ps_clk = ~ps_clk;

// DUT parameters
localparam int AXI_MM_WIDTH = 128;
localparam int DISCRIMINATOR_MAX_DELAY = 64;
localparam int BUFFER_READ_LATENCY = 4;

localparam int TIMER_BITS = $clog2(DISCRIMINATOR_MAX_DELAY);

// DUT data interfaces
Realtime_Parallel_If #(.DWIDTH(rx_pkg::DATA_WIDTH), .CHANNELS(rx_pkg::CHANNELS)) adc_data_in ();
Axis_If #(.DWIDTH(AXI_MM_WIDTH)) ps_readout_data ();
// buffer status interfaces
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*($clog2(buffer_pkg::SAMPLE_BUFFER_DEPTH)+1))) ps_samples_write_depth ();
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*($clog2(buffer_pkg::TSTAMP_BUFFER_DEPTH)+1))) ps_timestamps_write_depth ();
// buffer configuration interfaces
Axis_If #(.DWIDTH(3)) ps_capture_arm_start_stop ();
Axis_If #(.DWIDTH(buffer_pkg::BANKING_MODE_WIDTH)) ps_capture_banking_mode ();
Axis_If #(.DWIDTH(1)) ps_capture_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_readout_sw_reset ();
Axis_If #(.DWIDTH(1)) ps_readout_start ();

// discriminator
Axis_If #(.DWIDTH(2*rx_pkg::CHANNELS*rx_pkg::SAMPLE_WIDTH)) ps_discriminator_thresholds ();
Axis_If #(.DWIDTH(3*rx_pkg::CHANNELS*TIMER_BITS)) ps_discriminator_delays ();
Axis_If #(.DWIDTH(rx_pkg::CHANNELS*$clog2(rx_pkg::CHANNELS+tx_pkg::CHANNELS))) ps_discriminator_trigger_select ();
Axis_If #(.DWIDTH(rx_pkg::CHANNELS)) ps_discriminator_bypass ();

// channel mux
Axis_If #(.DWIDTH($clog2(2*rx_pkg::CHANNELS)*rx_pkg::CHANNELS)) ps_channel_mux_config ();

// trigger manager
Axis_If #(.DWIDTH(1+tx_pkg::CHANNELS)) ps_capture_digital_trigger_select();

logic [tx_pkg::CHANNELS-1:0] adc_digital_triggers;

receive_top_tb #(
  .DISCRIMINATOR_MAX_DELAY(DISCRIMINATOR_MAX_DELAY),
  .BUFFER_READ_LATENCY(BUFFER_READ_LATENCY),
  .AXI_MM_WIDTH(AXI_MM_WIDTH)
) tb_i (
  .adc_clk,
  .adc_reset,
  .adc_data_in,
  .adc_digital_triggers,
  .ps_clk,
  .ps_reset,
  .ps_readout_data,
  .ps_samples_write_depth,
  .ps_timestamps_write_depth,
  .ps_capture_arm_start_stop,
  .ps_capture_banking_mode,
  .ps_capture_sw_reset,
  .ps_readout_sw_reset,
  .ps_readout_start,
  .ps_discriminator_thresholds,
  .ps_discriminator_delays,
  .ps_discriminator_trigger_select,
  .ps_discriminator_bypass,
  .ps_channel_mux_config,
  .ps_capture_digital_trigger_select
);

receive_top #(
  .DISCRIMINATOR_MAX_DELAY(DISCRIMINATOR_MAX_DELAY),
  .BUFFER_READ_LATENCY(BUFFER_READ_LATENCY),
  .AXI_MM_WIDTH(AXI_MM_WIDTH)
) dut_i (
  .adc_clk,
  .adc_reset,
  .adc_data_in,
  .adc_digital_triggers,
  .ps_clk,
  .ps_reset,
  .ps_readout_data,
  .ps_samples_write_depth,
  .ps_timestamps_write_depth,
  .ps_capture_arm_start_stop,
  .ps_capture_banking_mode,
  .ps_capture_sw_reset,
  .ps_readout_sw_reset,
  .ps_readout_start,
  .ps_discriminator_thresholds,
  .ps_discriminator_delays,
  .ps_discriminator_trigger_select,
  .ps_discriminator_bypass,
  .ps_channel_mux_config,
  .ps_capture_digital_trigger_select
);

logic [tx_pkg::CHANNELS:0] trigger_manager_config;

initial begin
  debug.display("### TESTING RECEIVE TOPLEVEL ###", sim_util_pkg::DEFAULT);

  repeat (2) begin
    // wait a few clocks to make sure we don't assert reset too early for CDC
    repeat (10) @(posedge ps_clk);
    ps_reset <= 1'b1;
    @(posedge adc_clk);
    adc_reset <= 1'b1;
    tb_i.init();
    repeat (10) @(posedge ps_clk);
    ps_reset <= 1'b0;
    @(posedge adc_clk);
    adc_reset <= 1'b0;
    @(posedge ps_clk);
    tb_i.setup_adc_input_gen(debug);
    // configure sample buffer
    // 4 active channels
    tb_i.buffer_tb_i.set_banking_mode(debug, 2);
    // configure channel mux
    tb_i.setup_channel_mux(debug);
    // configure sample discriminator
    tb_i.setup_sample_discriminator(debug);
    // configure trigger manager
    trigger_manager_config = {{tx_pkg::CHANNELS{1'b0}}, 1'b1}; // OR, only enabling TX[0] trigger
    tb_i.set_capture_trigger_cfg(debug, trigger_manager_config);

    for (int capture_reset = 0; capture_reset < 2; capture_reset++) begin
      repeat (20) @(posedge ps_clk);
      // arm
      tb_i.buffer_tb_i.capture_arm_start_stop(debug, 1'b1, 1'b0, 1'b0);
      repeat (50) @(posedge adc_clk);
      // send a digital trigger
      tb_i.send_trigger({{(tx_pkg::CHANNELS-1){1'b0}}, 1'b1});
      // wait a bit
      repeat (100) @(posedge adc_clk);
      if (capture_reset == 0) begin
        // reset capture
        @(posedge ps_clk);
        tb_i.buffer_tb_i.reset_capture(debug);
      end
    end
    // wait a bit
    repeat (1000) @(posedge adc_clk);
    // stop capture
    @(posedge ps_clk);
    tb_i.buffer_tb_i.capture_arm_start_stop(debug, 1'b0, 1'b0, 1'b1);
    // wait a bit
    repeat (20) @(posedge ps_clk);
    // check write_depth has 1 transfer for timestamps and samples
    tb_i.buffer_tb_i.check_write_depth_num_packets(debug);
    for (int readout_reset = 0; readout_reset < 2; readout_reset++) begin
      // start readout
      tb_i.buffer_tb_i.start_readout(debug);
      repeat (50) @(posedge ps_clk);
      if (readout_reset == 0) begin
        tb_i.buffer_tb_i.reset_readout(debug);
        // wait to finish flushing the cancelled readout
        do @(posedge ps_clk); while (~((dut_i.buffer_i.timestamp_buffer_i.ps_readout_valid_pipe === 0) && (dut_i.buffer_i.sample_buffer_i.ps_readout_valid_pipe === 0)));
        repeat (10) @(posedge ps_clk)
        tb_i.buffer_tb_i.clear_received_data();
      end
    end
    // wait until readout finishes
    do @(posedge ps_clk); while (~(ps_readout_data.ok & ps_readout_data.last));
    // check output (4 active channels)
    tb_i.check_output(debug, 4);
    tb_i.clear_queues();
    // repeat 5 times
  end

  debug.finish();
end

endmodule
