st = """module edetect #(parameter DEFAULT = 0, parameter DATA_WIDTH = 1)
                (input wire clk, rst,
                 input wire[DATA_WIDTH-1:0] val,
                 output logic[1:0] comb_posedge_out,
                 output logic[1:0] posedge_out);
                 """


def find(st,pat,num):
    i = -1
    while num > 0:
        i = st.find(pat,i+1,-1)
        num-=1
    return i

def pullParams(s):
    out = ""
    start = s.find("#")
    end = s.find(")")
    line = s[start:end]
    s = s[end:]
    s = s[s.find("("):]
    pats = ["="," ",","]
    while True:
        if line.find("parameter") == -1: break
        start = line.find("parameter")+len("parameter")+1
        li = []
        i = 1
        for el in pats:
            while True:
                end = find(line,el,i)
                if end == -1: break
                if end <= start:
                    i+=1
                    continue
                else:
                    li.append(end)
                    break
        end = min(li)
        arg = line[start:end]
        out += f".{arg}(`{arg}) "
        line = line[end:]

    return out[:-1],s

def getfName(s, params=False):
    i1 = s.find("module")+len("module")+1
    i2 = s.find("#")-1
    if i2 == -2: i2 = s.find("(")
    return s[i1:i2]

def align(s):
    alignI = s.find(".")
    lines = s.split("\n")
    out = lines[0]+"\n"
    for line in lines[1:]:
        if line == '': continue
        out+=alignI*" "+line+"\n"
    return out

def grabNextArg(line):
    propPats = [line.find(el) for el in ["][", "] ["]]
    if any(propPats):
        i = max(propPats)
        line = line[i+3:]

    keyWrds = ['Axis_IF', 'Recieve_Transmit_IF','int','logic','input','parameter','output','input','inout','output', ']', 'wire']
    start = max([line.find(el)+len(el) if line.find(el) != -1 else -1 for el in keyWrds])
    while(line[start] == " "): start+=1

    end = line.find(',')
    if end == -1: end = line.find(')')
    if end == -1: return -2, ""
    arg = line[start:end]
    if end == len(line)-1: line = -1
    else: line = line[:start]+line[end+1:]
    return line,arg

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

def formatFuncCall(s,params=False,fName = "functionName"):
    s = clean(s)
    out = getfName(s)
    if (params):
        params,s = pullParams(s)
        out += f" #({params})\n"
    body = f" {fName}("
    lines = s.split("\n")
    for line in lines:
        while True:
            line,arg = grabNextArg(line)
            if line == -2: break
            body+=f".{arg}({arg}),\n"
            if line == -1: break
    body = body[:-2]
    body+=");"
    return out+align(body) if params else align(out+body)

out= formatFuncCall(st,True,fName="correct_ed")
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
















