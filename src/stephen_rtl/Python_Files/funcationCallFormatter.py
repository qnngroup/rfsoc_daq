def find_num_pats(s,pat):
    num = 0
    while True:
        i = s.find(pat)
        if i == -1: break
        i += len(pat)
        s = s[i:]
        num+=1
    return num

def pullParams(s,macro=False):
    out = ""
    start = s.find("#")
    end = s.find(")")+1
    line = s[start:end]
    while True:
        i = line.find("parameter")
        if i == -1: break 
        i+=len("parameter")+1
        j = i 
        while True:
            if line[j] in [" ", "=", ",",""")"""]: break
            j+=1 
        arg = line[i:j]
        out += f".{arg}({'`' if macro else ''}{arg}), "
        line = line[j:]
    return out[:-2],s[end:]
    
def getfName(s, params=False):
    i1 = s.find("module")+len("module")+1
    i2 = i1
    while True:
        if s[i2] in [" ", "(", "#"]: break
        i2+=1
    return s[i1:i2],i2

def align(s):
    alignI = s.find(".")
    lines = s.split("\n")
    out = lines[0]+"\n"
    for line in lines[1:]:
        if line == '': continue
        out+=alignI*" "+line+"\n"
    return out


def formatFuncCall(s,fName = "functionName",macro=False):
    n = find_num_pats(s, ",")+1
    out,i = getfName(s)
    if "#" in s: 
        params,s = pullParams(s,macro)
        out += f" #({params})\n"
        # params=True 
        n+=1
    else: out += "\n"
    s = s[i:]
    body = f"{fName}("
    while True:
        i1 = s.find(",")
        if i1 == -1: i1 = s.find(");")
        if i1 == -1: break 
        i2 = i1
        while True:
            if s[i2-1] == " ": break
            i2-=1 
        arg = s[i2:i1]
        body+=f".{arg}({arg}),\n"
        s = s[i1+1:]
    body = body[:-2]
    body+=");"
    if find_num_pats(out+body, ".") != n: print("ERROR IN BODY")
    return out+align(body)


st = """module top_tb #(parameter BATCH_SIZE, parameter A_BUS_WIDTH, parameter WD_BUS_WIDTH, parameter DMA_DATA_WIDTH, parameter WD_WIDTH,
				parameter SDC_DATA_WIDTH, parameter BUFF_CONFIG_WIDTH, parameter CHANNEL_MUX_WIDTH, parameter BUFF_TIMESTAMP_WIDTH)
					   (input wire ps_clk, dac_clk, pl_rstn,
					   	output logic ps_rst, dac_rst, 
		                //DAC
		                output logic dac0_rdy,
		                input  wire[BATCH_SIZE-1:0][WD_WIDTH-1:0] dac_batch, 
		                input  wire valid_dac_batch, 
		                //AXI
		                output logic [A_BUS_WIDTH-1:0] raddr_packet,
		                output logic raddr_valid_packet,
		                output logic [A_BUS_WIDTH-1:0] waddr_packet,
		                output logic waddr_valid_packet,
		                output logic [WD_BUS_WIDTH-1:0] wdata_packet,
		                output logic wdata_valid_packet,
		                output logic ps_wresp_rdy,ps_read_rdy,
		                input  wire[1:0] wresp_out,rresp_out,
		                input  wire wresp_valid_out, rresp_valid_out,
		                input  wire[WD_BUS_WIDTH-1:0] rdata_packet,
		                input  wire rdata_valid_out,
		                //Config Registers
		                input  wire sdc_rdy_in,
		                output logic[SDC_DATA_WIDTH-1:0] sdc_data_out,
		                output logic sdc_valid_out,
		                input  wire buffc_rdy_in,
		                output logic[BUFF_CONFIG_WIDTH-1:0] buffc_data_out,
		                output logic buffc_valid_out,
		                input  wire cmc_rdy_in,
		                output logic[CHANNEL_MUX_WIDTH-1:0] cmc_data_out,
		                output logic cmc_valid_out, 
		                input  wire[BUFF_TIMESTAMP_WIDTH-1:0] bufft_data_in,
		                input  wire bufft_valid_in,
		                output logic bufft_rdy_out, 
		                //DMA
		                output logic[DMA_DATA_WIDTH-1:0] pwl_data,
		                output logic[(DMA_DATA_WIDTH/8)-1:0] pwl_keep,
		                output logic pwl_last, pwl_valid,
		                input  wire pwl_ready,
		                input  wire run_pwl, run_trig, run_rand);
                 """
fName = "tb_i"
macro = True
out= formatFuncCall(st,fName=fName,macro=macro)
print(out)
















