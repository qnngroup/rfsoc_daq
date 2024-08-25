// realtime_differentiator.sv - Reed Foster
// computes first-order finite difference to approximate time derivative of
// input signal

`timescale 1ns/1ps
module realtime_differentiator #(
  parameter int SAMPLE_WIDTH = 16,
  parameter int PARALLEL_SAMPLES = 2,
  parameter int CHANNELS = 8
) (
  input wire clk, reset,
  Realtime_Parallel_If.Slave data_in,
  Realtime_Parallel_If.Master data_out
);

// register signals to infer DSP hardware subtractor
// can't do packed arrays because of signed type
logic signed [SAMPLE_WIDTH-1:0] data_in_reg [CHANNELS][PARALLEL_SAMPLES]; // 0Q16, 2Q14
// need to delay the last parallel sample so that we can use it in the next
// cycle for the finite difference with the first parallel sample
logic signed [SAMPLE_WIDTH-1:0] data_in_reg_d [CHANNELS]; // 0Q16, 2Q14
// register the output of the subtraction
logic signed [SAMPLE_WIDTH:0] diff [CHANNELS][PARALLEL_SAMPLES]; // 0Q16+0Q16 = 1Q16, 2Q14+2Q14 = 3Q14
// shift and truncate the subtraction result (probably don't really need to
// register this, but we don't care about latency too much)
logic signed [SAMPLE_WIDTH-1:0] diff_d [CHANNELS][PARALLEL_SAMPLES]; // 1Q15, 3Q13
// delay valid signal to match latency of DSP
logic [CHANNELS-1:0][2:0] valid_d;

always_ff @(posedge clk) begin
  if (reset) begin
    data_out.valid <= '0;
    valid_d <= '0;
    for (int channel = 0; channel < CHANNELS; channel++) begin
      data_in_reg_d[channel] <= '0;
      for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
        data_in_reg[channel][sample] <= '0;
      end
    end
  end else begin
    for (int channel = 0; channel < CHANNELS; channel++) begin
      if (data_in.valid[channel]) begin
        data_in_reg_d[channel] <= data_in_reg[channel][PARALLEL_SAMPLES-1]; // 0Q16, 2Q14
        for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
          data_in_reg[channel][sample] <= data_in.data[channel][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH]; // 0Q16, 2Q14
        end
        for (int sample = 0; sample < PARALLEL_SAMPLES; sample++) begin
          // for the 0th parallel sample, it's previous neighbor arrived in the
          // last clock cycle, so we need to use data_in_reg_d
          // otherwise, just subtract the sample-1th parallel sample
          diff[channel][sample] <= (SAMPLE_WIDTH+1)'(data_in_reg[channel][sample]) - ((sample == 0) ? (SAMPLE_WIDTH+1)'(data_in_reg_d[channel]) : (SAMPLE_WIDTH+1)'(data_in_reg[channel][sample-1])); // 1Q16
          // round and truncate
          diff_d[channel][sample] <= diff[channel][sample][SAMPLE_WIDTH-:SAMPLE_WIDTH]; // 1Q15
          data_out.data[channel][sample*SAMPLE_WIDTH+:SAMPLE_WIDTH] <= diff_d[channel][sample];
        end
        valid_d[channel] <= {valid_d[channel][1:0], 1'b1};
        data_out.valid[channel] <= valid_d[channel][2];
      end else begin
        data_out.valid[channel] <= 1'b0;
      end
    end
  end
end

endmodule
