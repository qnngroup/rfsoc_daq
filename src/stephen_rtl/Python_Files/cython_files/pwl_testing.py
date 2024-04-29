import pwl_wrapper as c
import pwl_wrapper_python as p
import matplotlib.pyplot as plt
from matplotlib.font_manager import FontProperties
from math import ceil,floor
from random import randrange as rr
from time import time,sleep, perf_counter

batch_size = c.get_bs()

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

def gen_rand_coords(avg_dt=100,T=500,n=5,max_val=2**15-1):
    coords = [(0,0)]
    abs_t = 0
    for i in range(n):
        t = rr(1,avg_dt)
        x = rr(0,max_val)
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

def fpga_to_pwl(fpga_cmds):
    pwl_cmds = []
    for num in fpga_cmds:
        x_mask = 0xffff << (8*4)
        x = (num&x_mask) >> (8*4)
        if x & 0x8000: x = -0x8000 + (x & 0x7fff)
        slope_mask = 0xffff << (4*4)
        slope = (num&slope_mask) >> (4*4)
        if slope & 0x8000: slope = -0x8000 + (slope & 0x7fff)
        dt_mask = 0xffff
        sb = num & 0b1
        dt = (num&dt_mask) >> 1
        pwl_cmds.append((x,slope,dt,sb))
    return pwl_cmds

def test_coords(coords,do_plot=True,show_batches=False,simple_plot=False, ignore=[]):
    coords.reverse()
    intv,fpga_cmds = c.main(coords)
    path = fpga_to_pwl(fpga_cmds)
    py_intv,py_fpga_cmds = p.main(coords)
    py_path = fpga_to_pwl(py_fpga_cmds)
    waves = c.decode_pwl_cmds(path)
    flat_wave = flatten(waves)
    
    if do_plot:
        split = lambda li: ([el[0] for el in li],[el[1] for el in li])
        x,t = split(coords)
        plt.scatter(t,x)
        
        if simple_plot: plt.plot(flat_wave)
        else:
            abs_t = 0
            for wave in waves:
                t = [abs_t+el for el in range(len(wave))]
                plt.plot(t,wave)
                abs_t+=len(wave)

    wrong = []
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
    
    return path,passed,wrong,intv
##############################################################################################################################################

test_num = int(1e4)
nxt_perc = 10
t0 = time()
n = 15
intvs = []
for i in range(test_num):
    perc = (i/test_num)*100
    if round(perc) == nxt_perc: 
        print(f"{nxt_perc}%")
        nxt_perc+=10        
    coords = gen_rand_coords(n=n,avg_dt=200)
    ignore = ignore_same_sloped_points(coords)
    path,result,wrong,intv = test_coords(coords[:],do_plot=False,show_batches=True,simple_plot=False, ignore=ignore)
    intvs.append(intv)
    if not result:
        print("Failed")
        print(coords)
        print(wrong)
        break
else:
    print("Passed")
print(f"\nAvg Cython calc time:\n{round((sum(intvs)/len(intvs))*1e6,2)} us\n{round((sum(intvs)/len(intvs))*1e3,2)} ms")
print(f"\nTest time:\n{round(time()-t0,2)} s")















