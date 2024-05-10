from math import ceil,floor
from time import perf_counter
from random import randrange as rr
from pwl_wrapper import get_bs
batch_size = get_bs()

def round_slope(slope): 
    if ((slope < -1) or (slope > 0 and slope < 1)): return ceil(slope)
    return floor(slope)

def gen_rand_coords(avg_dt=100,T=500,n=5,max_val=2**15-1):
    coords = [(0,0)]
    abs_t = 0
    for i in range(n):
        t = rr(1,avg_dt)
        x = rr(0,max_val)
        abs_t+=t
        coords.append((x,abs_t))
    return coords   

# Given a list of incomplete pwl_coords of the form (x,dx/dt,dt,-1), creates as many batched coordinates
# (where dt is a multiple of batch_size) as possible and assigns all but the last to have a valid sparse_bit
# (since assignment of the last depends on the points that follow). Assumes function was called the moment sum of all t's in coords >= batch_size
# Returns the number of pwl_tups that were modified or changed in the passed pwl_coord list
def batchify(batched_coords, curr_len):
    batched_ptr = 0 
    t = 0
    x,slope,dt,t_remain_in_batch,covered_batches = [0]*5
    for i in range(curr_len+2):
        pwl_cmd = batched_coords[i] 
        x = pwl_cmd["x"]
        slope = pwl_cmd["slope"]
        dt = pwl_cmd["dt"]

        if t+dt >= batch_size:
            if t != 0:
                t_remain_in_batch = batch_size - t
                pwl_cmd["dt"] = t_remain_in_batch
                pwl_cmd["sb"] = 0 
                batched_coords[batched_ptr] = pwl_cmd.copy()
                batched_ptr+=1 
                pwl_cmd["x"] += slope*t_remain_in_batch
                dt -= t_remain_in_batch
            if dt >= batch_size:
                covered_batches= dt//batch_size
                dt = dt%batch_size
                pwl_cmd["dt"] = batch_size*covered_batches
                pwl_cmd["sb"] = 1 
                batched_coords[batched_ptr] = pwl_cmd.copy()
                batched_ptr+=1 
                pwl_cmd["x"] += slope*(batch_size*covered_batches)
            pwl_cmd["dt"] = dt 
            pwl_cmd["sb"] = -1 
            batched_coords[batched_ptr] = pwl_cmd.copy()
            batched_ptr+=1 
            return batched_ptr
        else: 
            pwl_cmd["sb"] = 0 
            batched_coords[batched_ptr] = pwl_cmd.copy()
            batched_ptr+=1
        t+=dt

# Copies the first n elements of src into dst starting at strt_ptr
def cpy_pwl_tups(src, dst, strt_ptr, n):
    for i in range(n):
        dst[strt_ptr+i] = src[i]
    return 0 

# Given pwl_commands, returns new pwl_commands that ommit redundancies
# (ie when more than one command describes consecutive points on the same line, it will be squashed into one command).
def squash_sloped_points(pwl_cmds, n):
    x1,slope1,dt1,x2,slope2,dt2 = [0]*6
    cmd_ptr = 0 
    pwl_cmd = pwl_cmds[0]
    x1 = pwl_cmd["x"]
    slope1 = pwl_cmd["slope"]
    dt1 = pwl_cmd["dt"]
    pwl_cmd["dt"] = -1
    pwl_cmds[n] = pwl_cmd.copy()

    for i in range(1,n+1):
        pwl_cmd = pwl_cmds[i]
        x2 = pwl_cmd["x"]
        slope2 = pwl_cmd["slope"]
        dt2 = pwl_cmd["dt"]
        if slope1 == slope2 and dt2 != -1: dt1 = dt1+dt2
        else: 
            pwl_cmd["x"] = x1 
            pwl_cmd["slope"] = slope1
            pwl_cmd["dt"] = dt1 
            pwl_cmd["sb"] = 0 
            pwl_cmds[cmd_ptr] = pwl_cmd.copy()
            cmd_ptr+=1 
            x1 = x2
            slope1 = slope2
            dt1 = dt2
        if dt2 == -1: break 

    if cmd_ptr == 1: 
        pwl_cmd = pwl_cmds[0]
        pwl_cmd["sb"] = 1 
        pwl_cmds[0] = pwl_cmd.copy()
    return cmd_ptr


