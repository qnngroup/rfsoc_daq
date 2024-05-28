`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"
// import mem_layout_pkg::flash_signal;
module pwl_tb #(parameter BUS_WIDTH, parameter DATA_WIDTH, parameter DMA_DATA_WIDTH)
					   (input wire clk, rst,
					    Axis_IF dma);


	task automatic send_pwl_wave();
		//coords = [(0,0), (300,300), (450,1000), (150, 3000), (800,5800), (0, 6500)]
		bit[1:0] delay_timer;
		localparam BUFF_LEN = 21; 
		logic[BUFF_LEN-1:0][DMA_DATA_WIDTH-1:0] dma_buff;
		dma_buff = {48'd24, 48'd450971500552, 48'd3405909001569, 48'd3440268738576, 48'd3435973836816, 48'd3435973841057, 48'd3435973836828, 48'd3427383967748, 48'd678604899585, 48'd644245159952, 48'd644245094416, 48'd644245097761, 48'd644245094424, 48'd665719865352, 48'd1902670447169, 48'd1937030184976, 48'd1932735283216, 48'd1932735284257, 48'd1932735283228, 48'd1924145414148, 48'd66433}; 
		notify_dac(`RUN_PWL_ID); 
		for (int i = 0; i < BUFF_LEN; i++) begin
			dma.data <= dma_buff[i];
			delay_timer = $urandom_range(1,3);
			for (int j = 0; j < delay_timer; j++) @(posedge clk);
			dma.valid <= 1; 
			if (i == BUFF_LEN-1) dma.last <= 1;			
			@(posedge clk);
			while (~dma.ready) @(posedge clk); 
			{dma.valid,dma.last} <= 0;
		end
		// while (~dma.ready) @(posedge clk);
		// {dma.valid,dma.last} <= 0;
		// @(posedge clk);
	endtask  					   
	

endmodule 

`default_nettype wire

