`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module data_handshake #(parameter DATA_WIDTH = 32) 
						    (input wire clk_src,clk_dst,rst_src,rst_dst,
							 input wire[DATA_WIDTH-1:0] data_in,
							 input wire valid_in,
							 output logic[DATA_WIDTH-1:0] data_out,
							 output logic valid_out, 
							 output logic rdy,done);
	Axis_IF #(DATA_WIDTH) data_src();
    Axis_IF #(DATA_WIDTH) data_dst();

    Axis_IF #(DATA_WIDTH) ack_src();
    Axis_IF #(DATA_WIDTH) ack_dst();
    enum logic[1:0] {IDLE_SRC,SEND_DATA,GET_ACK, ERROR} srcState;
    enum logic[1:0] {GET_DATA,SEND_ACK} dstState;

    assign rdy = srcState == IDLE_SRC;
    assign data_dst.ready = 1; 
    assign ack_dst.ready = 1; 


	data_CDC #(.DATA_WIDTH(DATA_WIDTH)) 
           data_CDC(.src_clk(clk_src), .src_reset(rst_src),.src(data_src.stream_in),
                    .dest_clk(clk_dst),.dest_reset(rst_dst),.dest(data_dst.stream_out));
	
	data_CDC #(.DATA_WIDTH(DATA_WIDTH)) 
           ack_CDC(.src_clk(clk_dst), .src_reset(rst_dst),.src(ack_src.stream_in),
                   .dest_clk(clk_src),.dest_reset(rst_src),.dest(ack_dst.stream_out));  

    always_ff @(posedge clk_src) begin
    	if (rst_src) begin
    		{done, data_src.data,data_src.valid,data_src.last} <= 0;
    		srcState <= IDLE_SRC; 
    	end else begin
    		case(srcState) 
				IDLE_SRC: begin
					done <= 0; 
					if (valid_in) begin
						data_src.data <= data_in;
						{data_src.valid,data_src.last} <= 3; 
						srcState <= SEND_DATA; 
					end
				end 
				SEND_DATA: begin
					if (data_src.ok) begin
						srcState <= GET_ACK;
					end
				end
				GET_ACK: begin
					if (ack_dst.valid) begin
						done <= 1; 
						srcState <= (ack_dst.data == 1)? IDLE_SRC : ERROR;
						{data_src.valid,data_src.last} <= 0;
					end
				end 
    		endcase
    	end
    end




    always_ff @(posedge clk_dst) begin
    	if (rst_dst) begin
    		{ack_src.data,ack_src.valid,ack_src.last} <= 0;
    		dstState <= GET_DATA; 
    	end else begin
    		case(dstState) 
    			GET_DATA: begin
    				valid_out <= 0; 
		    		if (data_dst.valid) begin
		    			data_out <= data_dst.data; 
		    			ack_src.data <= 1; 
		    			{ack_src.valid, ack_src.last} <= 3; 
		    			dstState <= SEND_ACK; 
		    		end 
    			end 

    			SEND_ACK: begin
    				if (ack_src.ok) begin
    					{ack_src.valid, ack_src.last} <= 0; 
		    			valid_out <= 1; 
		    			dstState <= GET_DATA; 
    				end
    			end
    		endcase
    	end
    end

endmodule

`default_nettype wire