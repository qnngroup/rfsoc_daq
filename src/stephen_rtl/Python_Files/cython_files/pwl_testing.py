from sys import path
path.insert(0, r'C:\Users\skand\OneDrive\Documents\GitHub\rfsoc_daq\src\stephen_rtl\Python_Files')
path.insert(0, r'C:\Users\skand\OneDrive\Documents\GitHub\rfsoc_daq\src\stephen_rtl\Python_Files\cython_files')
import pwl_wrapper as c
import pwl_wrapper_python as p
import matplotlib.pyplot as plt
from matplotlib.font_manager import FontProperties
from math import ceil,floor
from random import randrange as rr
from time import time,sleep, perf_counter

from fpga_constants import *


def round_slope(slope): 
    if ((slope < -1) or (slope > 0 and slope < 1)): return ceil(slope)
    return floor(slope)

def ignore_same_sloped_points(coords):
    s1,s2 = None,None
    ignore = []
    for i,c1 in enumerate(coords):
        if i == len(coords)-1: break 
        c2 = coords[i+1]
        x1,t1 = c1
        x2,t2 = c2
        dx = x2-x1
        dt = t2-t1
        slope = round_slope(dx/dt)
        if s1 is None: s1 = slope
        elif s2 is None: s2 = slope 
        else:
            s1 = s2
            s2 = slope 
            
        if s1 is not None and s2 is not None: 
            if s1 == s2: ignore.append(c1)
    return ignore

def gen_rand_coords(avg_dt=100,T=500,n=5,max_val=0x7fff):
    coords = [(0,0)]
    abs_t = 0
    for i in range(n):
        t = rr(1,avg_dt)
        x = rr(-max_val,max_val)
        abs_t+=t
        coords.append((x,abs_t))
    return coords

def insert_points(coords,n=1):
    out = []
    for i,c in enumerate(coords):
        out.append(c)
        if i == len(coords)-1: continue
        x1,t1 = coords[i]
        x2,t2 = coords[i+1]
        dx = x2-x1
        dt = t2-t1
        slope = round_slope(dx/dt)
        
        intv = dt//(n+1)
        if intv == 0: intv = 1
        t = t1+intv
        while t < t2:
            out.append((x1+slope*t,t))
            t+=intv
    return out

def flatten(li):
    out = []
    for el in li:
        if type(el) == list: out += flatten(el)
        else: out.append(el)
    return out 

def fpga_to_sv(fpga_cmds):
    li = fpga_cmds[:]
    li.reverse()
    cmd = "assign dma_buff = {"
    for el in li: cmd+=f"48'd{el}, "
    cmd = cmd[:-2]+"};"
    return cmd 
