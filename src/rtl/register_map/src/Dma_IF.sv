interface Dma_IF #(parameter BUS_WIDTH = 32, parameter DATA_WIDTH = 16);
    localparam DATA_PER_BUS = BUS_WIDTH/DATA_WIDTH; 
    logic[BUS_WIDTH-1:0] packet
    logic[DATA_PER_BUS-1:0][DATA_WIDTH-1:0] datas; 
    logic is_burst; 



   generate
        for (genvar i = 0; i < DATA_PER_BUS; i++) begin: data_splices
            data_splicer #(.DATA_WIDTH(BUS_WIDTH), .SPLICE_WIDTH(DATA_WIDTH))
            data_out_splice(.data(packet),
                            .i(int'(i)),
                            .spliced_data(datas[i]));
        end
    endgenerate

    logic 
    logic[BUS_WIDTH-1:0] packet;                // packet transmitted/recieved
    logic[DATA_WIDTH-1:0] data_to_send, data;   // data_to_send is for transmitting. data represents data received (I didn't call it received_data just cuz that long and its used alot)
    logic valid_pack, valid_data;               // valid_pack is high when a handshake happens between a transmitter and receiver. valid_data is high when a receiver is done grabbing packets for a given transaction
    logic dev_rdy, trans_rdy;                   // dev_rdy indicates to a transmitter whether the end point is ready to receive. trans_rdy indicates to the world whether the transmitter can transmit
    logic send;                                 // send orders the transmitter to transmit, if it is able to. 
    logic got_pack;                             // Indicates that a packet was just accepted
    logic sent_data;                            // Indicates that a transmission was allowed to begin 
        
    assign got_pack = valid_pack && dev_rdy; 
    assign sent_data = send && trans_rdy; 

    modport transmit_bus(input dev_rdy, data_to_send, send, output packet, valid_pack, trans_rdy);
    modport receive_bus (input valid_pack, packet, output data, valid_data); 
endinterface

