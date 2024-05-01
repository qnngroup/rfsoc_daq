`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module top_level(input wire ps_clk,ps_rst, dac_clk, dac_rst,
                 //Inputs from DAC
                 input wire dac0_rdy,
                 //Outpus to DAC
                 output logic[`BATCH_WIDTH-1:0] dac_batch, 
                 output logic valid_dac_batch, 
                 output logic pl_rstn, 
                 //Inputs from PS
                 input wire [`A_BUS_WIDTH-1:0] raddr_packet,
                 input wire raddr_valid_packet,
                 input wire [`A_BUS_WIDTH-1:0] waddr_packet,
                 input wire waddr_valid_packet,
                 input wire [`WD_BUS_WIDTH-1:0] wdata_packet,
                 input wire wdata_valid_packet,
                 input wire ps_wresp_rdy,ps_read_rdy,
                 //axi_slave Outputs
                 output logic [1:0] wresp_out,rresp_out,
                 output logic wresp_valid_out,
                 output logic [`WD_BUS_WIDTH-1:0] rdata_packet,
                 output logic rdata_valid_out,
                 //DMA Inputs/Outputs (axi-stream)
                 input wire[`DMA_DATA_WIDTH-1:0] pwl_tdata,
                 input wire pwl_tlast, pwl_tvalid,
                 output logic pwl_tready);

    Recieve_Transmit_IF #(`A_BUS_WIDTH, `A_DATA_WIDTH)   wa_if (); 
    Recieve_Transmit_IF #(`WD_BUS_WIDTH, `WD_DATA_WIDTH) wd_if (); 
    Recieve_Transmit_IF #(`A_BUS_WIDTH, `A_DATA_WIDTH)   ra_if (); 
    Recieve_Transmit_IF #(`WD_BUS_WIDTH, `WD_DATA_WIDTH) rd_if (); 
    Recieve_Transmit_IF #(2,2) wr_if (); 
    Recieve_Transmit_IF #(2,2) rr_if ();



    Axis_IF #(`BUFF_TIMESTAMP_WIDTH) bufft_if(); 
    Axis_IF #(`BUFF_CONFIG_WIDTH) buffc_if();
    Axis_IF #(`DMA_DATA_WIDTH) pwl_dma_if();
    Axis_IF #(`CHANNEL_MUX_WIDTH) cmc_if();
    Axis_IF #(`SDC_DATA_WIDTH) sdc_if();


    assign pwl_dma_if.data = pwl_tdata;
    assign pwl_dma_if.valid = pwl_tvalid;
    assign pwl_dma_if.last = pwl_tlast;
    assign pwl_tready = pwl_dma_if.ready; 

    assign {bufft_if.data, bufft_if.valid, bufft_if.last} = 0; //Swap with Reed's out signals when he needs them.
    assign bufft_if.ready = 1; 

    assign sdc_if.ready = 1;   //Swap with Reed's in signals when he needs them
    assign buffc_if.ready = 1; //Swap with Reed's in signals when he needs them
    assign cmc_if.ready = 1;   //Swap with Reed's in signals when he needs them

    assign ra_if.packet     = raddr_packet;
    assign ra_if.valid_pack = raddr_valid_packet;
    assign wa_if.packet     = waddr_packet;
    assign wa_if.valid_pack = waddr_valid_packet;
    assign wd_if.packet     = wdata_packet;
    assign wd_if.valid_pack = wdata_valid_packet;
    assign rd_if.dev_rdy    = ps_read_rdy; 
    assign wr_if.dev_rdy    = ps_wresp_rdy; 

    assign rdata_packet     = rd_if.packet; 
    assign rdata_valid_out  = rd_if.valid_pack;    
    assign wresp_out        = wr_if.packet; 
    assign wresp_valid_out  = wr_if.valid_pack; 
    assign rresp_out        = rr_if.packet;

    // Receive interfaces don't need transmit signals
    assign {wa_if.data_to_send, wa_if.send, wa_if.trans_rdy, wa_if.dev_rdy} = 0;
    assign {wd_if.data_to_send, wd_if.send, wd_if.trans_rdy, wd_if.dev_rdy} = 0;
    assign {ra_if.data_to_send, ra_if.send, ra_if.trans_rdy, ra_if.dev_rdy} = 0;
    assign {ra_if.data_to_send, ra_if.send, ra_if.trans_rdy, ra_if.dev_rdy} = 0;

    // Transmit interfaces don't need receive signals 
    assign {rd_if.data, rd_if.valid_data} = 0;
    assign {wr_if.data, wr_if.valid_data} = 0;
    assign {rr_if.data, rr_if.valid_data} = 0;
    
    // All of these signals don't apply to read response since a transmitter module doesn't handle setting the packet and valid_packet field: its set directly in the slave module. 
    assign {rr_if.dev_rdy, rr_if.data_to_send, rr_if.send, rr_if.trans_rdy} = 0; 

   sys sys (.ps_clk(ps_clk), .ps_rst(ps_rst), .dac_clk(dac_clk), .dac_rst(dac_rst),
            .dac0_rdy(dac0_rdy),
            .dac_batch(dac_batch),
            .valid_dac_batch(valid_dac_batch),
            .pl_rstn(pl_rstn),
            .wa_if(wa_if),
            .wd_if(wd_if),
            .ra_if(ra_if),
            .rd_if(rd_if),
            .wr_if(wr_if),
            .rr_if(rr_if),
            .pwl_dma_if(pwl_dma_if),
            .bufft_if(bufft_if),
            .buffc_if(buffc_if),
            .cmc_if(cmc_if),
            .sdc_if(sdc_if)); 
    