def test_coords(coords,do_plot=True,show_batches=False,simple_plot=False, ignore=[],mv=0x7fff, scale_plot = False):
    coords.reverse()
    intvc,fpga_cmds = c.main(coords)
    path = c.fpga_to_pwl(fpga_cmds)
    intvp,py_fpga_cmds = p.main(coords)
    py_path = c.fpga_to_pwl(py_fpga_cmds)
    waves,_ = p.decode_pwl_cmds(path)
    
    if scale_plot:
        for i in range(len(waves)):
            waves[i] = [(el/mv)*100 for el in waves[i]]
        coords = [((el[0]/mv)*100,el[1]) for el in coords]
        
    flat_wave = flatten(waves)
    if do_plot:
        split = lambda li: ([el[0] for el in li],[el[1] for el in li])
        x,t = split(coords)
        plt.scatter(t,x)
        
        if simple_plot: plt.plot(flat_wave)
        else:
            abs_t = 0
            wavlet_cmd = [] 
            path_cpy = path[:]
            batch_t = 0
            while path_cpy:
                cmd = path_cpy.pop(0)                
                while cmd[-1] == 0 and path_cpy[0][-1] == 0 and (batch_t+cmd[-2]) < batch_size: 
                    wavlet_cmd+=[cmd]
                    batch_t+=cmd[-2]
                    cmd = path_cpy.pop(0) 
                    if len(path_cpy) == 0: break
                wavlet_cmd +=[cmd]
                cmd_wave = flatten(c.decode_pwl_cmds(wavlet_cmd))
                t = [abs_t+el for el in range(len(cmd_wave))]
                plt.plot(t,cmd_wave)
                abs_t+=len(cmd_wave)
                wavlet_cmd = []
                batch_t = 0
          

    wrong = []
    waves2,_= p.decode_pwl_cmds(path)
    if waves != waves2: wrong.append("decoded paths not equal")
    if py_path != path: wrong.append(("paths not equal"))
    if py_fpga_cmds != fpga_cmds: wrong.append(("fpga_cmds not equal"))
    
    for x1,t1 in coords:
        if (x1,t1) in ignore: continue
        if x1 not in flat_wave: 
            if do_plot:
                plt.axhline(x1)
                plt.axvline(t1)
            wrong.append((x1,t1,"Missing Coord"))
            
    batches,j = [0],0
    for el in path:
        _,_,dt,_ = el
        if dt <= 0: wrong.append((el, "0 or Negative time"))
        if batches[j] < p.batch_size: batches[j]+=dt
        else: 
            j+=1
            batches.append(dt)
    if any([el%batch_size != 0 for el in batches]): wrong.append((batches,"Batches aren't chunked correctly"))
    
    batch_t = 0
    for i,el in enumerate(path):
        x,slope,dt,sb = el 
        if batch_t != 0 and sb: 
            wrong.append((i,"Haven't finished a batch"))
            break 
        if sb == 1:
            if dt%batch_size == 0: continue
            wrong.append((i,"Continuous batch not continuous"))
        else:
            nbatch_t = batch_t+dt
            if nbatch_t == batch_size: batch_t = 0
            else: batch_t = nbatch_t
        
    tot_t = len(flat_wave)
    abs_time = coords[0][1]
    if tot_t != abs_time+(p.batch_size-abs_time%p.batch_size) and tot_t != abs_time: wrong.append((tot_t,abs_time,"Absolute time not reached"))
    
    if len(path) >(len(coords)-1)*6: wrong.append((len(path), "Path length exceeded allocated memory"))
    passed = len(wrong) == 0 
    
    if show_batches and do_plot:
        t = 0
        while t <= len(flat_wave):
            plt.axvline(t,color="orange", alpha=0.4)
            t+=batch_size
    
    return path,passed,wrong,intvc,intvp
##############################################################################################################################################

test_num = int(1e4)
do_plot = False
simple_plot = False
nxt_perc = 10
t0 = time()
n = 10
intvcs,intvps = [],[]
for i in range(test_num):
    perc = (i/test_num)*100
    if round(perc) == nxt_perc: 
        print(f"{nxt_perc}%",end="")
        if nxt_perc != 90: print(",",end="")
        nxt_perc+=10        
    coords = gen_rand_coords(n=n,avg_dt=100,max_val=max_voltage)
    # coords = [(0, 0), (9, 64)]
    ignore = ignore_same_sloped_points(coords)
    path,result,wrong,intvc,intvp = test_coords(coords[:],do_plot=do_plot,show_batches=False,simple_plot=simple_plot, ignore=ignore,scale_plot = False)
    intvcs.append(intvc)
    intvps.append(intvp)
    if not result:
        print("\nFailed")
        print(coords)
        print(wrong)
        break
else:
    print("\nPassed")

# avg_intvc = sum(intvcs)/len(intvcs)
# avg_intvp = sum(intvps)/len(intvps)
# print(f"\n################################\n\nInput coord list lenght: {n}")
# print(f"\nAvg Cython calc time:\n{round(avg_intvc*1e6,2)} us\n{round(avg_intvc*1e3,2)} ms")
# print(f"\nAvg Python calc time:\n{round(avg_intvp*1e6,2)} us\n{round(avg_intvp*1e3,2)} ms\n")
# print(f"Cython is {round(avg_intvp/avg_intvc)}x faster")
# print(f"\nTest time:\n{round(time()-t0,2)} s")


# coords = [(0,0), (300,300), (350,1000),(0,1800)]
# coords = [(0,0), (18,18), (0,20)]
# coords = [(0,0), (2,400)]
# coords = [(0,0), (-6,5)]
# coords = [(0, 0), (94, 4), (-99, 7)]
# coords.reverse()

# intvp,py_fpga_cmds = p.main(coords)
# intvc,c_fpga_cmds = c.main(coords)
# print(py_fpga_cmds == c_fpga_cmds)
# py_path = c.fpga_to_pwl(py_fpga_cmds)
# c_path = c.fpga_to_pwl(c_fpga_cmds)

# print(py_path)
# print(c_path)
# path = c_path

# waves = p.decode_pwl_cmds(path)
# flat_wave = flatten(waves)
# split = lambda li: ([el[0] for el in li],[el[1] for el in li])
# x,t = split(coords)
# plt.scatter(t,x)
# plt.plot(flat_wave)
