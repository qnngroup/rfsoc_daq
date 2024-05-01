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
        params=True 
        n+=1
    else: params = False
    s = s[i:]
    body = f" {fName}("
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
    return out+align(body) if params else align(out+body)


st = """module ps_interface(
                    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ps_clk CLK" *)
                    (* X_INTERFACE_PARAMETER = "FREQ_HZ 149998505 ASSOCIATED_BUSIF \
                      ps_axi" *)
                    input wire ps_clk,
                    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ps_rstn RST" *)
                    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
                    input wire ps_rstn, 
                    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 dac_clk CLK" *)
                    (* X_INTERFACE_PARAMETER = "FREQ_HZ 384000000 ASSOCIATED_BUSIF \
                      dac:\
                      pwl" *)
                    input wire dac_clk, 
                    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 dac_rstn RST" *)
                    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
                    input wire dac_rstn, 
                    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 pl_rstn RST" *)
                    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
                    output wire pl_rstn,

                    //DAC OUTPUT INTERFACE
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 dac TDATA" *)
                    output wire[255:0] dac_tdata,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 dac TVALID" *)
                    output wire        dac_tvalid, 
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 dac TREADY" *)
                    input  wire        dac_tready, 
                    output wire        rtl_dac_valid,

                    //PS AXI-LITE INTERFACE
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi ARADDR" *)
                    input  wire[31:0] ps_axi_araddr, 
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi ARPROT" *)
                    input  wire[2:0]  ps_axi_arprot,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi ARVALID" *)
                    input  wire       ps_axi_arvalid,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi ARREADY" *)
                    output wire       ps_axi_arready,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi RDATA" *)
                    input  wire[31:0] ps_axi_rdata,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi RRESP" *)
                    input  wire       ps_axi_rresp,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi RVALID" *)
                    output wire       ps_axi_rvalid,  
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi RREADY" *)
                    output wire[1:0]  ps_axi_rready,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi AWADDR" *)
                    input  wire[31:0] ps_axi_awaddr,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi AWPROT" *)
                    input  wire[2:0]  ps_axi_awprot,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi AWVALID" *)
                    input  wire       ps_axi_awvalid,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi AWREADY" *)
                    output wire       ps_axi_awready,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi WDATA" *)
                    input  wire[31:0] ps_axi_wdata,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi WSTRB" *)
                    input  wire[3:0]  ps_axi_wstrb,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi WVALID" *)
                    input  wire       ps_axi_wvalid,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi WREADY" *)
                    output wire       ps_axi_wready,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi BRESP" *)
                    output wire[1:0] ps_axi_bresp,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi BVALID" *)
                    output wire      ps_axi_bvalid,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 ps_axi BREADY" *)
                    input  wire      ps_axi_bready,

                    // ps_axiPWL DMA INTERFACE
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 pwl TDATA" *)
                    input wire[63:0] pwl_tdata,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 pwl TKEEP" *)
                    input wire[7:0] pwl_tkeep,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 pwl TLAST" *)
                    input wire pwl_tlast, 
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 pwl TVALID" *)
                    input wire pwl_tvalid,
                    (* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 pwl TREADY" *)
                    output wire pwl_tready);
                 """
fName = "ps_interface"
out= formatFuncCall(st,fName=fName)
print(out)
















