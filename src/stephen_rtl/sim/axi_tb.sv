`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::*;

module axi_tb();
    `define A `MAX_BURST_SIZE_ADDR
    `define ID `MAX_BURST_SIZE_ID
    localparam WAIT_TIME = 100; 
    logic clk, rst; 
    logic [`A_BUS_WIDTH-1:0] waddr_packet, raddr_packet;
    logic [`WD_BUS_WIDTH-1:0] wdata_packet,transmitted_rdata;
    logic waddr_valid_in, raddr_valid_in, wdata_valid_in;
    logic rdata_valid_packet, wresp_valid_out;
    logic ps_read_rdy = 1;
    logic ps_wresp_rdy = 1; 
    logic[1:0] wresp_out, rresp_out; 
    logic [`MEM_SIZE-1:0] fresh_bits;
    logic [`MEM_SIZE-1:0] read_reqs;
    logic[`MEM_SIZE-1:0] rtl_write_reqs,rtl_read_reqs;
    logic [`MEM_SIZE-1:0][`WD_DATA_WIDTH-1:0] rtl_rd_out,rtl_wd_in;

    logic[`WD_DATA_WIDTH-1:0] wdata,sys_rdata,ps_rdata;
    logic[`A_DATA_WIDTH-1:0] waddr,raddr;
    logic waddr_send, wdata_send, raddr_send; 
    logic[$clog2(WAIT_TIME):0] timer; 

    axi_transmit  #(.BUS_WIDTH(`A_BUS_WIDTH), .DATA_WIDTH(`A_DATA_WIDTH)) 
    w_addr_ps_transmitter(.clk(clk), .rst(rst),
                          .data_to_send(waddr),
                          .send(waddr_send),
                          .device_rdy(1'b1),
                          .axi_packet(waddr_packet),
                          .valid_pack(waddr_valid_in));

    axi_transmit  #(.BUS_WIDTH(`WD_BUS_WIDTH), .DATA_WIDTH(`WD_DATA_WIDTH)) 
    w_data_ps_transmitter(.clk(clk), .rst(rst),
                          .data_to_send(wdata),
                          .send(wdata_send),
                          .device_rdy(1'b1),
                          .axi_packet(wdata_packet),
                          .valid_pack(wdata_valid_in));

    axi_transmit  #(.BUS_WIDTH(`A_BUS_WIDTH), .DATA_WIDTH(`A_DATA_WIDTH)) 
    r_addr_ps_transmitter(.clk(clk), .rst(rst),
                          .data_to_send(raddr),
                          .send(raddr_send),
                          .device_rdy(1'b1),
                          .axi_packet(raddr_packet),
                          .valid_pack(raddr_valid_in));

    axi_slave #(.A_BUS_WIDTH(`A_BUS_WIDTH), .A_DATA_WIDTH(`A_DATA_WIDTH), .WD_BUS_WIDTH(`WD_BUS_WIDTH), .WD_DATA_WIDTH(`WD_DATA_WIDTH))
    slave(.clk(clk), .rst(rst),
          .waddr_packet(waddr_packet), .waddr_valid_packet(waddr_valid_in),
          .raddr_packet(raddr_packet), .raddr_valid_packet(raddr_valid_in),
          .wdata_packet(wdata_packet), .wdata_valid_packet(wdata_valid_in),
          .ps_read_rdy(ps_read_rdy),
          .ps_wrsp_rdy(ps_wresp_rdy),
          .rtl_write_reqs (rtl_write_reqs),
          .rtl_read_reqs(rtl_read_reqs),
          .rtl_wd_in(rtl_wd_in),                        //in
          .rtl_rd_out(rtl_rd_out),                  //out 
          .fresh_bits(fresh_bits),
          .wresp_out(wresp_out), .rresp_out(rresp_out),
          .wresp_valid_out(wresp_valid_out),
          .rdata_packet(transmitted_rdata),
          .rdata_valid_packet(rdata_valid_packet));

    edetect id_ed (.clk(clk), .rst(rst),
                   .val(fresh_bits[`ID]),
                   .comb_posedge_out(freshBits_edge));
    always begin
        #5;  
        clk = !clk;
    end

    enum logic[2:0] {IDLE, TEST, WAIT_W, WAIT_R, READOUT,CONTINUE, STOP} testState;
    logic start;
    logic[7:0] test_num; 
    logic[$clog2(`MEM_SIZE)-1:0] sys_read_id; 
    logic[1:0] freshBits_edge; 
    logic id_wrote,id_read, ps_read,ps_wrote, rtl_wrote,rtl_read; 

    assign id_wrote = freshBits_edge == 1;
    assign id_read = freshBits_edge == 2; 

    always_ff @(posedge clk) begin
         if (rst) begin
           testState <= IDLE; 
           test_num <= 0; 
           {sys_rdata,ps_rdata} <= 0;
           {wdata_send, waddr_send, raddr_send} <= 0; 
           {rtl_write_reqs,rtl_read_reqs,rtl_wd_in} <= 0;
           {ps_read, ps_wrote, rtl_wrote, rtl_read} <= 0; 
           sys_read_id <= `ID;
           timer <= WAIT_TIME; 
        end else begin
            if (rdata_valid_packet) ps_rdata <= transmitted_rdata;
            if (test_num >= 17 && test_num <= 30) begin
                if (id_wrote && ~ps_wrote) ps_wrote <= 1; 
                if (id_read && ~rtl_read) rtl_read <= 1; 
            end

            if (test_num >= 31 && test_num <= 50) begin 
                if (id_wrote && ~rtl_wrote) rtl_wrote <= 1; 
                if (id_read && ~ps_read) ps_read <= 1; 
            end 

            case(testState) 
                IDLE: begin
                    if (start) begin
                        test_num <= 1; 
                        testState <= TEST; 
                    end 
                    else if (test_num) begin
                        test_num <= test_num + 1; 
                        testState <= TEST; 
                    end
                end 

                TEST: begin
                    if (test_num == 1) begin
                        waddr <= `A; 
                        wdata <= 123;
                        {wdata_send, waddr_send} <= 3; 
                        testState <= CONTINUE;  
                    end 
                    else if (test_num == 2) begin 
                        if (fresh_bits[`ID]) begin
                            raddr <= `A;  
                            raddr_send <= 1; 
                            testState <= CONTINUE;
                        end 
                    end 
                    else if (test_num == 3) begin 
                        rtl_read_reqs[`ID] <= 1;
                        rtl_write_reqs[`ID] <= 1;
                        rtl_wd_in[`ID] <= 321; 
                        sys_rdata <= 0;
                        testState <= CONTINUE; 
                    end 
                    else if (test_num == 4) begin
                        rtl_read_reqs[`ID] <= 1;
                        rtl_write_reqs[`ID] <= 1;
                        rtl_wd_in[`ID] <= 991; 
                        sys_rdata <= 0;
                        testState <= CONTINUE; 
                    end
                    else if (test_num == 5) begin
                        rtl_read_reqs[`ID] <= 1;
                        sys_rdata <= 0; 
                        testState <= CONTINUE; 
                    end
                    else if (test_num == 6) begin
                        waddr <= `A; 
                        wdata <= 555;
                        {wdata_send, waddr_send} <= 3; 
                        raddr <= `A; 
                        raddr_send <= 1;

                        rtl_read_reqs[`ID] <= 1;
                        sys_rdata <= 0; 
                        testState <= CONTINUE;  
                    end
                    else if (test_num == 7) begin
                        waddr <= `A-4; 
                        wdata <= 444;
                        {wdata_send, waddr_send} <= 3; 
                        raddr <= `A-4; 
                        raddr_send <= 1;

                        rtl_read_reqs[`ID-1] <= 1;
                        sys_rdata <= 0; 
                        testState <= CONTINUE;  
                    end
                    else if (test_num >= 8 && test_num <= 10) begin
                        raddr <= `A; 
                        raddr_send <= 1;

                        rtl_read_reqs[`ID-1] <= 1;
                        sys_read_id <= `ID-1; 
                        sys_rdata <= 0; 
                        testState <= CONTINUE;  
                    end
                    else if (test_num >= 11 && test_num <= 13) begin
                        raddr <= `A-4; 
                        raddr_send <= 1;

                        rtl_read_reqs[`ID] <= 1;
                        sys_read_id <= `ID;
                        sys_rdata <= 0; 
                        testState <= CONTINUE;  
                    end
                    else if (test_num == 14) begin
                        waddr <= `A;
                        wdata <= 341; 
                        {waddr_send, wdata_send} <= 3; 

                        rtl_write_reqs[`ID] <= 1; 
                        rtl_wd_in[`ID] <= 599;
                        testState <= CONTINUE;                     
                    end
                    else if (test_num == 15) begin
                        waddr <= `A;
                        wdata <= 654; 
                        {waddr_send, wdata_send} <= 3; 
                        raddr <= `A-4; 
                        raddr_send <= 1;

                        rtl_write_reqs[`ID] <= 1; 
                        rtl_wd_in[`ID] <= 3235;
                        rtl_write_reqs[`ID-1] <= 1; 
                        rtl_wd_in[`ID-1] <= 983;

                        rtl_read_reqs[`ID] <= 1;
                        sys_read_id <= `ID;
    
                        testState <= CONTINUE;                     
                    end
                    else if (test_num == 16) begin
                        rtl_read_reqs[`ID] <= 1;
                        sys_read_id <= `ID;
                        testState <= CONTINUE;                     
                    end
                    else if (test_num >= 17 && test_num <= 30) begin
                        if (rtl_read || test_num == 17) begin 
                            waddr <= `A;
                            wdata <= (test_num == 17)? 69 : wdata + 1; 
                            rtl_read <= 0; 
                            testState <= WAIT_W; 
                        end 
                        if(ps_wrote) begin
                            rtl_read_reqs[`ID] <= 1;
                            sys_read_id <= `ID;
                            ps_wrote <= 0;
                            testState <= CONTINUE; 
                        end 
                                             
                    end
                    else if (test_num >= 31 && test_num <= 50) begin
                        if (rtl_wrote) begin 
                            raddr <= `A;
                            rtl_wrote <= 0; 
                            testState <= WAIT_R; 
                        end 
                        if(ps_read || test_num == 31) begin
                            rtl_write_reqs[`ID] <= 1;
                            rtl_wd_in[`ID] <= rtl_wd_in[`ID]+1;
                            ps_read <= 0; 
                            testState <= CONTINUE;         
                        end 
                    end
                    else begin 
                        test_num <= 0; 
                        testState <= STOP; 
                    end 
                end 

                WAIT_W: begin
                    if (timer) timer <= timer - 1;
                    else begin
                        {waddr_send, wdata_send} <= 3;
                        timer <= WAIT_TIME; 
                        testState <= CONTINUE; 
                    end
                end 

                WAIT_R: begin
                    if (timer) timer <= timer - 1;
                    else begin
                        raddr_send <= 1; 
                        timer <= WAIT_TIME; 
                        testState <= CONTINUE; 
                    end
                end 

                CONTINUE: begin
                    {wdata_send, waddr_send, raddr_send} <= 0; 
                    {rtl_read_reqs[`ID],rtl_write_reqs[`ID],rtl_read_reqs[`ID-1],rtl_write_reqs[`ID-1]} <= 0;
                    testState <= READOUT; 
                end 

                READOUT: begin
                    sys_rdata <= rtl_rd_out[sys_read_id];
                    testState <= IDLE; 
                end 

                STOP: begin
                    {wdata_send, waddr_send, raddr_send} <= 0; 
                    {rtl_read_reqs[`ID],rtl_write_reqs[`ID]} <= 0;
                end 
            endcase 
        end
    end
    initial begin
        $dumpfile("axi_tb.vcd");
        $dumpvars(0,axi_tb);
        clk = 0;
        rst = 0; 
        start = 0;
        #50
        rst = 1; #10; rst = 0; #10;
        #100; start = 1;
        #10; start = 0; 
        while (testState != STOP) #10;
        #5000;
       $finish;
    end 

endmodule 

`default_nettype wire

