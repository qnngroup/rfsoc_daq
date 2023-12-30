module ps_reqhandler (input wire clk, rst,
            input wire have_windex, have_wdata, have_rdata,
            input wire[`WD_DATA_WIDTH-1:0] rdata_in, wdata_in,
            input wire[`A_DATA_WIDTH-1:0] windex_in, rindex_in, 
            input wire transmit_wrsp_rdy, transmit_rdata_rdy,
            input wire wcomplete, rcomplete, 
            output logic[`WD_DATA_WIDTH-1:0] rdata_out, wdata_out,
            output logic[`A_DATA_WIDTH-1:0] windex_out, rindex_out, 
            output logic[1:0] wresp, 
            output logic transmit_wresp, transmit_rdata,
            output logic ps_read_req, ps_write_req); 

  enum logic {IDLE, SEND} wrespTransmitState, rdataTransmitState;
  logic[$clog2(`REQ_BUFFER_SZ):0] ps_wd_buffptr, ps_wi_buffptr, ps_rd_buffptr;     // write and read buffer pointers
  logic[`REQ_BUFFER_SZ-1:0][`WD_DATA_WIDTH-1:0] ps_wdbuff, ps_rdbuff;              // write and read data buffers  
  logic[`REQ_BUFFER_SZ-1:0][`A_DATA_WIDTH-1:0] ps_wibuff, ps_ribuff;               // write and read address buffer    

  // Setting all output signals for transmitting rdata/wresp, writing recieved wdata, and requesting r/w
  always_comb begin
    wdata_out = (ps_wd_buffptr < `REQ_BUFFER_SZ)? ps_wdbuff[ps_wd_buffptr] : 0;
    windex_out = (ps_wi_buffptr < `REQ_BUFFER_SZ)? ps_wibuff[ps_wi_buffptr] : 0; 
    ps_write_req = (ps_wd_buffptr < `REQ_BUFFER_SZ  && ps_wi_buffptr < `REQ_BUFFER_SZ && ps_wd_buffptr == ps_wi_buffptr && wrespTransmitState == IDLE && ~wcomplete)? 1 : 0; 

    if (ps_rd_buffptr < `REQ_BUFFER_SZ) begin
      rdata_out = ps_rdbuff[ps_rd_buffptr];
      rindex_out = ps_ribuff[ps_rd_buffptr]; 
      ps_read_req = (rdataTransmitState == IDLE && ~rcomplete)? 1 : 0; 
    end else {rdata_out, rindex_out, ps_read_req} = 0; 

    case(rdataTransmitState)
      IDLE: transmit_rdata = 0; 
      SEND: transmit_rdata = (transmit_rdata_rdy)? 1 : 0; 
      default: transmit_rdata = 0;
    endcase

    wresp = (windex_out <= `MEM_SIZE)? `OKAY : `SLVERR; 
    case(wrespTransmitState)
      IDLE: transmit_wresp = 0; 
      SEND: transmit_wresp = (transmit_wrsp_rdy)? 1 : 0; 
      default: transmit_wresp = 0; 
    endcase 
  end

  // Manages the buffering of r/w data/addrs, as well as necessary axi signals for wresp and rdata transmission 
  always_ff @(posedge clk) begin
    if (rst) begin
      {ps_rd_buffptr,ps_wi_buffptr,ps_wd_buffptr} <= -1; 
      {ps_wdbuff, ps_rdbuff, ps_wibuff, ps_ribuff} <= 0; 
      wrespTransmitState <= IDLE; 
      rdataTransmitState <= IDLE; 
    end else begin
      // Buffer and handle writes
      if (have_windex) begin
        ps_wi_buffptr <= ps_wi_buffptr + 1; 
        ps_wibuff[(ps_wi_buffptr+1)%(`REQ_BUFFER_SZ)] <= windex_in;
      end
      if (have_wdata) begin
        ps_wd_buffptr <= ps_wd_buffptr + 1; 
        ps_wdbuff[(ps_wd_buffptr+1)%(`REQ_BUFFER_SZ)] <= wdata_in;
      end
      case(wrespTransmitState)
        IDLE: begin
          if (wcomplete) wrespTransmitState <= SEND; // Means internal mem has recorded the write
        end 
        SEND: begin 
          if (transmit_wrsp_rdy && ~have_wdata && ~have_windex && ps_wd_buffptr == ps_wi_buffptr) begin
            ps_wd_buffptr <= ps_wd_buffptr - 1; 
            ps_wdbuff[ps_wd_buffptr] <= -1; 
            ps_wi_buffptr <= ps_wi_buffptr - 1; 
            ps_wibuff[ps_wi_buffptr] <= -1;
            wrespTransmitState <= IDLE;
          end
        end  
      endcase 


      // Buffer and handle reads
      if (have_rdata) begin
        ps_rd_buffptr <= ps_rd_buffptr + 1;  
        ps_rdbuff[(ps_rd_buffptr+1)%(`REQ_BUFFER_SZ)] <= rdata_in;
        ps_ribuff[(ps_rd_buffptr+1)%(`REQ_BUFFER_SZ)] <= rindex_in; 
      end else begin
        case(rdataTransmitState) 
          IDLE: begin
            if (rcomplete) rdataTransmitState <= SEND;
          end 
          SEND: begin
            if (transmit_rdata_rdy && ~have_rdata) begin
              ps_rd_buffptr <= ps_rd_buffptr - 1;
              ps_rdbuff[ps_rd_buffptr] <= -1; 
              rdataTransmitState <= IDLE; 
            end 
          end 
        endcase
      end

    end
  end
endmodule 

// Make a pswrite request fall immediately after being served, same with read request 