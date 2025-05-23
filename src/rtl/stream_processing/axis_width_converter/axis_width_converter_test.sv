// axis_width_converter_test.sv - Reed Foster
// Check that all Axis_If interface axi-stream resizer modules work correctly
// by saving all sent/received data and comparing each subword at the end of
// the test

`timescale 1ns / 1ps
module axis_width_converter_test ();

sim_util_pkg::math #(int) math; // abs, max functions on ints
sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT); // printing, error tracking

logic reset;
logic clk = 0;
localparam int CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

localparam int DWIDTH_IN = 24;
localparam int N_DOWN = 2;
localparam int N_UP = 2;
localparam int DOWN [N_DOWN] = {3,1};
localparam int UP [N_UP] = {2,1};

logic [N_DOWN-1:0][N_UP-1:0] start, done;

initial begin
  start <= '0;
  for (int down = 0; down < N_DOWN; down++) begin
    for (int up = 0; up < N_UP; up++) begin
      // mid-test reset
      reset <= 1'b1;
      repeat (100) @(posedge clk);
      reset <= 1'b0;
      start[down][up] <= 1'b1;
      @(posedge clk);
      start <= '0;
      do begin @(posedge clk); end while (~done[down][up]);
      @(posedge clk);
    end
  end
  debug.finish();
end

generate
  for (genvar down = 0; down < N_DOWN; down++) begin: gen_down
    for (genvar up = 0; up < N_UP; up++) begin: gen_up
      localparam int DWIDTH_OUT = (DWIDTH_IN*UP[up])/DOWN[down];
      Axis_If #(.DWIDTH(DWIDTH_IN)) data_in ();
      Axis_If #(.DWIDTH(DWIDTH_OUT)) data_out ();
      axis_width_converter #(
        .DWIDTH_IN(DWIDTH_IN),
        .DWIDTH_OUT(DWIDTH_OUT)
      ) dut_i (
        .clk,
        .reset,
        .data_in,
        .data_out
      );

      logic ready_rand, ready_en;

      axis_driver #(
        .DWIDTH(DWIDTH_IN)
      ) driver_i (
        .clk,
        .intf(data_in)
      );

      axis_receiver #(
        .DWIDTH(DWIDTH_OUT)
      ) receiver_i (
        .clk,
        .ready_rand(ready_rand),
        .ready_en(ready_en),
        .intf(data_out)
      );

      localparam int MAX_EXTRA_SAMPLES = UP[up]*DOWN[down]-1;
      localparam int WORD_SIZE = DWIDTH_IN/DOWN[down];

      typedef logic [WORD_SIZE-1:0] sample_t;
      typedef logic [DWIDTH_IN-1:0] in_t;
      typedef logic [DWIDTH_OUT-1:0] out_t;
      sim_util_pkg::queue #(.T(sample_t), .T2(in_t)) in_q_util = new;
      sim_util_pkg::queue #(.T(sample_t), .T2(out_t)) out_q_util = new;

      sample_t sent_q [$];
      sample_t recv_q [$];

      initial begin
        done[down][up] <= 1'b0;
        ready_en <= 1'b0;
        ready_rand <= 1'b0;
        driver_i.init(); // reset data, last, valid
        do begin @(posedge clk); end while (start[down][up] !== 1'b1);
        @(posedge clk);
        // do test
        debug.display($sformatf(
          "### TESTING AXIS WIDTH CONVERTER u = %0d, d = %0d ###",
          UP[up],
          DOWN[down]),
          sim_util_pkg::DEFAULT
        );
        ready_en <= 1'b1;
        for (int i = 0; i < 2; i++) begin
          ready_rand <= i;
          // send samples with random arrivals
          driver_i.send_samples($urandom_range(3,100), 1'b1, 1'b1);
          // send samples all at once
          driver_i.send_samples($urandom_range(3,100), 1'b0, 1'b1);
          // send samples with random arrivals
          driver_i.send_samples($urandom_range(3,100), 1'b1, 1'b1);
          // send last signal
          driver_i.send_last();
          do begin @(posedge clk); end while (~(data_out.last & data_out.valid & data_out.ready));
          // check the output data matches the input
          repeat (100) @(posedge clk);
          debug.display($sformatf(
            "checking results for up = %0d, down = %0d, ready_rand = %0d",
            UP[up],
            DOWN[down],
            i),
            sim_util_pkg::VERBOSE
          );
          // make sure last_q has one element equal to data_q.size()
          if (receiver_i.last_q.size() !== 1) begin
            debug.error($sformatf(
              "expected 1 tlast event, got %0d",
              receiver_i.last_q.size())
            );
          end else begin
            if (receiver_i.last_q[$] !== receiver_i.data_q.size()) begin
              debug.error($sformatf(
                "got last at the wrong time, got %0d but have %0d samples",
                receiver_i.last_q[$],
                receiver_i.data_q.size())
              );
            end
          end
          out_q_util.samples_from_batches(receiver_i.data_q, recv_q, WORD_SIZE, UP[up]);
          in_q_util.samples_from_batches(driver_i.data_q, sent_q, WORD_SIZE, DOWN[down]);
          // check we got the right number of samples
          if ((recv_q.size() < sent_q.size())
              || (recv_q.size() - sent_q.size() > MAX_EXTRA_SAMPLES)) begin
            debug.error($sformatf(
              "received incorrect number of samples, sent %0d got %0d (MAX_EXTRA = %0d)",
              sent_q.size(),
              recv_q.size(),
              MAX_EXTRA_SAMPLES)
            );
          end
          // remove invalid subwords if an incomplete word was sent at the end
          while (recv_q.size() > sent_q.size()) begin
            recv_q.pop_front();
          end
          in_q_util.compare(debug, recv_q, sent_q);
          // clear queues
          driver_i.clear_queues();
          receiver_i.clear_queues();
          while (recv_q.size() > 0) recv_q.pop_back();
          while (sent_q.size() > 0) sent_q.pop_back();
        end
        repeat (10) @(posedge clk);
        done[down][up] <= 1'b1;
      end
    end
  end
endgenerate

endmodule
