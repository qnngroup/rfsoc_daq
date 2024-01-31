`timescale 1ns / 1ps
module signal_splitter(input m_axis_aclk, m0_axis_aclk,
			input M_AXIS_tvalid,
			output M_AXIS_tready,
			input[255:0] M_AXIS_tdata,
			output M0_AXIS_tvalid,
			input M0_AXIS_tready,
			output[255:0] M0_AXIS_tdata,
			output dacDomain_batch_valid);
	assign M0_AXIS_tvalid = M_AXIS_tvalid;
	assign M_AXIS_tready = M0_AXIS_tready;
	assign M0_AXIS_tdata = M_AXIS_tdata;
	assign dacDomain_batch_valid = M_AXIS_tvalid;


endmodule 
