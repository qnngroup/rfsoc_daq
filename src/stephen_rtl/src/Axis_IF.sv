`timescale 1ns / 1ps

interface Axis_IF #(parameter DWIDTH, parameter CHAN = 1);
    logic[CHAN-1:0][DWIDTH-1:0]  data;
    logic[CHAN-1:0] ready, valid;
    logic[CHAN-1:0] last, done, ok;

    always_comb begin
        for (int i = 0; i < CHAN; i++) begin 
            done[i] = last[i] && ready[i]; 
            ok[i] = ready[i] && valid[i];
        end 
    end 
    modport stream_in (input data, valid, last, ok, done, output ready);
    modport stream_out (input ready, done,ok, output data, valid, last);  
endinterface

