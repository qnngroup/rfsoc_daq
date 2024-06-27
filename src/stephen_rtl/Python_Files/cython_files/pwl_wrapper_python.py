from time import perf_counter
from random import randrange as rr
from sys import path
path.insert(0, r'C:\Users\skand\OneDrive\Documents\GitHub\rfsoc_daq\src\stephen_rtl\Python_Files')
from fpga_constants import *

def create_slope_obj(slope):
    sign = 1 if slope > 0 else -1  
    whole = floor(slope) if sign > 0 else ceil(slope)
    fract = round(whole-slope,fixed_point_percision)
    return {"sign": sign, "whole": abs(whole), "fract":abs(fract)}

def nearest_int(num): return floor(num+0.5)

def scale(slope,i): return nearest_int(slope["sign"]*(slope["whole"]+slope["fract"])*i)

def is_zero_slope(slope): return slope["whole"] == 0 and slope["fract"] == 0.0

def inv_num(num,bit_width):
    mask = (1<<bit_width)-1
    num = (abs(num) ^ mask)+1  
    return num

def float_to_fixed(num,m,n): 
    raw_fixed = round(abs(num)*(2**n))
    if num < 0: raw_fixed = inv_num(raw_fixed,m+n)  
    return raw_fixed
    
def gen_rand_coords(avg_dt=100,T=500,n=5,max_val=2**15-1):
    coords = [(0,0)]
    abs_t = 0
    for i in range(n):
        t = rr(1,avg_dt)
        x = rr(0,max_val)
        abs_t+=t
        coords.append((x,abs_t))
    return coords   


def mk_fpga_cmds(pwl_cmds):
    fpga_cmds = []
    for x,slope,dt,sb in pwl_cmds: 
        if x < 0: x = inv_num(x,16)
        x = x<<(12*4) 
        slope = slope["sign"]*(slope["whole"]+slope["fract"])
        slope = float_to_fixed(slope,16,16)
        slope = slope<<(4*4)
        dt = (dt << 1) + sb
        if dt & 0x8000: dt -= 0x8000
        fpga_cmds.append(x+slope+dt)
    return fpga_cmds
        

