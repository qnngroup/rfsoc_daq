interface Axis_IF #(parameter DWIDTH = 32);
    logic[DWIDTH-1:0]  data;
    logic ready, valid;
    logic last, done, ok;

    assign done = last && ready; 
    assign ok = ready && valid;
    modport stream_in (input data, valid, last, ok, done, output ready);
    modport stream_out (input ready, done,ok, output data, valid, last);  
endinterface

