`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module top_level(input wire clk,sys_rst,
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
                 output logic wresp_valid_out, rresp_valid_out,
                 output logic [`WD_BUS_WIDTH-1:0] rdata_packet,
                 output logic rdata_valid_out,
                 //DMA Inputs/Outputs (axi-stream)
                 input wire[`DMA_DATA_WIDTH-1:0] pwl_tdata,
                 input wire[3:0] pwl_tkeep,
                 input wire pwl_tlast, pwl_tvalid,
                 output logic pwl_tready,
                 //Sample Discriminator Config Inputs/Outputs (axi-stream)
                 output logic[`SDC_DATA_WIDTH-1:0] sdc_tdata,
                 output logic[3:0] sdc_tkeep,
                 output logic sdc_tlast, sdc_tvalid,
                 input wire sdc_tready,
                 //Buffer Config Inputs/Outputs (axi-stream)
                 output logic[`BUFF_CONFIG_WIDTH-1:0] buffc_tdata,
                 output logic[3:0] buffc_tkeep,
                 output logic buffc_tlast, buffc_tvalid,
                 input wire buffc_tready,
                 //Channel Mux Config Inputs/Outputs (axi-stream)
                 output logic[`CHANNEL_MUX_WIDTH-1:0] cmc_tdata,
                 output logic[3:0] cmc_tkeep,
                 output logic cmc_tlast, cmc_tvalid,
                 input wire cmc_tready,
                 //Buffer Timestamp Inputs/Outputs (axi-stream)
                 input wire[`BUFF_TIMESTAMP_WIDTH-1:0] bufft_tdata,
                 input wire[3:0] bufft_tkeep,
                 input wire bufft_tlast, bufft_tvalid,
                 output logic bufft_tready);

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

    assign bufft_if.data = bufft_tdata;
    assign bufft_if.valid = bufft_tvalid;
    assign bufft_if.last = bufft_tlast;
    assign bufft_tready = bufft_if.ready; 

    assign sdc_tdata =  sdc_if.data;  
    assign sdc_tvalid = sdc_if.valid;  
    assign sdc_tlast =  sdc_if.last;  
    assign sdc_tkeep = 1;
    assign sdc_if.ready = sdc_tready; 

    assign buffc_tdata =  buffc_if.data;  
    assign buffc_tvalid = buffc_if.valid;  
    assign buffc_tlast =  buffc_if.last;  
    assign buffc_tkeep = 1;
    assign buffc_if.ready = buffc_tready;

    assign cmc_tdata =  cmc_if.data;  
    assign cmc_tvalid = cmc_if.valid;  
    assign cmc_tlast =  cmc_if.last;  
    assign cmc_tkeep = 1;
    assign cmc_if.ready = cmc_tready;

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
    assign rresp_valid_out  = rr_if.valid_pack; 

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

    sys sys (.clk(clk), .sys_rst(sys_rst),
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
             
      sys_ILA sys_ILA (.clk(clk), 
                       .probe0(sys.rst),
                       .probe1(valid_dac_batch),
                       .probe2(waddr_packet),
                       .probe3(waddr_valid_packet),
                       .probe4(wdata_packet),
                       .probe5(wdata_valid_packet),
                       .probe6(pl_rstn),
                       .probe7(raddr_packet),
                       .probe8(raddr_valid_packet),
                       .probe9(rdata_packet),
                       .probe10(rdata_valid_out),
                       .probe11(ps_wresp_rdy),
                       .probe12(ps_read_rdy),
                       .probe13(wresp_out),
                       .probe14(rresp_out),
                       .probe15(sys.dac_intf.dacState),
                       .probe16(pwl_tdata),
                       .probe17(pwl_tvalid),
                       .probe18(pwl_tlast),
                       .probe19(pwl_tready),
                       .probe20(dac_batch),
                       .probe21(sys.dac_intf.pwl_gen.wave_bram_addr),
                       .probe22(sys.dac_intf.pwl_gen.wave_lines_stored),
                       .probe23(sys.dac_intf.pwl_gen.pwlState));
endmodule 

`default_nettype wire


//Thu  11/23: 8 hours
//Sat  11/24: 6 hours
//Mon  11/27: 9 hours (stopping at 4:18pm) + 9 hours (stopping at 5am)
//Tues 11/28: 7 hours
//Wed  11/29: 16 hours
//Thur 11/30: 1 hour
//Tue  12/5:  7 hours
//Wed  12/6:  3+12 hours
//Thur 12/7:  5 hours
//Fri  12/8:  18 hours
//Sat  12/9:  15 hours 
//Sun  12/10: 12 hours 
//Tues 12/19: 13 hours
//Wed  12/20: 19 hours

//Tues 12/26: 4 hours 
//Weds 12/27: 4 hours
//Thur 12/28: 8 hours
//Sat  1/6:   
//Sun  1/7:  
//Mon  1/8:   14 hours  
//Tues 1/9:   8 hours
//Wed  1/10:  7 hours
//Thur 1/11:  4 hours
//Fri  1/12:  7 hours
//Mon  1/15:  10 hours
//Tues 1/16:  7 hours

//Mon 1/22:  9 hours


//TODO: Almost ready to pull shit onto lab computer. Finish testing things here (wtf is going on with the memory?? And wresp stuff is wierd. Make sure all tests work and pass). 
//THen push to lab computer and pull. Then make sure firmware version is being printed correctly. Then figure out why the wave stored lines is 1028 and not 428 or something. 
//Do this by adding some probes BEFORE you run the bitstream. You got this. We got this.  