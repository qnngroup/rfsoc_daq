// awg_test.sv - Reed Foster
// Stress test of arbitrary waveform generator
// Writes a random waveform to the AWG buffer memory and triggers the
// generation of zero or more bursts:
//  - checks output values match what was sent
//  - checks that triggers are being produced correctly
//  - checks that dma_transfer_error produces the correct output when tlast
//      doesn't arrive on the right cycle (also implicitly checks that the
//      module can recover from this event without needing to be reset)
//  - tests behavior when sending start signal multiple times
//  - tests with a max-length frame
//  - tests with random-length frame
//  - tests with a random-length burst

`timescale 1ns/1ps

module awg_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT);

parameter int DEPTH = 256;

logic dac_reset;
logic dac_clk = 0;
localparam int DAC_CLK_RATE_HZ = 384_000_000;
always #(0.5s/DAC_CLK_RATE_HZ) dac_clk = ~dac_clk;

logic dma_reset;
logic dma_clk = 0;
localparam int DMA_CLK_RATE_HZ = 100_000_000;
always #(0.5s/DMA_CLK_RATE_HZ) dma_clk = ~dma_clk;

Axis_If #(.DWIDTH(tx_pkg::AXI_MM_WIDTH)) dma_data_in ();
Axis_If #(.DWIDTH($clog2(DEPTH)*tx_pkg::CHANNELS)) dma_write_depth ();
Axis_If #(.DWIDTH(2*tx_pkg::CHANNELS)) dma_trigger_out_config ();
Axis_If #(.DWIDTH(64*tx_pkg::CHANNELS)) dma_awg_burst_length ();
Axis_If #(.DWIDTH(2)) dma_awg_start_stop ();
Axis_If #(.DWIDTH(2)) dma_transfer_error ();

Realtime_Parallel_If #(.DWIDTH(tx_pkg::DATA_WIDTH), .CHANNELS(tx_pkg::CHANNELS)) dac_data_out ();
logic [tx_pkg::CHANNELS-1:0] dac_trigger;

awg_tb #(
  .DEPTH(DEPTH)
) tb_i (
  .dma_clk,
  .dma_data_in,
  .dma_write_depth,
  .dma_trigger_out_config,
  .dma_awg_burst_length,
  .dma_awg_start_stop,
  .dma_transfer_error,
  .dac_clk,
  .dac_trigger,
  .dac_data_out
);

awg #(
  .DEPTH(DEPTH)
) dut_i (
  .dma_clk,
  .dma_reset,
  .dma_data_in,
  .dma_write_depth,
  .dma_trigger_out_config,
  .dma_awg_burst_length,
  .dma_awg_start_stop,
  .dma_transfer_error,
  .dac_clk,
  .dac_reset,
  .dac_data_out,
  .dac_trigger
);

logic [tx_pkg::CHANNELS-1:0][$clog2(DEPTH)-1:0] write_depths;
logic [tx_pkg::CHANNELS-1:0][63:0] burst_lengths;
logic [tx_pkg::CHANNELS-1:0][1:0] trigger_modes;

initial begin
  debug.display("### TESTING ARBITRARY WAVEFORM GENERATOR ###", sim_util_pkg::DEFAULT);

  dac_reset <= 1'b1;
  dma_reset <= 1'b1;

  tb_i.init();

  repeat (100) @(posedge dma_clk);
  dma_reset <= 1'b0;
  @(posedge dac_clk);
  dac_reset <= 1'b0;

  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    write_depths[channel] = $urandom_range(1, DEPTH/2);
    burst_lengths[channel] = $urandom_range(1, 4);
    trigger_modes[channel] = $urandom_range(0, 2);
  end
  write_depths[0] = DEPTH - 1; // test max-depth
 
  for (int start_repeat_count = 0; start_repeat_count < 5; start_repeat_count += 1 + 2*start_repeat_count) begin
    for (int rand_valid = 0; rand_valid < 2; rand_valid++) begin
      for (int tlast_check = 0; tlast_check < 3; tlast_check++) begin
        debug.display($sformatf(
          "running test with start_repeat_count = %0d, tlast_check = %0d, rand_valid = %0d",
          start_repeat_count,
          tlast_check,
          rand_valid),
          sim_util_pkg::VERBOSE
        );
        // set registers to configure the DUT
        tb_i.configure_dut(
          debug,
          trigger_modes,
          burst_lengths,
          write_depths
        );

        // generate samples_to_send, use that to generate dma_words and
        // verify that it matches the desired samples_to_send
        tb_i.generate_samples(debug, write_depths);

        // send DMA data
        debug.display("sending samples over DMA", sim_util_pkg::DEBUG);
        tb_i.send_dma_data(rand_valid, tlast_check);
        debug.display("done sending samples over DMA", sim_util_pkg::DEBUG);

        // wait a few cycles to check for transfer error
        repeat (10) begin
          do @(posedge dma_clk); while (~dma_transfer_error.ready);
        end
        tb_i.check_transfer_error(debug, tlast_check);
        
        if (start_repeat_count == 0) begin
          // need to send stop signal to return to the IDLE state
          // otherwise the AWG will hang future DMA transactions
          tb_i.stop_dac(debug);
          @(posedge dma_clk);
        end else begin
          for (int i = 0; i < start_repeat_count; i++) begin
            tb_i.do_dac_burst(debug, write_depths, burst_lengths);
            if (tlast_check == 0) begin
              tb_i.check_output_data(debug, trigger_modes, write_depths, burst_lengths);
            end else begin
              debug.display($sformatf(
                "tlast_check = %0d, so not going to check output data since it will be garbage",
                tlast_check),
                sim_util_pkg::VERBOSE
              );
            end
            // clear receive queues
            tb_i.clear_receive_data();
          end
        end
        // clear send queues (outside of start_repeat_count loop so that we
        // keep track of the values the DAC is sending each iteration of the
        // loop)
        tb_i.clear_send_data();
      end
    end
  end
  debug.finish();
end

endmodule
