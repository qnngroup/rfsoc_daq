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
				   input wire clr_rd_out, 
				   input wire[`MEM_SIZE-1:0] rtl_rdy, 
               	   input wire[`MEM_SIZE-1:0][WD_DATA_WIDTH-1:0] rtl_wd_in,
               	   output logic[`MEM_SIZE-1:0][WD_DATA_WIDTH-1:0] rtl_rd_out,
               	   output logic[`MEM_SIZE-1:0] fresh_bits);

    logic [`MEM_SIZE-1:0][WD_DATA_WIDTH-1:0] mem_map;			
    logic [`MEM_SIZE-1:0] rtl_read_reqs_full, rtl_write_reqs_full; 	  
	logic[A_DATA_WIDTH-1:0] windex_out, windex_out_raw, rindex_out;
	logic[WD_DATA_WIDTH-1:0] wdata_out, rdata_in; 
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
	assign is_readonly_addr = windex_out == `MAX_DAC_BURST_SIZE_ID || windex_out == `MEM_SIZE_ID || windex_out == `ABS_ID_CEILING || windex_out == `ABS_ID_CEILING-1 || (windex_out >= `ABS_ID_CEILING && windex_out < `MEM_TEST_BASE_ADDR); 
	assign can_ps_write = (ps_write_req && ~rtl_write_reqs_full[windex_out] && ~rtl_read_reqs_full[windex_out])? 1 : 0;
	assign can_ps_read = (ps_read_req && ~rtl_write_reqs_full[rindex_out] && ~rtl_read_reqs_full[rindex_out])? 1 : 0; 
	
	always_comb begin
		for (int i = 0; i < `MEM_SIZE; i++) begin
			if (`is_RTLPOLL(i)) begin
				rtl_read_reqs_full[i] = fresh_bits[i] && rtl_rdy[i]; 
				rtl_write_reqs_full[i] = 0; 
			end else if (`is_READONLY(i)) begin
				rtl_read_reqs_full[i] = rtl_read_reqs[i]; 
				rtl_write_reqs_full[i] = 0; 
			end else begin
				rtl_read_reqs_full[i] = rtl_read_reqs[i]; 
				rtl_write_reqs_full[i] = rtl_write_reqs[i];
			end 
		end
	end

	always_ff @(posedge clk) begin
		if (rst) begin 
			{fresh_bits,rtl_rd_out, wcomplete, rcomplete} <= 0;
			for (int i = 0; i < `MEM_SIZE; i++) begin
				if (i == `MAX_DAC_BURST_SIZE_ID) mem_map[i] <= `MAX_DAC_BURST_SIZE; 
				else if (i == `DAC_BURST_SIZE_ID) mem_map[i] <= 0; 
				else if (i == `SCALE_DAC_OUT_ID) mem_map[i] <= 0; 
				else if (`is_PS_VALID(i) || `is_RTL_VALID(i)) mem_map[i] <= 0;
				else if (i == `MEM_SIZE_ID) mem_map[i] <= `MEM_SIZE; 
				else if (i == `VERSION_ID) mem_map[i] <= `FIRMWARE_VERSION; 
				else if (i == `ABS_ID_CEILING) mem_map[i] <= -2; 
				else mem_map[i] <= -1; 				
			end 
		end else begin
			// Handler for internal system read and write requests (Prioritized over PS requests since those are buffered)
			for (integer i = 0; i < `MEM_SIZE; i++) begin
				if (rtl_write_reqs_full[i]) begin
					mem_map[i] <= rtl_wd_in[i];
					fresh_bits[i] <= 1;
				end else if (`is_PS_BIGREG(i) && `is_PS_VALID(i)) begin
					if (fresh_bits[i] && rtl_rdy[i]) mem_map[i] <= 0; 
				end
				if (clr_rd_out) rtl_rd_out[i] <= 0;
				else begin 
					if (rtl_read_reqs_full[i]) begin
						rtl_rd_out[i] <= mem_map[i];
						if (~rtl_write_reqs_full[i]) fresh_bits[i] <= 0; 
					end
				end 
			end

			if (can_ps_write) begin
				if (~(`is_READONLY(windex_out))) begin
					if (windex_out >= `MEM_TEST_BASE_ID && windex_out < `MEM_TEST_END_ADDR) begin
						mem_map[windex_out] <= wdata_out-10;
						fresh_bits[windex_out] <= 1; 
						if (windex_out != `MEM_TEST_END_ID-1) begin
							mem_map[windex_out+1] <= wdata_out+10;
							fresh_bits[windex_out+1] <= 1;
						end 
					end else 
					if (windex_out == `DAC_BURST_SIZE_ID) begin
						mem_map[windex_out] <= (wdata_out <= `MAX_DAC_BURST_SIZE)? wdata_out : `MAX_DAC_BURST_SIZE; 
						fresh_bits[windex_out] <= 1;
					end else 
					if (windex_out == `SCALE_DAC_OUT_ID) begin
						mem_map[windex_out] <= (wdata_out <= `MAX_SCALE_FACTOR)? wdata_out : `MAX_SCALE_FACTOR; 
						fresh_bits[windex_out] <= 1; 
					end
					else begin 
						mem_map[windex_out] <= wdata_out;
						fresh_bits[windex_out] <= 1; 
					end
				end 
				wcomplete <= 1;
			end	else wcomplete <= 0; 

			if (can_ps_read) begin 
				if (~`is_RTLPOLL(rindex_out)) fresh_bits[rindex_out] <= 0; 
				rcomplete <= 1; 
			end else rcomplete <= 0; 
		end
	end
	
endmodule 

`default_nettype wire