# Given a path with els of the form (x,dx/dt,dt,sparse_bit), cleans up by and squishing pwl commands together
# if they fall within the same batch and have same slope (pwl_commands in path should already be batched)
def clean_path(path, n):
    pwl_cmd = {"x":0,"slope":0,"dt":0,"sb":-1}
    pwl_batch_cmds = []
    cleaned_path = []
    for i in range(n): 
        pwl_batch_cmds.append(pwl_cmd.copy())
        cleaned_path.append(pwl_cmd.copy())
    batch_t = 0
    curr_slope = -1
    batch_ptr = 0 
    cpath_ptr = 0
    must_squash = 0
    for i in range(n):
        pwl_cmd = path[i] 
        if pwl_cmd["dt"] == 0: continue 
        pwl_batch_cmds[batch_ptr] = pwl_cmd.copy()
        batch_ptr+=1
        batch_t+=pwl_cmd["dt"]    
        
        if batch_ptr >= 2 and curr_slope == pwl_cmd["slope"]: must_squash = 1
        curr_slope = pwl_cmd["slope"] 

        if batch_t >= batch_size:
            if must_squash:
                batch_ptr = squash_sloped_points(pwl_batch_cmds,batch_ptr)
                must_squash = 0

            if batch_ptr == 1 and i < n-1:
                pwl_cmd = path[i+1]
                if pwl_cmd["sb"] == 1: continue
            cpy_pwl_tups(pwl_batch_cmds,cleaned_path,cpath_ptr,batch_ptr)
            cpath_ptr+=batch_ptr
            batch_t = 0
            batch_ptr = 0 
            curr_slope = -1
    pwl_batch_cmds = []
    cpy_pwl_tups(cleaned_path,path,0,cpath_ptr)
    cleaned_path = []
    return cpath_ptr 


# Given coords of the form (x,t) that describe a wave, produces pwl_coords of the form (x,dx/dt,dt,sparse_bit).
# Also produces a list of hex numbers (representing the same pwl commands) that can be sent to the FPGA.
# Bitwidths look like (16,16,16,1)
def mk_pwl_cmds(coords, path):
    pwl_list_len = len(path)
    if pwl_list_len > batch_size: pwl_list_len = batch_size 
    pwl_cmd = {"x":0,"slope":0,"dt":0,"sb":-1}
    pwl_cmd_buff = []
    for i in range(pwl_list_len): pwl_cmd_buff.append(pwl_cmd.copy())

    i = len(coords)-1
    coord = coords[i].copy()
    x1 = coord["x"] 
    t1 = coord["t"]
    batch_t = 0 
    pbuff_ptr = 0 
    path_ptr = 0 
    i-=1
    
    # Fill up path with (x,slope,dt,sparse_bit) points
    while i >= 0:  
        coord = coords[i].copy()
        x2 = coord["x"] 
        t2 = coord["t"] 
        dx = x2-x1
        dt = t2-t1
        slope = round_slope(dx/dt)
        # If out of bounds:
        if (slope > 0 and x1+slope*(dt-1) > x2) or (slope < 0 and x1+slope*(dt-1) < x2):
            t = 0
            if slope > 0:
                while x1+slope*(t+1) <= x2: t+=1
            else:
                while x1+slope*(t+1) >= x2: t+=1
            coord["x"] = x1+slope*t 
            coord["t"] = t1+t 
            coords[i+1] = coord.copy()
            i+=1
            continue
        # Build pwl command buffer until a batch is reached, then batchify, add to path, and reset 
        pwl_cmd["x"] = x1 
        pwl_cmd["slope"] = slope 
        pwl_cmd["dt"] = dt 
        pwl_cmd["sb"] = -1 
        pwl_cmd_buff[pbuff_ptr] = pwl_cmd.copy()
        pbuff_ptr+=1 
        batch_t+=dt
        
        if batch_t >= batch_size: 
            tups_to_cpy = batchify(pwl_cmd_buff, pbuff_ptr)
            cpy_pwl_tups(pwl_cmd_buff, path, path_ptr, tups_to_cpy-1)
            path_ptr+=(tups_to_cpy-1)

            pwl_cmd = pwl_cmd_buff[tups_to_cpy-1] 
            pwl_cmd_buff[0] = pwl_cmd.copy()
            pbuff_ptr = 1 
            batch_t = pwl_cmd["dt"] 
        # Move onto next point 
        x1 = x2
        t1 = t2 
        i-=1

    # Fill in last batch 
    batch_t = 0 
    for j in range(pbuff_ptr): 
        pwl_cmd = pwl_cmd_buff[j].copy()
        batch_t+=pwl_cmd["dt"] 
    pwl_cmd["x"] = x2 
    pwl_cmd["slope"] = 0 
    pwl_cmd["dt"] = batch_size-batch_t 
    pwl_cmd["sb"] = -1
    pwl_cmd_buff[pbuff_ptr] = pwl_cmd.copy()
    pbuff_ptr+=1  
    tups_to_cpy = batchify(pwl_cmd_buff,pbuff_ptr)
    cpy_pwl_tups(pwl_cmd_buff, path, path_ptr, tups_to_cpy-1)
    path_ptr+=(tups_to_cpy-1)
    # Clean the path (connect points together and remove nonsensical commands (where dt = 0))
    path_ptr = clean_path(path,path_ptr)
    # Connect last added point if neccessary
    pwl_cmd = path[path_ptr-1]
    x = pwl_cmd["x"] 
    slope = pwl_cmd["slope"] 
    dt = pwl_cmd["dt"] 
    if pwl_cmd["sb"]: 
        pwl_cmd = path[path_ptr-2]
        if slope == pwl_cmd["slope"]: 
            pwl_cmd["x"] = x 
            pwl_cmd["dt"] += dt 
            pwl_cmd["sb"] = 1
            path_ptr-=1 
            path[path_ptr-1] = pwl_cmd.copy()
    pwl_cmd_buff = []
    return path_ptr 

