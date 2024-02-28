// buffer_pkg.sv - Reed Foster
// parameterization of buffer

`timescale 1ns/1ps

package buffer_pkg;

  // main parameters
  localparam int TSTAMP_BUFFER_DEPTH = 512;
  localparam int SAMPLE_BUFFER_DEPTH = 2048;
  localparam int TSTAMP_WIDTH = 64;

  // derived parameters
  localparam int SAMPLE_INDEX_WIDTH = $clog2(TSTAMP_BUFFER_DEPTH*rx_pkg::CHANNELS);
  localparam int CLOCK_WIDTH = TSTAMP_WIDTH - SAMPLE_INDEX_WIDTH;

endpackage
