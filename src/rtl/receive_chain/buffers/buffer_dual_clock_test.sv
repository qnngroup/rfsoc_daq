// buffer_dual_clock_test.sv - Reed Foster

`timescale 1ns/1ps
module buffer_dual_clock_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT);

localparam int CHANNELS = 4;
localparam int BUFFER_DEPTH = 64;
localparam int DATA_WIDTH = 16;
localparam int READ_LATENCY = 4;

logic capture_reset;
logic capture_clk = 0;
localparam CAPTURE_CLK_RATE_HZ = 512_000_000;
always #(0.5s/CAPTURE_CLK_RATE_HZ) capture_clk = ~capture_clk;

logic readout_reset;
logic readout_clk = 0;
localparam READOUT_CLK_RATE_HZ = 100_000_000;
always #(0.5s/READOUT_CLK_RATE_HZ) readout_clk = ~readout_clk;

Realtime_Parallel_If #(.DWIDTH(DATA_WIDTH), .CHANNELS(CHANNELS)) capture_data ();
Axis_If #(.DWIDTH(DATA_WIDTH)) readout_data ();

logic [$clog2($clog2(CHANNELS)+1)-1:0] capture_banking_mode;
logic capture_start, capture_stop;
logic capture_full;

logic [CHANNELS-1:0][$clog2(BUFFER_DEPTH+1)-1:0] capture_write_depth;
logic capture_sw_reset;

logic readout_sw_reset;
logic readout_start;

buffer_dual_clock #(
  .CHANNELS(CHANNELS),
  .BUFFER_DEPTH(BUFFER_DEPTH),
  .DATA_WIDTH(DATA_WIDTH),
  .READ_LATENCY(READ_LATENCY)
) dut_i (
  .capture_clk,
  .capture_reset,
  .capture_data,
  .capture_banking_mode,
  .capture_start,
  .capture_stop,
  .capture_full,
  .capture_write_depth,
  .capture_sw_reset,
  .readout_clk,
  .readout_reset,
  .readout_data,
  .readout_sw_reset,
  .readout_start
);

logic capture_enabled;
logic readout_enabled;

logic [DATA_WIDTH-1:0] samples_sent [CHANNELS][$];
logic [DATA_WIDTH-1:0] samples_received [$];
int last_received;

always @(posedge capture_clk) begin
  capture_data.valid <= $urandom_range('0, {CHANNELS{1'b1}});
  if (capture_enabled) begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      if (capture_data.valid[channel]) begin
        capture_data.data[channel] <= $urandom_range(0, {DATA_WIDTH{1'b1}});
        samples_sent[channel].push_front(capture_data.data[channel]);
      end
    end
  end
end

always @(posedge readout_clk) begin
  if (readout_enabled) begin
    readout_data.ready <= $urandom_range(0, 1);
  end else begin
    readout_data.ready <= 1'b0;
  end
end

always @(posedge readout_clk) begin
  if (readout_reset) begin
    last_received <= 0;
  end else begin
    if (capture_start) begin
      last_received <= 0;
    end else begin
      if (readout_data.ok) begin
        samples_received.push_front(readout_data.data);
        if (readout_data.last) begin
          last_received <= samples_received.size();
        end
      end
    end
  end
end

task automatic check_write_depth (
  input logic [DATA_WIDTH-1:0] samples_sent [CHANNELS][$],
  input logic [CHANNELS-1:0][$clog2(BUFFER_DEPTH+1)-1:0] write_depths,
  input int banking_mode
);
  
  int total_write_depth;

  // make sure the write depths match up with the number of samples sent
  for (int channel = 0; channel < 1 << banking_mode; channel++) begin
    total_write_depth = 0;
    for (int bank = channel; bank < CHANNELS; bank += 1 << banking_mode) begin
      if (write_depths[bank][$clog2(BUFFER_DEPTH+1)-1]) begin
        // if MSB is set, then bank is full
        total_write_depth += BUFFER_DEPTH;
      end else begin
        total_write_depth += write_depths[bank];
      end
    end
    if (samples_sent[channel].size() !== total_write_depth) begin
      debug.error($sformatf(
        "channel %0d: sent %0d samples, but %0d were written",
        channel,
        samples_sent[channel].size(),
        total_write_depth)
      );
    end
  end

endtask

task automatic check_results (
  inout logic [DATA_WIDTH-1:0] samples_sent [CHANNELS][$],
  inout logic [DATA_WIDTH-1:0] samples_received [$],
  input int last_received,
  input int banking_mode
);
 
  // keep track of what sample we're on across multiple banks
  int sample_index;

  // make sure we got tlast at the right time
  if (last_received !== CHANNELS*BUFFER_DEPTH) begin
    debug.error($sformatf(
      "expected tlast event on cycle %0d, got it on %0d",
      CHANNELS*BUFFER_DEPTH,
      last_received)
    );
  end

  // make sure samples_received is the right size
  if (samples_received.size() !== CHANNELS*BUFFER_DEPTH) begin
    debug.error($sformatf(
      "expected to receive %0d samples, but got %0d",
      CHANNELS*BUFFER_DEPTH,
      samples_received.size())
    );
  end

  // check that the right data was received
  for (int bank = 0; bank < CHANNELS; bank++) begin
    for (int sample = 0; sample < BUFFER_DEPTH; sample++) begin
      sample_index = (bank / (1 << banking_mode)) * BUFFER_DEPTH + sample;
      if (sample_index < samples_sent[bank % (1 << banking_mode)].size()) begin
        if (samples_sent[bank % (1 << banking_mode)][$-sample_index] !== samples_received[$]) begin
          debug.error($sformatf(
            "channel %0d, bank %0d: sample mismatch, expected %x got %x",
            bank % (1 << banking_mode),
            bank,
            samples_sent[bank % (1 << banking_mode)][$-sample_index],
            samples_received[$])
          );
        end
      end
      samples_received.pop_back();
    end
  end

  // clean up extra samples
  for (int channel = 0; channel < CHANNELS; channel++) begin
    while (samples_sent[channel].size() > 0) samples_sent[channel].pop_back();
  end
  while (samples_received.size() > 0) samples_received.pop_back(); 

endtask

initial begin
  debug.display("### TESTING DUAL-CLOCK SAMPLE BUFFER ###", sim_util_pkg::DEFAULT);

  // assert resets
  readout_reset <= 1'b1;
  capture_reset <= 1'b1;

  // reset inputs to DUT
  readout_data.ready <= 1'b0;
  capture_banking_mode <= '0;
  capture_start <= 1'b0;
  capture_stop <= 1'b0;
  capture_sw_reset <= 1'b0;
  readout_sw_reset <= 1'b0;
  readout_start <= 1'b0;
  
  capture_enabled <= 1'b0;

  repeat (100) @(posedge readout_clk);
  readout_reset <= 1'b0;
  repeat (10) @(posedge capture_clk);
  capture_reset <= 1'b0;

  for (int test_readout_reset = 0; test_readout_reset < 2; test_readout_reset++) begin
    if (test_readout_reset == 0) begin
      debug.display("not asserting readout_sw_reset", sim_util_pkg::VERBOSE);
    end else begin
      debug.display("asserting readout_sw_reset", sim_util_pkg::VERBOSE);
    end
    for (int test_capture_reset = 0; test_capture_reset < 2; test_capture_reset++) begin
      if (test_capture_reset == 0) begin
        debug.display("not asserting capture_sw_reset", sim_util_pkg::VERBOSE);
      end else begin
        debug.display("asserting capture_sw_reset", sim_util_pkg::VERBOSE);
      end
      for (int sample_count_mode = 0; sample_count_mode < 2; sample_count_mode++) begin
        if (sample_count_mode == 0) begin
          debug.display("sending a few samples", sim_util_pkg::VERBOSE);
        end else begin
          debug.display("sending samples until full", sim_util_pkg::VERBOSE);
        end
        for (int banking_mode = 0; banking_mode <= $clog2(CHANNELS); banking_mode++) begin
          debug.display($sformatf("testing with banking_mode = %0d", banking_mode), sim_util_pkg::VERBOSE);
          // set the banking mode
          capture_banking_mode <= banking_mode;
          @(posedge capture_clk);
          for (int r = 0; r < ((test_capture_reset > 0) ? 2 : 1); r++) begin
            // start capture
            capture_start <= 1'b1;
            capture_enabled <= 1'b1;
            @(posedge capture_clk)
            capture_start <= 1'b0;
            if ((r == 0) & (test_capture_reset > 0)) begin
              repeat ($urandom_range(15, 45)) @(posedge capture_clk);
              capture_sw_reset <= 1'b1;
              @(posedge capture_clk);
              capture_sw_reset <= 1'b0;
              for (int channel = 0; channel < CHANNELS; channel++) begin
                while (samples_sent[channel].size() > 0) samples_sent[channel].pop_back();
              end
            end else begin
              // send samples
              // wait some amount of time
              debug.display("waiting for capture to complete", sim_util_pkg::DEBUG);
              if (sample_count_mode == 0) begin
                repeat ($urandom_range(5, 20)) @(posedge capture_clk);
                capture_stop <= 1'b1;
                capture_enabled <= 1'b0;
                @(posedge capture_clk);
                capture_stop <= 1'b0;
              end else begin
                while (capture_enabled) begin
                  for (int channel = 0; channel < 1 << banking_mode; channel++) begin
                    if (samples_sent[channel].size() == (BUFFER_DEPTH * (CHANNELS >> banking_mode))) begin
                      capture_enabled <= 1'b0;
                    end
                  end
                  @(posedge capture_clk);
                end
              end
            end
          end
          @(posedge readout_clk);
          for (int r = 0; r < ((test_readout_reset > 0) ? 2 : 1); r++) begin
            readout_start <= 1'b1;
            readout_enabled <= 1'b1;
            debug.display("waiting for readout to complete", sim_util_pkg::DEBUG);
            repeat (10) @(posedge readout_clk);
            // check capture_write_depth
            check_write_depth(samples_sent, capture_write_depth, banking_mode);
            if ((r == 0) & (test_readout_reset > 0)) begin
              repeat ($urandom_range(0, BUFFER_DEPTH*CHANNELS/2)) @(posedge readout_clk);
              readout_start <= 1'b0;
              readout_sw_reset <= 1'b1;
              @(posedge readout_clk);
              readout_sw_reset <= 1'b0;
              while (samples_received.size() > 0) samples_received.pop_back();
            end else begin
              while (~(readout_data.ok & readout_data.last)) @(posedge readout_clk);
              readout_start <= 1'b0;
              readout_enabled <= 1'b0;
              repeat (10) @(posedge readout_clk);
              check_results(samples_sent, samples_received, last_received, banking_mode);
            end
          end
        end
      end
    end
  end
  debug.finish();
end

endmodule
