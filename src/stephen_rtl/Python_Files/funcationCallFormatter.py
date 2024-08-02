def find_num_pats(s,pat):
    num = 0
    while True:
        i = s.find(pat)
        if i == -1: break
        i += len(pat)
        s = s[i:]
        num+=1
    return num

def pullParams(s,addition):
    out = ""
    start = s.find("#")
    end = s.find(")")+1
    line = s[start:end]
    if find_num_pats(s,"parameter") == 1:
        i = line.find("parameter")+len("parameter")
        args = line[i:].split(",")
        args = [el.replace(" ", "").replace(")","") for el in args]
        for arg in args: out += f".{arg}({addition if addition else ''}{arg}), "
    else:   
        while True:
            i = line.find("parameter")
            if i == -1: break 
            i+=len("parameter")+1
            j = i 
            while True:
                if line[j] in [" ", "=",""")"""]: break
                j+=1 
            arg = line[i:j]
            out += f".{arg}({addition if addition else ''}{arg}), "
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


def formatFuncCall(s,fName = "functionName",addition=None):
    n = find_num_pats(s, ",")+1
    out,i = getfName(s)
    if "#" in s: 
        params,s = pullParams(s,addition)
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


st = """module wave_generator (input wire clk,rst,
			 		  input wire next,
			 		  output logic[DATAW-1:0] sample_out, 
			 		  output logic sample_out_valid,
			 		  Axis_IF.stream_in wave);
                 """
fName = "wave_gen"
addition = "daq_params_pkg::"
out= formatFuncCall(st,fName=fName,addition=addition)
print(out)
















