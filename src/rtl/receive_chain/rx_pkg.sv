// rx_pkg.sv - Reed Foster
// parameterization of receive chain

`timescale 1ns/1ps

package rx_pkg;

  // main parameters
  localparam int CHANNELS = 8;
  localparam int SAMPLE_WIDTH = 16;
  localparam int RFDC_CLK_MHZ = 4096;
  localparam int PL_CLK_MHZ = 512;

  // derived parameters
  localparam int PARALLEL_SAMPLES = RFDC_CLK_MHZ/PL_CLK_MHZ; // = 8 for 4.096 GS/s @ 512 MHz
  localparam int DATA_WIDTH = PARALLEL_SAMPLES*SAMPLE_WIDTH;

  typedef logic signed [SAMPLE_WIDTH-1:0] sample_t;

endpackage
