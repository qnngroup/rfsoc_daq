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

//Mon  1/22:  9 hours

//Wed  1/31:  7 hours
//Thur 2/1:   6 hours
//Sat  2/3:   5 hours

//Mon  2/5:   7 hours
//Tues 2/6:   8 hours
//Wed  2/7:   9 hours
//Thur 2/8:   x hours



// WEEKLY UPDATES

/*
Mon:
    Finished code scraping. Got rid of lots of uncecessary signals and caught a few undefined ones. Removed all the warnings vivado was screaming at me about 
    (ignoring the unconsequential ones). Then I started the process of removing everything associated with the DAC ILA from the memory map. Had to go through
    a few parts of the project for that. After that, I've realized that my axi_slave test bench is actually really bad. It isn't set up the best because it was one 
    of my first test benches and I've developed lots of better ways of testing stuff. I've been wanting to redo most of my tests there for a while, but now I think I
    should do it asap because I'm realizing that we'll be making lots of changes to the memory map moving forwards, so it should be very easy to update my tests. Spent most
    of the day starting that process. I really hope to completely finish it tomorrow. 

Tues: 
    Fixed what would have been a problematic bug in the memory map definitions. Spent the whole day completely refactoring the slave_tb. Made really good progress, and fixed alot
    of useless/incorrect tests. Overall, the whole thing is much more comprehensible to me. Very nearly done, still buffing out some issues. Plan is to complete the bench asap very 
    early tomorrow before Reed gets in. Then, when he's here, we'll go over some the superconductivity meeting questions I have, LTspice work and how that might connect to my thesis,
    and finally a pwl discussion.

Wed: 
    Reed Meeting Notes: For timing tricks, varaible limits for loops and shifting == BAD, don't use inequalities unless you need to, don't reset signals that depend on other signals
    (valids, enables, lasts, etc). Finshed up the slave testbench reformat. Planning on working on a block diagram for the pwl module tonight or tomorrow morning to talk to Reed about.

Thurs:
    It's taken much longer than planned, but fully finished producing a stable version of the system. All tests have been finished and are passing. I then spent the rest of the morning
    working on a test suite that can be run on the hardware in real time, and fixing my simulated interface with the DAS to test the testbench. It should be capable of checking all
    the important aspects of my system, as well as run the DAC in an idle mode where it just switches between producing different waveform types (right now its just random samples and triangle waves).
    I plan on going into the lab and testing this at some point. 
*/


// SUPERCONDUCTING MEETING QUESTIONS

/*
2/6/24
    Terms: 
        1. JPL films
        2. Device constriction? Dpair current?
        3. What is a meander? 
        4. Transmission line "coupled to a resonator"
        5. Etched samples, dicing? 


    Questions:
    1. Alejandro: You're trying to find a way to figure out a fast method of measuring inductance 
    2. Why is measuring constriction vs Temperature important for infared detection?

*/

// TIMING TRICKS
/*
Variable limits for for loops and shifting == BAD
Counters: don't use inequalities unless u need to
If issues with high fannout rest, don't reset data signals. In general don't reset singals that depend (valids, enables etc, last )
*/