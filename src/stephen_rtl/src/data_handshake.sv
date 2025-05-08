`timescale 1ns / 1ps
`default_nettype none

module data_handshake #(parameter DATA_WIDTH = 32) 
		       (input wire src_clk,dst_clk,src_rst,
		        input wire[DATA_WIDTH-1:0] data_in,
		        input wire valid_in,
		        output logic[DATA_WIDTH-1:0] data_out,
		        output logic valid_out, 
		        output logic rdy,done);
	Axis_IF #(DATA_WIDTH) data_src();
    Axis_IF #(DATA_WIDTH) data_dst();

    enum logic[2:0] {FIRST_TRANSFER,IDLE_SRC,SEND_DATA,GET_ACK, RESET} srcState = IDLE_SRC;
    enum logic[1:0] {GET_DATA,SEND_ACK} dstState = GET_DATA;
    logic dst_rst; 
    logic ack_in = 0; 
    logic ack_out;
    logic valid_src_rst, valid_dst_rst; 
    logic src_rst_buff = 0;
    logic dst_rst_buff = 0;
    logic dst_rst_done, begin_first_transfer;

    assign rdy = srcState == IDLE_SRC && dstState == GET_DATA && ~src_rst_buff && ~dst_rst_buff;
    assign valid_src_rst = src_rst_buff && srcState == IDLE_SRC && ~src_rst; //src reset can be an arbitrary # of cycles. We know dst reset will be one though
    assign valid_dst_rst = dst_rst_buff && dstState == GET_DATA;

    pulse_CDC
    rst_CDC(.src_clk(src_clk), .dst_clk(dst_clk),
            .signal_in(valid_src_rst), .signal_out(dst_rst));
    pulse_CDC
    rst_done_CDC(.src_clk(dst_clk), .dst_clk(src_clk),
                 .signal_in(dst_rst_done), .signal_out(begin_first_transfer));
    pulse_CDC
    ack_CDC(.src_clk(dst_clk), .dst_clk(src_clk),
            .signal_in(ack_in), .signal_out(ack_out));

	data_CDC #(.DATA_WIDTH(DATA_WIDTH)) 
	data_CDC(.src_clk(src_clk), .src_reset(valid_src_rst),.src(data_src.stream_in),
	         .dest_clk(dst_clk),.dest_reset(valid_dst_rst),.dest(data_dst.stream_out));

    always_ff @(posedge src_clk) begin
    	if (valid_src_rst) begin
    		{done, data_src.data,data_src.valid,data_src.last} <= '0;
    		src_rst_buff <= 0; 
    		srcState <= FIRST_TRANSFER; 
    	end else begin
    		if (src_rst) src_rst_buff <= 1;
    		case(srcState) 
    			FIRST_TRANSFER: begin
    				if (begin_first_transfer) begin 
	    				{data_src.valid,data_src.last} <= 2;
	    				data_src.data <= 0; 
						srcState <= SEND_DATA;
					end 
    			end 
				IDLE_SRC: begin
					done <= 0; 
					if (valid_in) begin
						data_src.data <= data_in;
						{data_src.valid,data_src.last} <= 2;
						srcState <= SEND_DATA; 
					end
				end 
				SEND_DATA: begin
					if (data_src.ok) srcState <= GET_ACK;
				end
				GET_ACK: begin
					if (ack_out) begin
						done <= 1; 
						{data_src.valid,data_src.last} <= 3;
						srcState <= RESET;
					end
				end 
				RESET: begin
					srcState <= IDLE_SRC;
					{data_src.valid,data_src.last} <= 0;
					done <= 0; 
				end 
    		endcase
    	end
    end

    always_ff @(posedge dst_clk) begin
    	if (valid_dst_rst) begin
    		{ack_in,data_out,valid_out} <= '0;
    		dst_rst_buff <= 0;
    		dst_rst_done <= 1;
    		data_dst.ready <= 1;
    		dstState <= GET_DATA; 
    	end else begin
    		if (dst_rst) dst_rst_buff <= 1;
    		case(dstState) 
    			GET_DATA: begin
    				valid_out <= 0; 
    				dst_rst_done <= 0; 
		    		if (data_dst.valid) begin
		    			data_out <= data_dst.data; 
		    			ack_in <= 1; 		    		
		    			data_dst.ready <= 0;  
		    			dstState <= SEND_ACK; 
		    		end 
    			end 
    			SEND_ACK: begin
    				ack_in <= 0;
	    			valid_out <= 1; 
	    			data_dst.ready <= 1;
	    			dstState <= GET_DATA; 
    			end
    		endcase
    	end
    end

endmodule

`default_nettype wire