def mk_fpga_cmds(pwl_cmds):
    fpga_cmds = []
    for x,slope,dt,sb in pwl_cmds: 
        x1,slope1,dt1 = x,slope,dt

        if x < 0: x = 0x10000+x 
        x = x<<(8*4) 
        if slope < 0: slope = 0x10000+slope
        slope = slope<<(4*4)
        dt = (dt<<1)+sb
        if dt & 0x8000: dt -= 0x8000
        fpga_cmds.append(x+slope+dt)
    return fpga_cmds
        

def batchify_fast(pwl_cmd):
    clean_dt = (pwl_cmd["dt"]//batch_size)*batch_size
    if clean_dt == 0:
        pwl_cmd["sb"] = 0 
        return 0,0 
    leftover_dt = pwl_cmd["dt"]-clean_dt 
    newx = pwl_cmd["x"]+pwl_cmd["slope"]*clean_dt
    pwl_cmd["dt"] = clean_dt
    pwl_cmd["sb"] = 1
    return newx,leftover_dt 

def mk_pwl_cmds_fast(coords, path):
    i = len(coords)-1
    coord = coords[i].copy()
    x1 = coord["x"] 
    t1 = coord["t"]
    batch_t = 0 
    path_ptr = 0 
    skip_calc = False
    pwl_cmd = {"x":-1,"slope":-1,"dt":-1,"sb":-1}
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
                slope = round_slope(dx/dt)
                # If out of bounds:
                if (slope > 0 and x1+slope*(dt-1) > x2) or (slope < 0 and x1+slope*(dt-1) < x2):
                    t = (x2-x1)//slope
                    coord["x"] = x1+slope*t 
                    coord["t"] = t1+t 
                    coords[i+1] = coord.copy()
                    i+=1
                    continue

            # See if we must grow the current pwl_cmd before adding to path 
            if pwl_cmd["dt"] == -1:
                pwl_cmd["x"] = x1 
                pwl_cmd["slope"] = slope 
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
                ending_x = prev_pwl_cmd["x"]+prev_pwl_cmd["slope"]*(prev_pwl_cmd["dt"]-1)
                if ending_x == x2: break 
            left_in_batch = batch_size-batch_t
            pwl_cmd["x"] = x2
            pwl_cmd["sb"] = 1 if left_in_batch == batch_size else 0
            # If the last slope was 0, we can consolidate 
            if pwl_cmd["slope"] == 0:
                # If the only thing in the batch we have to finish is a cmd with 0 slope, fill it all with this. 
                if pwl_cmd["dt"] == batch_t:
                    pwl_cmd["dt"] = batch_size
                    pwl_cmd["sb"] = 1
                    prev_pwl_cmd = path[path_ptr-2]
                    if prev_pwl_cmd["slope"] == 0 and prev_pwl_cmd["sb"]: 
                        prev_pwl_cmd["dt"]+=batch_size
                        path_ptr-=1
                        pwl_cmd = prev_pwl_cmd.copy()
                else: pwl_cmd["dt"]+=left_in_batch
                path[path_ptr-1] = pwl_cmd.copy()
                break
            pwl_cmd["dt"] = left_in_batch
            pwl_cmd["slope"] = 0
            path[path_ptr] = pwl_cmd.copy()
            path_ptr+=1
            break 
         
        # When are we allowed to add sparse cmds? If the current batch isn't fragmented and the current pwl_cmd would fill atleast 1 full batch
        if batch_t >= batch_size or (batch_t == 0 and pwl_cmd["dt"] >= batch_size):
            newx, leftover_dt = batchify_fast(pwl_cmd)
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
                pwl_cmd["x"] += pwl_cmd["slope"]*left_in_batch
                pwl_cmd["dt"] = full_pwlcmd_dt-left_in_batch
                pwl_cmd["sb"] = -1
                skip_calc = True
                continue 
            
        # Move onto next point (if there is one)
        if i > -1:
            pwl_cmd["x"] = x1
            pwl_cmd["slope"] = slope
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
    l = mk_pwl_cmds_fast(coords,path_wrapper)
    path = toLi(path_wrapper,l)
    fpga_cmds = mk_fpga_cmds(path)
    intv = perf_counter() - t0
    coords = [] 
    return intv,fpga_cmds


def toLi(path,n): 
    out = []
    for i,di in enumerate(path):
        if i >= n: break
        el = tuple([e for e in di.values()])
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

#############################################################

coords = [(0,0), (300,300), (300,1000),(0,5800), (0, 6500)]
# coords = gen_rand_coords(n=50)
coords.reverse()
intv,fpga_cmds = main(coords)


