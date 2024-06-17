def find_num_pats(s,pat):
    num = 0
    while True:
        i = s.find(pat)
        if i == -1: break
        i += len(pat)
        s = s[i:]
        num+=1
    return num

def pullParams(s):
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
        out += f".{arg}({arg}), "
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


def formatFuncCall(s,fName = "functionName"):
    n = find_num_pats(s, ",")+1
    out,i = getfName(s)
    if "#" in s: 
        params,s = pullParams(s)
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


st = """module cdc_tb #(parameter PS_CMD_WIDTH, parameter DATA_WIDTH)
			   (input wire ps_clk, dac_clk, 
			   	input  wire[PS_CMD_WIDTH-1:0] ps_cmd_out,
			   	input  wire[DAC_RSP_WIDTH-1:0] dac_rsp_out,
			   	output logic ps_rst, dac_rst, 
			   	output logic[PS_CMD_WIDTH-1:0] ps_cmd_in,
			   	output logic ps_cmd_valid_in, ps_cmd_valid_out, ps_cmd_transfer_rdy, ps_cmd_transfer_done,
			   	output logic[DAC_RSP_WIDTH-1:0] dac_rsp_in, 
			   	output logic dac_rsp_valid_in, dac_rsp_valid_out, dac_rsp_transfer_rdy, dac_rsp_transfer_done);
                 """
fName = "tb_i"
out= formatFuncCall(st,fName=fName)
print(out)
















