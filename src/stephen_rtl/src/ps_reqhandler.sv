`timescale 1ns / 1ps
`default_nettype none

module ps_reqhandler #(parameter ADDRW, DATAW, REQ_BUFFER_SZ)
					 (input wire clk, rst,
					  input wire have_windex, have_wdata, have_rdata,
					  input wire[DATAW-1:0] rdata_in, wdata_in,
					  input wire[ADDRW-1:0] windex_in, rindex_in, 
					  input wire transmit_wrsp_rdy, transmit_rdata_rdy,
					  input wire wcomplete, rcomplete, 
					  output logic[DATAW-1:0] rdata_out, wdata_out,
					  output logic[ADDRW-1:0] windex_out, rindex_out, 
					  output logic[1:0] wresp, 
					  output logic transmit_wresp, transmit_rdata,
					  output logic ps_read_req, ps_write_req); 

	enum logic[1:0] {IDLE, REQUEST, SEND} wrespTransmitState, rdataTransmitState;
	logic[$clog2(REQ_BUFFER_SZ):0] ps_wd_buffptr, ps_wi_buffptr, ps_rd_buffptr;     // write and read buffer pointers
	logic[$clog2(REQ_BUFFER_SZ):0] ps_wreq_num, ps_rreq_num; 
	logic[REQ_BUFFER_SZ-1:0][DATAW-1:0] ps_wdbuff, ps_rdbuff;              // write and read data buffers  
	logic[REQ_BUFFER_SZ-1:0][ADDRW-1:0] ps_wibuff, ps_ribuff;               // write and read address buffer  	
	// Setting all output signals for writing recieved wdata and requesting r/w
	always_comb begin
		wdata_out = (ps_wreq_num > 0)? ps_wdbuff[ps_wd_buffptr-1] : '0;
		windex_out = (ps_wreq_num > 0)? ps_wibuff[ps_wi_buffptr-1] : '0;
		ps_write_req =  (wcomplete)? 0 : wrespTransmitState == REQUEST;

		rdata_out = (ps_rreq_num > 0)? ps_rdbuff[ps_rd_buffptr-1] : '0;
		rindex_out = (ps_rreq_num > 0)? ps_ribuff[ps_rd_buffptr-1] : '0;
		ps_read_req = (rcomplete)? 0 : rdataTransmitState == REQUEST;
	end

	// Manages the buffering of r/w data/addrs, as well as necessary axi signals for wresp and rdata transmission 
	always_ff @(posedge clk) begin
		if (rst) begin
			{ps_rd_buffptr,ps_wi_buffptr,ps_wd_buffptr} <= '0; 
			{ps_wdbuff, ps_rdbuff, ps_wibuff, ps_ribuff} <= '0;
			{ps_wreq_num, ps_rreq_num} <= '0;
			{transmit_rdata, transmit_wresp, wresp} <= 0; 
			wrespTransmitState <= IDLE; 
			rdataTransmitState <= IDLE; 
		end else begin
			// Buffer and handle writes
			if (have_windex && ps_wi_buffptr < REQ_BUFFER_SZ) begin
				ps_wi_buffptr <= ps_wi_buffptr + 1; 
				ps_wibuff[ps_wi_buffptr] <= windex_in;
			end
			if (have_wdata && ps_wd_buffptr < REQ_BUFFER_SZ) begin
				ps_wd_buffptr <= ps_wd_buffptr + 1; 
				ps_wdbuff[ps_wd_buffptr] <= wdata_in;
				ps_wreq_num <= ps_wreq_num + 1; 
			end
			case(wrespTransmitState)
				IDLE: begin
					if (ps_wreq_num > 0 && ps_wd_buffptr == ps_wi_buffptr && {have_windex, have_wdata} == 2'd0) begin
						wrespTransmitState <= REQUEST; 						
					end 
				end 
				REQUEST: begin
					if (wcomplete) begin // Means internal mem has recorded the write
						ps_wd_buffptr <= ps_wd_buffptr - 1; 
						ps_wdbuff[ps_wd_buffptr] <= '1; 
						ps_wi_buffptr <= ps_wi_buffptr - 1; 
						ps_wibuff[ps_wi_buffptr] <= '1;
						ps_wreq_num <= ps_wreq_num - 1;
						transmit_wresp <= 1; 
						wresp <= (windex_out <= mem_layout_pkg::MEM_SIZE)? axi_params_pkg::OKAY : axi_params_pkg::SLVERR; 
						wrespTransmitState <= SEND;	
					end
				end 
				SEND: begin 
					if (transmit_wrsp_rdy) begin
						transmit_wresp <= 0;
						wrespTransmitState <= IDLE;						
					end 
				end  
			endcase 

			// Buffer and handle reads
			if (have_rdata && ps_rd_buffptr < REQ_BUFFER_SZ) begin
				ps_rd_buffptr <= ps_rd_buffptr + 1;  
				ps_rdbuff[ps_rd_buffptr] <= rdata_in;
				ps_ribuff[ps_rd_buffptr] <= rindex_in; 
				ps_rreq_num <= ps_rreq_num + 1; 
			end 
			case(rdataTransmitState) 
				IDLE: begin
					if (ps_rreq_num > 0 && ~have_rdata) rdataTransmitState <= REQUEST;
				end 
				REQUEST: begin
					if (rcomplete) begin
						transmit_rdata <= 1; 
						rdataTransmitState <= SEND; 
					end
				end 
				SEND: begin
					if (transmit_rdata_rdy) begin 
						ps_rd_buffptr <= ps_rd_buffptr - 1;
						ps_rdbuff[ps_rd_buffptr] <= '1; 
						ps_rreq_num <= ps_rreq_num - 1; 
						transmit_rdata <= 0; 
						rdataTransmitState <= IDLE; 
					end 
				end 
			endcase
		end
	end
endmodule 

`default_nettype wire

