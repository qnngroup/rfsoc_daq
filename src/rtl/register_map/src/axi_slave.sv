`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module axi_slave #(parameter A_BUS_WIDTH=2, parameter A_DATA_WIDTH=5, parameter WD_BUS_WIDTH=8, parameter WD_DATA_WIDTH=32)
				  (input wire clk, rst,
				   Recieve_Transmit_IF waddr_if,
				   Recieve_Transmit_IF wdata_if,
				   Recieve_Transmit_IF raddr_if,
				   Recieve_Transmit_IF rdata_if,
				   Recieve_Transmit_IF wresp_if,
				   Recieve_Transmit_IF rresp_if, 
				   input wire[`MEM_SIZE-1:0] rtl_write_reqs, rtl_read_reqs,
               	   input wire[`MEM_SIZE-1:0][WD_DATA_WIDTH-1:0] rtl_wd_in,
               	   output logic[`MEM_SIZE-1:0][WD_DATA_WIDTH-1:0] rtl_rd_out,
               	   output logic[`MEM_SIZE-1:0] fresh_bits);

    logic [`MEM_SIZE-1:0][WD_DATA_WIDTH-1:0] mem_map;				  
	logic[A_DATA_WIDTH-1:0] windex_out, windex_out_raw, rindex_out;
	logic[WD_DATA_WIDTH-1:0] wdata_out, rdata_in; 
	logic transmit_wrsp_rdy,transmit_rdata_rdy;
	logic wcomplete, rcomplete;
	logic can_ps_write, can_ps_read, is_readonly_addr;
	logic ps_write_req,ps_read_req; 

	assign rresp_if.packet = `OKAY; 
	assign rresp_if.valid_pack = can_ps_read; 

	axi_receive #(.BUS_WIDTH(A_BUS_WIDTH), .DATA_WIDTH(A_DATA_WIDTH)) 
	waddr_recieve(.clk(clk), .rst(rst),
				   .bus(waddr_if.receive_bus),
                   .is_addr(1'b1)); 
	axi_receive #(.BUS_WIDTH(WD_BUS_WIDTH), .DATA_WIDTH(WD_DATA_WIDTH)) 
	wdata_recieve(.clk(clk), .rst(rst),
				   .bus(wdata_if.receive_bus),
                   .is_addr(1'b0)); 
	axi_receive #(.BUS_WIDTH(A_BUS_WIDTH), .DATA_WIDTH(A_DATA_WIDTH)) 
	raddr_recieve(.clk(clk), .rst(rst),
				   .bus(raddr_if.receive_bus),
                   .is_addr(1'b1)); 
	axi_transmit #(.BUS_WIDTH(WD_BUS_WIDTH), .DATA_WIDTH(WD_DATA_WIDTH))
	rdata_transmit(.clk(clk), .rst(rst),
	              .bus(rdata_if.transmit_bus));
	axi_transmit #(.BUS_WIDTH(2), .DATA_WIDTH(2))
	wresp_transmit(.clk(clk), .rst(rst),
	              .bus(wresp_if.transmit_bus));


	ps_reqhandler ps_rh(.clk(clk), .rst(rst),
					    .have_windex(waddr_if.valid_data), .have_wdata(wdata_if.valid_data),
					    .have_rdata(raddr_if.valid_data),
					    .rdata_in(rdata_in), .rindex_in(raddr_if.data),
					    .wdata_in(wdata_if.data), .windex_in(waddr_if.data),
					    .transmit_wrsp_rdy(wresp_if.trans_rdy), .transmit_rdata_rdy(rdata_if.trans_rdy),
					    .rcomplete(rcomplete), .wcomplete(wcomplete),					//in
					    .rdata_out(rdata_if.data_to_send), .rindex_out(rindex_out),
					    .wdata_out(wdata_out), .windex_out(windex_out_raw),
					    .wresp(wresp_if.data_to_send),
					    .transmit_wresp(wresp_if.send),
					    .transmit_rdata(rdata_if.send),
					    .ps_read_req(ps_read_req),
					    .ps_write_req(ps_write_req));

	assign windex_out = (windex_out_raw > `ABS_ID_CEILING)? `ABS_ID_CEILING : windex_out_raw; 
	assign rdata_in = (raddr_if.valid_data)? mem_map[raddr_if.data] : 0;
	assign is_readonly_addr = windex_out == `MAX_BURST_SIZE_ID || windex_out == `MEM_SIZE_ID || windex_out == `ABS_ID_CEILING || windex_out == `ABS_ID_CEILING-1 || (windex_out >= `ABS_ID_CEILING && windex_out < `MEM_TEST_BASE_ADDR); 
	assign can_ps_write = (ps_write_req && ~rtl_write_reqs[windex_out] && ~rtl_read_reqs[windex_out])? 1 : 0;
	assign can_ps_read = (ps_read_req && ~rtl_write_reqs[rindex_out] && ~rtl_read_reqs[rindex_out])? 1 : 0; 

	always_ff @(posedge clk) begin
		if (rst) begin 
			{fresh_bits,rtl_rd_out, wcomplete, rcomplete} <= 0;
			for (int i = 0; i < `MEM_SIZE; i++) begin
				if (i == `MAX_BURST_SIZE_ID) mem_map[i] <= `MAX_ILA_BURST_SIZE; 
				else if (i == `MEM_SIZE_ID) mem_map[i] <= `MEM_SIZE; 
				else if (i == `ABS_ID_CEILING) mem_map[i] <= -1; 
				else mem_map[i] <= 0; 				
			end 
		end else begin
			// Handler for internal system read and write requests (Prioritized over PS requests since those are buffered)
			for (integer i = 0; i < `MEM_SIZE; i++) begin
				if (rtl_write_reqs[i] && ~is_readonly_addr) begin
					mem_map[i] <= rtl_wd_in[i];
					fresh_bits[i] <= 1;
				end
				if (rtl_read_reqs[i]) begin
					rtl_rd_out[i] <= mem_map[i];
					if (~rtl_write_reqs[i]) fresh_bits[i] <= 0; 
				end
			end

			if (can_ps_write) begin
				if (~is_readonly_addr) begin
					if (windex_out >= `MEM_TEST_BASE_ADDR) begin
						mem_map[windex_out] <= wdata_out-10;
						fresh_bits[windex_out] <= 1; 
						mem_map[windex_out+1] <= wdata_out+10;
						fresh_bits[windex_out+1] <= 1; 
					end else begin 
						mem_map[windex_out] <= wdata_out;
						fresh_bits[windex_out] <= 1; 
					end
				end 
				wcomplete <= 1;
			end	else wcomplete <= 0; 

			if (can_ps_read) begin 
				fresh_bits[rindex_out] <= 0; 
				rcomplete <= 1; 
			end else rcomplete <= 0; 
		end
	end
	
endmodule 

`default_nettype wire
