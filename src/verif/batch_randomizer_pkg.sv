// batch_randomizer_pkg.sv - Reed Foster
// constrained randomization of stimulus data

`timescale 1ns/1ps
package batch_randomizer_pkg;

  class BatchRandomizer #(
    parameter int SAMPLE_WIDTH = 16,
    parameter int PARALLEL_SAMPLES = 8,
    type sample_t=logic signed [SAMPLE_WIDTH-1:0]
  );
    rand sample_t data [PARALLEL_SAMPLES];
    sample_t max;
    sample_t min;

    constraint c_range {
      foreach (data[i]) {
        data[i] <= int'(max);
        data[i] >= int'(min);
      }
    }
  
    function new(
      input sample_t min,
      input sample_t max
    );
      this.min = min;
      this.max = max;
    endfunction
  
  endclass

endpackage
