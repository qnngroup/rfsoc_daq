// awg_tb.sv - Reed Foster
// Utilities for testing the awg

`timescale 1ns/1ps
module awg_tb #(
  parameter int DEPTH = 1024
) (
  input logic dma_clk,

  Axis_If.Master dma_data_in,
  Axis_If.Master dma_write_depth,
  Axis_If.Master dma_trigger_out_config,
  Axis_If.Master dma_awg_burst_length,
  Axis_If.Master dma_awg_start_stop,
  Axis_If.Slave  dma_transfer_error,

  input logic dac_clk,
  input logic [tx_pkg::CHANNELS-1:0] dac_trigger,
  Realtime_Parallel_If.Slave dac_data_out
);

typedef logic signed [tx_pkg::SAMPLE_WIDTH-1:0] sample_t;
typedef logic [tx_pkg::AXI_MM_WIDTH-1:0] dma_batch_t;
typedef logic [tx_pkg::DATA_WIDTH-1:0] dac_batch_t;
sim_util_pkg::queue #(.T(sample_t), .T2(dma_batch_t)) dma_q_util = new;
sim_util_pkg::queue #(.T(sample_t), .T2(dac_batch_t)) dac_q_util = new;

sample_t samples_to_send [tx_pkg::CHANNELS][$];
dma_batch_t dma_words [$];
int trigger_arrivals [tx_pkg::CHANNELS][$];

task automatic clear_receive_data();
  dac_data_recv_i.clear_queues();
  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    while (trigger_arrivals[channel].size() > 0) trigger_arrivals[channel].pop_back();
  end
endtask

task automatic clear_send_data();
  while (dma_words.size() > 0) dma_words.pop_back();
  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    while (samples_to_send[channel].size() > 0) samples_to_send[channel].pop_back();
  end
endtask

axis_driver #(
  .DWIDTH(tx_pkg::AXI_MM_WIDTH)
) dma_data_i (
  .clk(dma_clk),
  .intf(dma_data_in)
);

axis_driver #(
  .DWIDTH($clog2(DEPTH)*tx_pkg::CHANNELS)
) dma_write_depth_i (
  .clk(dma_clk),
  .intf(dma_write_depth)
);

axis_driver #(
  .DWIDTH(2*tx_pkg::CHANNELS)
) dma_trigger_cfg_i (
  .clk(dma_clk),
  .intf(dma_trigger_out_config)
);

axis_driver #(
  .DWIDTH(64*tx_pkg::CHANNELS)
) dma_burst_length_i (
  .clk(dma_clk),
  .intf(dma_awg_burst_length)
);

axis_driver #(
  .DWIDTH(2)
) dma_start_stop_i (
  .clk(dma_clk),
  .intf(dma_awg_start_stop)
);

axis_receiver #(
  .DWIDTH(2)
) dma_transfer_error_i (
  .clk(dma_clk),
  .ready_rand(1'b1),
  .ready_en(1'b1),
  .intf(dma_transfer_error)
);

realtime_parallel_receiver #(
  .DWIDTH(tx_pkg::DATA_WIDTH),
  .CHANNELS(tx_pkg::CHANNELS)
) dac_data_recv_i (
  .clk(dac_clk),
  .intf(dac_data_out)
);

task automatic check_dma_words(
  inout sim_util_pkg::debug debug
);
  int samples;
  int words;
  int channel_offset;
  sample_t dma_samples [$];
  dma_batch_t words_temp [$];
  debug.display("checking dma input data", sim_util_pkg::DEBUG);
  debug.display($sformatf("dma_words.size() = %0d", dma_words.size()), sim_util_pkg::DEBUG);
  for (int c = 0; c < tx_pkg::CHANNELS; c++) begin
    debug.display($sformatf(
      "samples_to_send[%0d].size() = %0d",
      c,
      samples_to_send[c].size()),
      sim_util_pkg::DEBUG
    );
  end
  channel_offset = 0;
  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    samples = samples_to_send[channel].size();
    words = (samples*tx_pkg::SAMPLE_WIDTH)/tx_pkg::AXI_MM_WIDTH;
    if (dma_words.size() < (words + channel_offset)) begin
      debug.fatal("incorrect number of dma words");
    end
    for (int w = 0; w < words; w++) begin
      words_temp.push_front(dma_words[$-(channel_offset+w)]);
    end
    dma_q_util.samples_from_batches(
      words_temp,
      dma_samples,
      tx_pkg::SAMPLE_WIDTH,
      tx_pkg::AXI_MM_WIDTH/tx_pkg::SAMPLE_WIDTH
    );
    debug.display($sformatf("words_temp.size() = %0d", words_temp.size()), sim_util_pkg::DEBUG);
    debug.display($sformatf("dma_samples.size() = %0d", dma_samples.size()), sim_util_pkg::DEBUG);
    while (words_temp.size() > 0) words_temp.pop_back();
    // check queues
    dma_q_util.compare(debug, dma_samples, samples_to_send[channel]);
    channel_offset += words;
  end
  debug.display("done checking dma_words", sim_util_pkg::DEBUG);
endtask

task automatic check_output_data(
  inout sim_util_pkg::debug debug,
  input logic [tx_pkg::CHANNELS-1:0][1:0] trigger_modes,
  input logic [tx_pkg::CHANNELS-1:0][$clog2(DEPTH)-1:0] write_depths,
  input logic [tx_pkg::CHANNELS-1:0][63:0] burst_lengths
);
  sample_t recv_samples [$];
  int sample_count;
  int burst_count;
  int time_offset;
  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    sample_count = 0;
    burst_count = 0;
    time_offset = 0;
    debug.display($sformatf("checking output for channel %0d", channel), sim_util_pkg::VERBOSE);
    // trim zero samples from front and back
    while (dac_data_recv_i.data_q[channel][$] == '0) begin
      dac_data_recv_i.data_q[channel].pop_back();
      time_offset++;
    end
    while (dac_data_recv_i.data_q[channel][0] == '0) dac_data_recv_i.data_q[channel].pop_front();
    debug.display($sformatf("time_offset = %0d", time_offset), sim_util_pkg::DEBUG);
    dac_q_util.samples_from_batches(
      dac_data_recv_i.data_q[channel],
      recv_samples,
      tx_pkg::SAMPLE_WIDTH,
      tx_pkg::PARALLEL_SAMPLES
    );
    if (recv_samples.size()
        != (write_depths[channel]+1)*burst_lengths[channel]*tx_pkg::PARALLEL_SAMPLES) begin
      debug.error($sformatf(
        {
          "incorrect number of samples received on channel %0d.",
          "\nbased on write_depths*burst_lengths, expected %0d;",
          "\nbased on samples_to_send, expected %0d;",
          "\ngot %0d"
        },
        channel,
        (write_depths[channel]+1)*burst_lengths[channel]*tx_pkg::PARALLEL_SAMPLES,
        samples_to_send[channel].size(),
        recv_samples.size())
      );
    end
    while (recv_samples.size() > 0) begin
      if (recv_samples[$] !== samples_to_send[channel][$-sample_count]) begin
        debug.error($sformatf(
          "channel %0d: mismatch on sample %0d (burst %0d), sent %x, received %x",
          channel,
          sample_count,
          burst_count,
          samples_to_send[channel][$-sample_count],
          recv_samples[$])
        );
      end
      recv_samples.pop_back();
      if (sample_count == (write_depths[channel]+1)*tx_pkg::PARALLEL_SAMPLES - 1) begin
        burst_count = burst_count + 1;
      end
      sample_count = (sample_count + 1) % ((write_depths[channel]+1)*tx_pkg::PARALLEL_SAMPLES);
    end
    // check for correct timing of trigger signals
    case (trigger_modes[channel])
      0: burst_count = 0;
      1: burst_count = 1;
      2: burst_count = burst_lengths[channel];
    endcase
    // check we got the correct number of trigger events
    // should have burst_count trigger events,
    // at times k*(write_depths[channel]+1)*tx_pkg::PARALLEL_SAMPLES for
    // k = 0,1,2,...,burst_count
    if (trigger_arrivals[channel].size() != burst_count) begin
      debug.error($sformatf(
        "channel %0d: expected %0d triggers, but got %0d triggers",
        channel,
        burst_count,
        trigger_arrivals[channel].size())
      );
    end
    for (int frame = 0; frame < burst_count; frame++) begin
      if (trigger_arrivals[channel][frame] - time_offset !== frame*(write_depths[channel]+1)) begin
        debug.error($sformatf(
          "channel %0d: wrong trigger timing, got %0d, expected %0d",
          channel,
          trigger_arrivals[channel][frame] - time_offset,
          frame*(write_depths[channel]+1))
        );
      end
    end
  end
endtask

task automatic configure_dut(
  inout sim_util_pkg::debug debug,
  input logic [tx_pkg::CHANNELS-1:0][1:0] trigger_modes,
  input logic [tx_pkg::CHANNELS-1:0][63:0] burst_lengths,
  input logic [tx_pkg::CHANNELS-1:0][$clog2(DEPTH)-1:0] write_depths
);
  bit register_write_success;

  // update the trigger configuration
  dma_trigger_cfg_i.send_sample_with_timeout(10, trigger_modes, register_write_success);
  if (~register_write_success) begin
    debug.error("failed to update trigger configuration register");
  end
  // set the burst lengths
  dma_burst_length_i.send_sample_with_timeout(10, burst_lengths, register_write_success);
  if (~register_write_success) begin
    debug.error("failed to update burst length register");
  end
  // finally, update the write depth, which will put the DUT into a state
  // where it is ready to accept DMA data
  dma_write_depth_i.send_sample_with_timeout(10, write_depths, register_write_success);
  if (~register_write_success) begin
    debug.fatal("failed to update write_depth register; cannot proceed with DMA");
  end
endtask

task automatic generate_samples(
  inout sim_util_pkg::debug debug,
  input logic [tx_pkg::CHANNELS-1:0][$clog2(DEPTH)-1:0] write_depths
);
  logic [tx_pkg::AXI_MM_WIDTH-1:0] dma_word;

  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    for (int batch = 0; batch < write_depths[channel] + 1; batch++) begin
      for (int sample = 0; sample < tx_pkg::PARALLEL_SAMPLES; sample++) begin
        samples_to_send[channel].push_front($urandom_range(1,{tx_pkg::SAMPLE_WIDTH{1'b1}}));
      end
    end
  end

  // reform samples into tx_pkg::AXI_MM_WIDTH-wide words
  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    for (int word = 0; word < ((write_depths[channel]+1)*tx_pkg::DATA_WIDTH)/tx_pkg::AXI_MM_WIDTH; word++) begin
      dma_word = '0;
      for (int sample = 0; sample < tx_pkg::AXI_MM_WIDTH/tx_pkg::SAMPLE_WIDTH; sample++) begin
        dma_word = {samples_to_send[channel][$-(word*(tx_pkg::AXI_MM_WIDTH/tx_pkg::SAMPLE_WIDTH)+sample)],
                    dma_word[tx_pkg::AXI_MM_WIDTH-1:tx_pkg::SAMPLE_WIDTH]};
      end
      dma_words.push_front(dma_word);
    end
  end

  // check to make sure we actually send the right data to the AWG
  check_dma_words(debug);

  for (int i = 0; i < dma_words.size(); i++) begin
    debug.display($sformatf("dma_words[%0d] = %x", i, dma_words[$-i]), sim_util_pkg::DEBUG);
  end
endtask

task automatic send_dma_data (
  input bit rand_valid,
  input int tlast_check
);
  dma_data_i.send_queue(dma_words, (dma_words.size() / 4) * 2, rand_valid & 1'b1, 1'b1, 1'b0);
  if (tlast_check == 2) begin
    dma_data_i.send_last();
  end else begin
    dma_data_i.send_queue(dma_words, dma_words.size(), rand_valid & 1'b1, 1'b1, tlast_check == 0);
  end
endtask

task automatic check_transfer_error(
  inout sim_util_pkg::debug debug,
  input int tlast_check
);
  if (dma_transfer_error_i.last_q.size() != 1 || dma_transfer_error_i.data_q.size() != 1) begin
    debug.fatal($sformatf(
      "didn't get transfer error, last_q.size() = %0d data_q.size() = %0d",
      dma_transfer_error_i.last_q.size(),
      dma_transfer_error_i.data_q.size())
    );
  end
  // check data is correct
  if (dma_transfer_error_i.data_q[$] !== tlast_check) begin
    debug.error($sformatf(
      "expected transfer error code %0d, got error code %0d",
      tlast_check,
      dma_transfer_error_i.data_q[$])
    );
  end
  dma_transfer_error_i.clear_queues();
endtask

task automatic stop_dac(
  inout sim_util_pkg::debug debug
);
  bit register_write_success;
  dma_start_stop_i.send_sample_with_timeout(100, 2'b01, register_write_success);
  if (~register_write_success) begin
    debug.fatal("start/stop write timed out");
  end
endtask

task automatic do_dac_burst(
  inout sim_util_pkg::debug debug,
  input logic [tx_pkg::CHANNELS-1:0][$clog2(DEPTH)-1:0] write_depths,
  input logic [tx_pkg::CHANNELS-1:0][63:0] burst_lengths
);
  bit register_write_success;
  debug.display("running DAC burst", sim_util_pkg::DEBUG);
  // start outputting DMA data
  dma_start_stop_i.send_sample_with_timeout(100, 2'b10, register_write_success);
  if (~register_write_success) begin
    debug.fatal("start/stop write timed out");
  end
  debug.display("sent start command, waiting for DAC data to be valid", sim_util_pkg::DEBUG);
  
  // wait until we get data that's nonzero (we only send nonzero data so
  // it's easier to check this)
  // there should be a way to get the latency accurately, but it's kind of
  // annoying since the start signal has to cross clock domains
  do begin @(posedge dac_clk); end while (dac_data_out.valid !== '1);
  debug.display("waiting until dac_data_out.data is nonzero", sim_util_pkg::DEBUG);
  while (dac_data_out.data === '0) @(posedge dac_clk);
  // we have nonzero data now, so wait until all channels become inactive
  while (dac_data_out.data !== '0) begin
    for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
      // save trigger arrival if it happens
      if (dac_trigger[channel] === 1'b1) begin
        debug.display($sformatf(
          "got trigger on channel %0d for time %0d",
          channel,
          dac_data_recv_i.data_q[channel].size()),
          sim_util_pkg::DEBUG
        );
        trigger_arrivals[channel].push_back(dac_data_recv_i.data_q[channel].size());
      end
    end
    @(posedge dac_clk);
  end
  for (int channel = 0; channel < tx_pkg::CHANNELS; channel++) begin
    debug.display($sformatf(
      "trigger_arrivals[%0d].size() = %0d",
      channel,
      trigger_arrivals[channel].size()),
      sim_util_pkg::DEBUG
    );
  end
  debug.display("finished receiving data from dac_data_out", sim_util_pkg::DEBUG);
endtask

task automatic init();
  dma_data_i.init();
  dma_write_depth_i.init();
  dma_trigger_cfg_i.init();
  dma_burst_length_i.init();
  dma_start_stop_i.init();
endtask


endmodule
