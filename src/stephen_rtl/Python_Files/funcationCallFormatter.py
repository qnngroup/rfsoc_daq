st = """module top_level(input wire ps_clk,ps_rst, dac_clk, dac_rst,
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

                 """


def find(st,pat,num):
    i = -1
    while num > 0:
        i = st.find(pat,i+1,-1)
        num-=1
    return i

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
    end = s.find(")")
    line = s[start:end]
    n = find_num_pats(line, "parameter")
    while True:
        i = line.find("parameter")
        if i == -1: break 
        i+=len("parameter")+1
        j = line.find(",")
        p = line.find("=")
        if j == -1: j = p
        elif p != -1 and j > p: j = p
        arg = line[i:j-1]
        out += f".{arg}({arg}), "
        if line[j] == "=": j = line.find(",")
        if j == -1: break
        line = line[j+1:]
    s = s[s.find(")")+1:]
    if n != find_num_pats(out,"."): print ("ERROR IN PARAMTERS")
    return out[:-2],s
    
def getfName(s, params=False):
    i1 = s.find("module")+len("module")+1
    i2 = s.find("#")-1
    if i2 == -2: i2 = s.find("(")
    while s[i2-1] == " ": i2-=1
    return s[i1:i2]

def align(s):
    alignI = s.find(".")
    lines = s.split("\n")
    out = lines[0]+"\n"
    for line in lines[1:]:
        if line == '': continue
        out+=alignI*" "+line+"\n"
    return out

def grab_args(line):
    args = []
    i = line.find(");")
    if i != -1: line = line[:i]+","
    while True:
        i = line.find(",")
        if i == -1: break 
        j = i 
        while j >= 0 and " " not in line[j:i]: j-=1
        args.append(line[j+1:i])
        line = line[i+1:]
    return args

def clean(s):
    while (s.find("\t") != -1): s = s.replace("\t","")
    lines = s.split("\n")
    s = ""
    for line in lines:
        if all([el == " " for el in line]): continue
        if line.find("//") != -1: continue
        if line: s+=line+"\n"
    s = s[:-1]
    for i in range(len(s)):
        if s[i] == " " and s[i+1] == " ":
            j = i
            while True:
                if s[j] == " ": s = s[:j]+"*"+s[j+1:]
                else: break
                j+=1
    s = s.replace("*","")
    return s

def formatFuncCall(s,fName = "functionName"):
    s = clean(s)
    out = getfName(s)
    if (s.find("#") != -1):
        params,s = pullParams(s)
        out += f" #({params})\n"
        params = True
    else: params = False
    body = f" {fName}("
    n = find_num_pats(s, ",")+1
    lines = s.split("\n")
    n2 = len(lines)
    for line in lines:
        args = grab_args(line)
        for arg in args: body+=f".{arg}({arg}),\n"
    body = body[:-2]
    body+=");"
    if find_num_pats(body, ".") != n or n < n2: print("ERROR IN BODY")
    return out+align(body) if params else align(out+body)

out= formatFuncCall(st,fName="tl")
print(out)
# line = "input wire ps_wresp_rdy,blah,bloo,foo,whoo,oops,ps_read_rdy,   "
# line = clean(st)
# i = 0
# while True:
#   i+=1
#   line, arg = grabNextArg(line)
#   if (line == -1): break
#   print(arg)
#   if i == 20: break
















