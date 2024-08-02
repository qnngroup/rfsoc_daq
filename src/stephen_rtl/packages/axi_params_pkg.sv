`ifndef AXI_PARAMS_PKG_SV
`define AXI_PARAMS_PKG_SV
    //REPLACE A_DATA and WD_DATA with ADDRW and DATAW
    package axi_params_pkg;
        localparam A_BUS_WIDTH     = 32;            // Bus width for axi addresses
        localparam A_DATA_WIDTH    = 32;            // Data width for axi addresses
        localparam WD_BUS_WIDTH    = 32;            // Bus width for axi data
        localparam WD_DATA_WIDTH   = 16;            // Data width for axi data
        localparam RESP_DATA_WIDTH = 2;             // Data width for axi write/read response data
        localparam ADDRW           = A_DATA_WIDTH;  // Shorthand
        localparam DATAW           = WD_DATA_WIDTH; // Shorthand
        // Codes for responses sent to processor 
        localparam OKAY   = 2'b00; // General signal for a successful transaction (or that an exclusive access failed)
        localparam EXOKAY = 2'b01; // Either the write OR read was okay
        localparam SLVERR = 2'b10; // Transaction recieved but error in execution
        localparam DECERR = 2'b11; // No slave at transaction address
    endpackage 

`endif