//       sys_ILA sys_ILA (.clk(ps_clk), 
//                        .probe0(sys.rst),
//                        .probe1(sys.hlt_counter),
//                        .probe2(waddr_packet),
//                        .probe3(waddr_valid_packet),
//                        .probe4(wdata_packet),
//                        .probe5(wdata_valid_packet),
//                        .probe6(pl_rstn),
//                        .probe7(raddr_packet),
//                        .probe8(raddr_valid_packet),
//                        .probe9(rdata_packet),
//                        .probe10(rdata_valid_out),
//                        .probe11(ps_wresp_rdy),
//                        .probe12(ps_read_rdy),
//                        .probe13(wresp_out),
//                        .probe14(rresp_out),
//                        .probe15(sys.dac_intf.dacConfigState),
//                        .probe16(sys.dac_intf.ps_cmd_in),
//                        .probe17(sys.dac_intf.seed_set),
//                        .probe18(sys.dac_intf.state_rdy),
//                        .probe19(sys.dac_intf.fresh_bits),
//                        .probe20(sys.ps_rst),
//                        .probe21(sys.rst_cmd),
//                        .probe22(sys.rstState));
                        
//        dac_ILA dac_ILA (.clk(dac_clk), 
//                        .probe0(dac_rst),
//                        .probe1(valid_dac_batch),
//                        .probe2(pwl_tdata),
//                        .probe3(pwl_tvalid),
//                        .probe4(pwl_tlast),
//                        .probe5(pwl_tready),
//                        .probe6(dac_batch),
// //                        .probe7(dac0_rdy),
// //                        .probe8(dac0_rdy),
// //                        .probe9(dac0_rdy));            
//                        .probe7(sys.dac_intf.sample_gen.run_shift_regs),
//                        .probe8(sys.dac_intf.sample_gen.run_trig_wav),
//                        .probe9(sys.dac_intf.sample_gen.run_pwl));            
                        
                       
                       
endmodule 

`default_nettype wire

// WEEKLY UPDATES

/*
Weekly updates:
Mon-Wedensday:
    Working out bugs with the c algorithm. Found some pointer issues, fixed some memory leaks. Currently working to develop a testing suite for the cython module
 TODO: 
    5 streams of work: 
    1. PWL Hardware testing (basically just make the pathway from python to pwl_wave on a scope work)
    2. PWL updating: Increase the dma width to allow for larger slopes then introduce fractional slopes
    3. System-wide changes (parameters, testbenches, etc). Prepare the codebase for integration with reed
    4. DAQ system user interface rehaul: Ontop of the cli, introduce a server interface. Allow for GPIB connections to arbitrary lab equipment.
    5. Shadow more experiments to familiarize yourself with the process your tool will be applied in.
*/
