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


st = """module axi_slave #(parameter A_BUS_WIDTH=2, parameter A_DATA_WIDTH=5, parameter WD_BUS_WIDTH=8, parameter WD_DATA_WIDTH=32)
				  (input wire clk, rst,
				   Recieve_Transmit_IF waddr_if,
				   Recieve_Transmit_IF wdata_if,
				   Recieve_Transmit_IF raddr_if,
				   Recieve_Transmit_IF rdata_if,
				   Recieve_Transmit_IF wresp_if,
				   Recieve_Transmit_IF rresp_if, 
				   input wire[`MEM_SIZE-1:0] rtl_write_reqs, rtl_read_reqs,
				   input wire clr_rd_out, 
				   input wire[`MEM_SIZE-1:0] rtl_rdy, 
               	   input wire[`MEM_SIZE-1:0][WD_DATA_WIDTH-1:0] rtl_wd_in,
               	   output logic[`MEM_SIZE-1:0][WD_DATA_WIDTH-1:0] rtl_rd_out,
               	   output logic[`MEM_SIZE-1:0] fresh_bits);
                 """
fName = "dut_i"
out= formatFuncCall(st,fName=fName)
print(out)
















