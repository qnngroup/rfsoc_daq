// buffer.sv - Reed Foster
// adds capture and readout FSMs to buffer_core to reduce deadlocks due to
// stalled DMA transfers

`timescale 1ns/1ps
module buffer #(
) (
  // ADC clock, reset (512 MHz)
  input wire capture_clk, capture_reset,
  // data
  Realtime_Parallel_If.Slave capture_data,
  // configuration
  Axis_If.Slave capture_banking_mode,
  Axis_If.Slave capture_sw_arm_start_stop,
  Axis_If.Slave capture_sw_reset,
  Axis_If.Master capture_write_depth,
  input logic capture_hw_start,
  input logic capture_hw_stop,
  output logic capture_full,

  output logic [CHANNELS-1:0][$clog2(BUFFER_DEPTH+1)-1:0] capture_write_depth,
  input wire capture_sw_reset, // manual software/PS-triggered reset

  // Readout (PS) clock, reset (100 MHz)
  input wire readout_clk, readout_reset,
  Axis_If.Master readout_data,
  // 
  input wire readout_sw_reset,
  input wire readout_start


);
endmodule