# Given a list of incomplete pwl_coords of the form (x,dx/dt,dt,-1), creates as many batched coordinates
# (where dt is a multiple of batch_size) as possible and assigns all but the last to have a valid sparse_bit
# (since assignment of the last depends on the points that follow). Assumes function was called the moment sum of all t's in coords >= batch_size
# Returns the number of pwl_tups that were modified or changed in the passed pwl_coord list
def batchify(pwl_cmd):
    clean_dt = (pwl_cmd["dt"]//batch_size)*batch_size
    if clean_dt == 0:
        pwl_cmd["sb"] = 0 
        return 0,0 
    leftover_dt = pwl_cmd["dt"]-clean_dt 
    newx = pwl_cmd["x"]+scale(pwl_cmd["slope"],clean_dt)
    pwl_cmd["dt"] = clean_dt
    pwl_cmd["sb"] = 1
    return newx,leftover_dt 

# Given coords of the form (x,t) that describe a wave, produces pwl_coords of the form (x,dx/dt,dt,sparse_bit).
# Also produces a list of hex numbers (representing the same pwl commands) that can be sent to the FPGA.
# Bitwidths look like (16,16,16,1)
def mk_pwl_cmds(coords, path):
    i = len(coords)-1
    coord = coords[i].copy()
    x1 = coord["x"] 
    t1 = coord["t"]
    batch_t = 0 
    path_ptr = 0 
    skip_calc = False
    slope = {"sign": -1, "whole": 1, "fract": 0}
    pwl_cmd = {"x":-1,"slope":slope.copy(),"dt":-1,"sb":-1}
    i-=1
    
    # Fill up path with (x,slope,dt,sparse_bit) points
    while i >= -2:
        
        if i > -1:
            if skip_calc: skip_calc = False
            else:
                coord = coords[i].copy()
                x2 = coord["x"] 
                t2 = coord["t"] 
                dx = x2-x1
                dt = t2-t1
                slope = create_slope_obj(dx/dt)  

            # See if we must grow the current pwl_cmd before adding to path 
            if pwl_cmd["dt"] == -1:
                pwl_cmd["x"] = x1 
                pwl_cmd["slope"] = slope.copy() 
                pwl_cmd["dt"] = dt 
                pwl_cmd["sb"] = -1 
                # Move onto next point 
                x1 = x2
                t1 = t2 
                i-=1
                continue 
            if slope == pwl_cmd["slope"]:
                pwl_cmd["dt"]+=dt 
                # Move onto next point
                x1 = x2
                t1 = t2 
                i-=1
                continue
            
        # If i is -2, we've completed everything and just need to make sure the last batch gets filled in (if we're currently filling one)
        if i == -2:
            if batch_t == 0 or batch_t == batch_size:
                prev_pwl_cmd = path[path_ptr-1]
                ending_x = prev_pwl_cmd["x"]+scale(prev_pwl_cmd["slope"],prev_pwl_cmd["dt"]-1)
                if ending_x == x2: break 
            left_in_batch = batch_size-batch_t
            pwl_cmd["x"] = x2
            pwl_cmd["sb"] = 1 if left_in_batch == batch_size else 0
            # If the last slope was 0, we can consolidate 
            if is_zero_slope(pwl_cmd["slope"]):
                # If the only thing in the batch we have to finish is a cmd with 0 slope, fill it all with this. 
                if pwl_cmd["dt"] == batch_t:
                    pwl_cmd["dt"] = batch_size
                    pwl_cmd["sb"] = 1
                    if path_ptr > 1:
                        prev_pwl_cmd = path[path_ptr-2]
                        if is_zero_slope(prev_pwl_cmd["slope"]) and prev_pwl_cmd["sb"]: 
                            prev_pwl_cmd["dt"]+=batch_size
                            path_ptr-=1
                            pwl_cmd = prev_pwl_cmd.copy()                        
                else: pwl_cmd["dt"]+=left_in_batch
                path[path_ptr-1] = pwl_cmd.copy()
                break
            pwl_cmd["dt"] = left_in_batch
            pwl_cmd["slope"] = {"sign": 1, "whole":0,"fract":0.0}
            path[path_ptr] = pwl_cmd.copy()
            path_ptr+=1
            break 
         
        # When are we allowed to add sparse cmds? If the current batch isn't fragmented and the current pwl_cmd would fill atleast 1 full batch
        if batch_t >= batch_size or (batch_t == 0 and pwl_cmd["dt"] >= batch_size):
            newx, leftover_dt = batchify(pwl_cmd)
            path[path_ptr] = pwl_cmd.copy()
            path_ptr+=1 
            batch_t = 0
            if leftover_dt != 0:
                # This means the current pwl_cmd was batchified but there's some overflow => it must still be handled 
                # Otherwise, the pwl_cmd filled up a perfect num of batches => move on to next point. 
                pwl_cmd["x"] = newx
                pwl_cmd["dt"] = leftover_dt  
                pwl_cmd["sb"] = -1 
                skip_calc = True
                continue            
        else:
            if batch_t+pwl_cmd["dt"] <= batch_size: 
                # This means the pwl_cmd-to-add will not fully fill up a batch. So we add it, then consider the next pwl point.
                # (sb will surely be 0 since we'll need to fill the batch we're currently making)
                # print(pwl_cmd["x"])
                pwl_cmd["sb"] = 0 
                path[path_ptr] = pwl_cmd.copy()
                path_ptr+=1 
                batch_t+=pwl_cmd["dt"]
                if batch_t == batch_size: batch_t = 0
            else: 
                # This means the pwl_cmd-to-add will overflow the current batch. 
                # So we must complete the current batch, update the current pwl_cmd and continue (holding onto the next point)
                # (sb will be 1 if what's left of dt is enough to fill a batch, and 0 otherwise)
                left_in_batch = batch_size-batch_t
                full_pwlcmd_dt = pwl_cmd["dt"]
                pwl_cmd["dt"] = left_in_batch 
                pwl_cmd["sb"] = 0
                path[path_ptr] = pwl_cmd.copy()
                path_ptr+=1 
                batch_t = 0
                pwl_cmd["x"] += scale(pwl_cmd["slope"],left_in_batch)
                pwl_cmd["dt"] = full_pwlcmd_dt-left_in_batch
                pwl_cmd["sb"] = -1
                skip_calc = True
                continue 
            
        # Move onto next point (if there is one)
        if i > -1:
            pwl_cmd["x"] = x1
            pwl_cmd["slope"] = slope.copy()
            pwl_cmd["dt"] = dt 
            pwl_cmd["sb"] = -1 
            x1 = x2
            t1 = t2 
        i-=1
    return path_ptr

def main(coords):
    t0 = perf_counter()
    coords = [{"x":el[0], "t":el[1]} for el in coords]
    path_wrapper = [0]*((len(coords)-1)*6)
    l = mk_pwl_cmds(coords,path_wrapper)
    # print(toLi(path_wrapper,l,True))
    path = toLi(path_wrapper,l)
    fpga_cmds = mk_fpga_cmds(path)
    intv = perf_counter() - t0
    coords = [] 
    return intv,fpga_cmds


def toLi(path,n,pretty=False): 
    out = []
    for i,di in enumerate(path):
        if i >= n: break
        el = tuple([e for e in di.values()])
        if pretty:
            s = el[1]["sign"]*(el[1]["whole"]+el[1]["fract"])
            el = el[0:1] + (s,)+ el[2:]
        out.append(el)
    return out

def toDi(li):
    out = []
    for el in li:
        di = {}
        di["x"] = el[0]
        di["slope"] = el[1]
        di["dt"] = el[2]
        di["sb"] = el[3]
        out.append(di)
    return out

# def decode_pwl_cmds(pwl_cmds):
#     wave = []
#     batch = []
#     coords = []
#     abs_t = 0
#     for x,slope,dt,_ in pwl_cmds:
#         t = 0
#         slope = create_slope_obj(slope)
#         coords.append((x,abs_t))
#         abs_t+=dt
#         while dt > 0:
#             batch.append(x+scale(slope,t))
#             if len(batch) == batch_size: 
#                 wave.append(batch)
#                 batch = [] 
#                 x = x + scale(slope, batch_size)
#                 t = 0
#                 dt-=1
#                 continue 
#             t+=1 
#             dt-=1
#     coords.append((wave[-1][-1],abs_t-1))
#     if len(batch) != 0:
#         print("UNEVEN WAVE CREATED")
#         return None
#     return wave,coords

def decode_pwl_cmds(pwl_cmds):
    wave = []
    batch = []
    coords = []
    abs_t = 0
    for x,slope,dt,_ in pwl_cmds:
        t = 0
        slope = create_slope_obj(slope)
        coords.append((x,abs_t))
        abs_t+=dt
        while t < dt:
            batch.append(x+scale(slope,t))
            if len(batch) == batch_size: 
                wave.append(batch)
                batch = [] 
            t+=1 
    coords.append((wave[-1][-1],abs_t-1))
    if len(batch) != 0:
        print("UNEVEN WAVE CREATED")
        return None
    return wave,coords

def fixed_to_float(num,m,n):
    whole,fract = 0,0
    bin_num = bin(num)[2:]
    j = -n
    out = 0
    for i in range(len(bin_num)-1,-1,-1):
        if bin_num[i] == "1": out+=2**j if j != (m-1) else -2**j
        j+=1
    return out 

def fpga_to_pwl(fpga_cmds):
    pwl_cmds = []
    for num in fpga_cmds:
        x_mask = 0xffff << (12*4)
        x = (num&x_mask) >> (12*4)
        print(hex(x_mask),hex(x))
        if x & 0x8000: x = -0x8000 + (x & 0x7fff)
        print(x)
        slope_mask = 0xffffffff << (4*4)
        slope = (num&slope_mask) >> (4*4)
        slope = fixed_to_float(slope,16,16)    
        dt_mask = 0xffff
        sb = num & 0b1
        dt = (num&dt_mask) >> 1
        pwl_cmds.append((x,slope,dt,sb)) 
    return pwl_cmds

#############################################################

# coords = [(0,0), (-6,5)]
# coords.reverse()
# intv,fpga_cmds = main(coords)
# print([hex(el) for el in fpga_cmds])
# pwl = fpga_to_pwl(fpga_cmds)
# print(pwl)

# pc = [(0, 0.140625, 64, 1)]
# print(decode_pwl_cmds(pc))




