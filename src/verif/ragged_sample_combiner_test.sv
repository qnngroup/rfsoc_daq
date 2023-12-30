// ragged_sample_combiner_test.sv - Reed Foster

import sim_util_pkg::*;

`timescale 1ns / 1ps
module ragged_sample_combiner_test ();

sim_util_pkg::debug #(.VERBOSITY(DEFAULT)) dbg = new; // printing, error tracking

initial begin
  dbg.finish();
end

endmodule
