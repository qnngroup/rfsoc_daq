`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module axi_receive #(parameter BUS_WIDTH = 32, parameter DATA_WIDTH = 16)
          (input wire clk, rst,
           input wire is_addr,
           Recieve_Transmit_IF.receive_bus bus);

  enum logic{IDLE, RECEIVING} axiR_state;
  logic[DATA_WIDTH-1:0] buff;
  logic[`A_DATA_WIDTH-1:0] ps_addr_req; 
  logic[$clog2(`MEM_SIZE)-1:0] mem_id; 

  addr_to_id aTi (.addr(ps_addr_req),.mem_id(mem_id));
  assign ps_addr_req = buff; 
  assign bus.valid_data = (axiR_state == RECEIVING && ~bus.valid_pack);
  assign bus.data = (bus.valid_data)? ( (is_addr)? mem_id : buff ) : 0;
  
  always_ff @(posedge clk) begin
    if (rst) begin
      buff <= 0;
      axiR_state <= IDLE;
    end else begin
      case (axiR_state) 
        IDLE: begin
          if (bus.valid_pack) begin
            if (BUS_WIDTH >= DATA_WIDTH) buff <= bus.packet;
            else buff <= {buff[DATA_WIDTH-1-BUS_WIDTH:0],bus.packet}; 
            axiR_state <= RECEIVING;
          end
        end 

        RECEIVING: begin
          if (bus.valid_pack) begin
            if (BUS_WIDTH >= DATA_WIDTH) buff <= bus.packet;
            else buff <= {buff[DATA_WIDTH-1-BUS_WIDTH:0],bus.packet}; 
          end 
          else axiR_state <= IDLE;
        end 
      endcase 
    end
  end

endmodule 

module addr_to_id (input wire[`A_DATA_WIDTH-1:0] addr, output logic[$clog2(`MEM_SIZE)-1:0] mem_id);
  always_comb begin
    case(addr)
      `RST_ADDR             : mem_id = `RST_ID;
      `PS_SEED_BASE_ADDR       : mem_id = `PS_SEED_BASE_ID;
      `PS_SEED_VALID_ADDR      : mem_id = `PS_SEED_VALID_ID;
      `DAC_HLT_ADDR            : mem_id = `DAC_HLT_ID;
      `DAC_ILA_TRIG_ADDR       : mem_id = `DAC_ILA_TRIG_ID;
      `DAC_ILA_RESP_ADDR      : mem_id = `DAC_ILA_RESP_ID;
      `DAC_ILA_RESP_VALID_ADDR : mem_id = `DAC_ILA_RESP_VALID_ID;
      `TRIG_WAVE_ADDR      : mem_id = `TRIG_WAVE_ID; 
      `ILA_BURST_SIZE_ADDR     : mem_id = `ILA_BURST_SIZE_ID; 
      `MAX_BURST_SIZE_ADDR    : mem_id = `MAX_BURST_SIZE_ID;
      `SCALE_DAC_OUT_ADDR      : mem_id = `SCALE_DAC_OUT_ID;
      `DAC1_ADDR          : mem_id = `DAC1_ID;
      `DAC2_ADDR          : mem_id = `DAC2_ID;
      `PWL_PREP_ADDR        : mem_id = `PWL_PREP_ID;
      `RUN_PWL_ADDR        : mem_id = `RUN_PWL_ID;
      `MEM_SIZE_ADDR        : mem_id = `MEM_SIZE_ID; 
      `MEM_TEST_BASE_ADDR    : mem_id = `MEM_TEST_BASE_ID; 
      default: begin 
        if (addr > `PS_SEED_BASE_ADDR && addr < `PS_SEED_VALID_ADDR) mem_id = ( (-1*(`PS_SEED_BASE_ADDR - addr)) >> 2 ) + 1; 
        else if (addr > `MAPPED_ADDR_CEILING) mem_id = (addr - `PS_BASE_ADDR)/4;
        else mem_id = -1;
      end 
    endcase 
  end
endmodule 

`default_nettype wire
