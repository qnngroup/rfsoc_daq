interface Axis_IF #(parameter DWIDTH = 32);
    logic[DWIDTH-1:0]  data;
    logic ready, valid;
    logic last, done;

    assign done = last && ready; 
    modport stream_in (input data, valid, last, done, output ready);
    modport stream_out (input ready, done, output data, valid, last); 
endinterface

