// axis_width_converter_test.sv - Reed Foster
// Check that all Axis_If interface axi-stream resizer modules work correctly
// by saving all sent/received data and comparing each subword at the end of
// the test

import sim_util_pkg::*;

`timescale 1ns / 1ps
module axis_width_converter_test ();

sim_util_pkg::math #(int) math; // abs, max functions on ints
sim_util_pkg::debug debug = new(DEFAULT); // printing, error tracking

logic reset;
logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

localparam int DWIDTH_DOWN_IN = 256;
localparam int DWIDTH_UP_IN = 16;
localparam int DWIDTH_COMB_IN = 24;
localparam int DWIDTH_COMB_OUT = 32;
localparam int DOWN = 4;
localparam int UP = 8;

// these are needed for the test
localparam int COMB_UP = 4;
localparam int COMB_DOWN = 3;

// choose a standard datawidth for all of the DUTs that can fit the largest
// signal (input or output)
localparam int DWIDTH = math.max(math.max(math.max(DWIDTH_DOWN_IN, DWIDTH_UP_IN*UP), DWIDTH_COMB_OUT), DWIDTH_COMB_IN);

Axis_If #(.DWIDTH(DWIDTH_DOWN_IN)) downsizer_in ();
Axis_If #(.DWIDTH(DWIDTH_DOWN_IN/DOWN)) downsizer_out ();
Axis_If #(.DWIDTH(DWIDTH_UP_IN)) upsizer_in ();
Axis_If #(.DWIDTH(DWIDTH_UP_IN*UP)) upsizer_out ();
Axis_If #(.DWIDTH(DWIDTH_COMB_IN)) comb_in ();
Axis_If #(.DWIDTH(DWIDTH_COMB_OUT)) comb_out ();
Axis_If #(.DWIDTH(DWIDTH_COMB_IN)) nochange_comb_in ();
Axis_If #(.DWIDTH(DWIDTH_COMB_IN)) nochange_comb_out ();

axis_downsizer #(
  .DWIDTH(DWIDTH_DOWN_IN),
  .DOWN(DOWN)
) downsize_dut_i (
  .clk,
  .reset,
  .data_in(downsizer_in),
  .data_out(downsizer_out)
);

axis_upsizer #(
  .DWIDTH(DWIDTH_UP_IN),
  .UP(UP)
) upsize_dut_i (
  .clk,
  .reset,
  .data_in(upsizer_in),
  .data_out(upsizer_out)
);

axis_width_converter #(
  .DWIDTH_IN(DWIDTH_COMB_IN),
  .DWIDTH_OUT(DWIDTH_COMB_OUT)
) comb_dut_i (
  .clk,
  .reset,
  .data_in(comb_in),
  .data_out(comb_out)
);

axis_width_converter #(
  .DWIDTH_IN(DWIDTH_COMB_IN),
  .DWIDTH_OUT(DWIDTH_COMB_IN)
) nochange_comb_dut_i (
  .clk,
  .reset,
  .data_in(nochange_comb_in),
  .data_out(nochange_comb_out)
);

logic [DWIDTH-1:0] sent [4][$];
logic [DWIDTH-1:0] received [4][$];
int last_sent [4][$]; // size of sent whenever last is present
int last_received [4][$]; // size of received whenever last is present

logic [1:0][3:0][DWIDTH-1:0] data;
assign downsizer_in.data = data[0][0];
assign upsizer_in.data = data[0][1];
assign comb_in.data = data[0][2];
assign nochange_comb_in.data = data[0][3];
assign data[1][0] = downsizer_out.data;
assign data[1][1] = upsizer_out.data;
assign data[1][2] = comb_out.data;
assign data[1][3] = nochange_comb_out.data;

logic [1:0][3:0] ok;
assign ok[0][0] = downsizer_in.ok;
assign ok[0][1] = upsizer_in.ok;
assign ok[0][2] = comb_in.ok;
assign ok[0][3] = nochange_comb_in.ok;
assign ok[1][0] = downsizer_out.ok;
assign ok[1][1] = upsizer_out.ok;
assign ok[1][2] = comb_out.ok;
assign ok[1][3] = nochange_comb_out.ok;

logic [3:0] out_ready;
assign downsizer_out.ready = out_ready[0];
assign upsizer_out.ready = out_ready[1];
assign comb_out.ready = out_ready[2];
assign nochange_comb_out.ready = out_ready[3];

logic [3:0] in_valid;
assign downsizer_in.valid = in_valid[0];
assign upsizer_in.valid = in_valid[1];
assign comb_in.valid = in_valid[2];
assign nochange_comb_in.valid = in_valid[3];

logic [1:0][3:0] last;
assign downsizer_in.last = last[0][0];
assign upsizer_in.last = last[0][1];
assign comb_in.last = last[0][2];
assign nochange_comb_in.last = last[0][3];
assign last[1][0] = downsizer_out.last;
assign last[1][1] = upsizer_out.last;
assign last[1][2] = comb_out.last;
assign last[1][3] = nochange_comb_out.last;

localparam [1:0][3:0][31:0] NUM_WORDS = '{
  '{1, COMB_UP, UP, 1},      // output words
  '{1, COMB_DOWN, 1, DOWN}   // input words
};

localparam [3:0][31:0] WORD_SIZE = '{
  DWIDTH_COMB_IN,
  DWIDTH_COMB_IN/COMB_DOWN, // both
  DWIDTH_UP_IN,             // upsizer
  DWIDTH_DOWN_IN/DOWN       // downsizer
};

localparam MAX_WORD_SIZE = math.max(math.max(math.max(WORD_SIZE[0],WORD_SIZE[1]),WORD_SIZE[2]),WORD_SIZE[3]);
logic [MAX_WORD_SIZE-1:0] sent_word, received_word;

// update data and track sent/received samples
always_ff @(posedge clk) begin
  if (reset) begin
    data[1] <= '0;
  end else begin
    for (int dut = 0; dut < 4; dut++) begin // select which dut is active
      // inputs
      if (ok[0][dut]) begin
        for (int word = 0; word < DWIDTH/8; word++) begin
          data[0][dut][word*8+:8] <= $urandom_range(0,8'hff);
        end
        // save data that was sent, split up into individual "words"
        for (int word = 0; word < NUM_WORDS[0][dut]; word++) begin
          for (int i = 0; i < WORD_SIZE[dut]; i++) begin
            sent_word[i] = data[0][dut][word*WORD_SIZE[dut]+i];
          end
          sent[dut].push_front(sent_word & ((1 << WORD_SIZE[dut]) - 1));
        end
        if (last[0][dut]) begin
          last_sent[dut].push_front(sent[dut].size());
        end
      end
      // outputs
      if (ok[1][dut]) begin
        // save data that was received, split up into individual "words"
        for (int word = 0; word < NUM_WORDS[1][dut]; word++) begin
          for (int i = 0; i < WORD_SIZE[dut]; i++) begin
            received_word[i] = data[1][dut][word*WORD_SIZE[dut]+i];
          end
          received[dut].push_front(received_word & ((1 << WORD_SIZE[dut]) - 1));
        end
        if (last[1][dut]) begin
          last_received[dut].push_front(received[dut].size());
        end
      end
    end
  end
end

logic [3:0][1:0] readout_mode; // 0 for always 0, 1 for always 1, 2-3 for randomly toggling output ready signal

always_ff @(posedge clk) begin
  if (reset) begin
    out_ready <= '0;
  end else begin
    for (int dut = 0; dut < 4; dut++) begin
      unique case (readout_mode[dut])
        0: begin
          out_ready[dut] <= '0;
        end
        1: begin
          out_ready[dut] <= 1'b1;
        end
        2: begin
          out_ready[dut] <= $urandom() & 1'b1;
        end
      endcase
    end
  end
end

task check_dut(input int dut_select);
  int max_extra_samples;
  unique case (dut_select)
    0: begin
      debug.display("checking downsizer", VERBOSE);
      max_extra_samples = 0;
    end
    1: begin
      debug.display("checking upsizer", VERBOSE);
      max_extra_samples = UP - 1;
    end
    2: begin
      debug.display("checking combination up:down", VERBOSE);
      max_extra_samples = COMB_UP*COMB_DOWN - 1;
    end
    3: begin
      debug.display("checking nochange combination up:down (1:1)", VERBOSE);
      max_extra_samples = 0;
    end
  endcase
  debug.display($sformatf(
    "sent[%0d].size() = %0d",
    dut_select,
    sent[dut_select].size()),
    DEBUG
  );
  debug.display($sformatf(
    "received[%0d].size() = %0d",
    dut_select,
    received[dut_select].size()),
    DEBUG
  );
  debug.display($sformatf(
    "last_sent[%0d].size() = %0d",
    dut_select,
    last_sent[dut_select].size()),
    DEBUG
  );
  debug.display($sformatf(
    "last_received[%0d].size() = %0d",
    dut_select,
    last_received[dut_select].size()),
    DEBUG
  );
  while (last_sent[dut_select].size() > 0 && last_received[dut_select].size() > 0) begin
    debug.display($sformatf(
      "last_sent, last_received: %0d, %0d",
      last_sent[dut_select][$],
      last_received[dut_select][$]),
      DEBUG
    );
    last_sent[dut_select].pop_back();
    last_received[dut_select].pop_back();
  end
  // check we got the right amount of data
  if (received[dut_select].size() < sent[dut_select].size()) begin
    debug.error($sformatf(
      "mismatch in number of received/sent words, received fewer words than sent (received %d, sent %d)",
      received[dut_select].size(),
      sent[dut_select].size())
    );
  end
  if (received[dut_select].size() - sent[dut_select].size() > max_extra_samples) begin
    debug.error($sformatf(
      "mismatch in number of received/sent words, received %d more words than sent (received %d, sent %d)",
      received[dut_select].size() - sent[dut_select].size(),
      received[dut_select].size(),
      sent[dut_select].size())
    );
  end
  // remove invalid subwords if an incomplete word was sent at the end
  if (dut_select > 0) begin
    // do nothing for downsizer; it cannot have invalid subwords
    while (received[dut_select].size() > sent[dut_select].size()) begin
      received[dut_select].pop_front();
    end
  end

  // check data
  while (sent[dut_select].size() > 0 && received[dut_select].size() > 0) begin
    if (sent[dut_select][$] != received[dut_select][$]) begin
      debug.error($sformatf(
        "data mismatch error (received %x, sent %x)",
        received[dut_select][$],
        sent[dut_select][$])
      );
    end
    sent[dut_select].pop_back();
    received[dut_select].pop_back();
  end
endtask

// actually do the test
initial begin
  reset <= 1'b1;

  // reset input valid
  in_valid <= '0;
  // reset input last
  last[0] <= '0;
  // set readout mode to off for all DUTs(readout disabled)
  readout_mode <= '0;
  // reset input data
  data[0] <= '0;

  repeat (50) @(posedge clk);
  reset <= 1'b0;
  repeat (50) @(posedge clk);

  // do test
  for (int dut = 0; dut < 4; dut++) begin
    unique case (dut)
      0: debug.display("### TESTING AXIS DOWNSIZER ###", DEFAULT);
      1: debug.display("### TESTING AXIS UPSIZER ###", DEFAULT);
      2: debug.display("### TESTING AXIS COMBINED UPSIZER/DOWNSIZER ###", DEFAULT);
      3: debug.display("### TESTING AXIS COMBINED UPSIZER/DOWNSIZER WITH NO WIDTH CHANGE (I.E. 1:1) ###", DEFAULT);
    endcase
    repeat (50) begin
      for (int j = 1; j <= 2; j++) begin
        // cycle between continuously-high and randomly toggling ready signal on output interface 
        readout_mode[dut] <= j;
        unique case (dut)
          0: begin
            // send samples with random arrivals
            downsizer_in.send_samples(clk, $urandom_range(3,100), 1'b1, 1'b1, 1'b0);
            // send samples all at once
            downsizer_in.send_samples(clk, $urandom_range(3,100), 1'b0, 1'b1, 1'b0);
            // send samples with random arrivals
            downsizer_in.send_samples(clk, $urandom_range(3,100), 1'b1, 1'b1, 1'b0);
          end
          1: begin
            upsizer_in.send_samples(clk, $urandom_range(3,100), 1'b1, 1'b1, 1'b0);
            upsizer_in.send_samples(clk, $urandom_range(3,100), 1'b0, 1'b1, 1'b0);
            upsizer_in.send_samples(clk, $urandom_range(3,100), 1'b1, 1'b1, 1'b0);
          end
          2: begin
            comb_in.send_samples(clk, $urandom_range(3,100), 1'b1, 1'b1, 1'b0);
            comb_in.send_samples(clk, $urandom_range(3,100), 1'b0, 1'b1, 1'b0);
            comb_in.send_samples(clk, $urandom_range(3,100), 1'b1, 1'b1, 1'b0);
          end
          3: begin
            nochange_comb_in.send_samples(clk, $urandom_range(3,100), 1'b1, 1'b1, 1'b0);
            nochange_comb_in.send_samples(clk, $urandom_range(3,100), 1'b0, 1'b1, 1'b0);
            nochange_comb_in.send_samples(clk, $urandom_range(3,100), 1'b1, 1'b1, 1'b0);
          end
        endcase
        last[0][dut] <= 1'b1;
        in_valid[dut] <= 1'b1;
        // wait until last is actually registered by the DUT before deasserting it
        do begin @(posedge clk); end while (!ok[0][dut]);
        last[0][dut] <= 1'b0;
        in_valid[dut] <= 1'b0;

        // read out everything, waiting until last signal on DUT output
        do begin @(posedge clk); end while (!(last[1][dut] && ok[1][dut]));
        // check the output data matches the input
        check_dut(dut);
        repeat (100) @(posedge clk);
      end
    end
    // disable readout of DUT when finished
    readout_mode[dut] <= '0;
  end

  debug.finish();
end

endmodule
