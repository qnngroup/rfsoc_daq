from libc.stdlib cimport malloc, free
from libc.math cimport ceil,floor
from libc.stdint cimport int8_t
from math import isfinite
from cython.operator import dereference as dref
from time import perf_counter 
from sys import path
path.insert(0, r'C:\Users\skand\OneDrive\Documents\GitHub\rfsoc_daq\src\stephen_rtl\Python_Files')
from fpga_constants import dma_data_width, fixed_point_percision, batch_size as bs 

##################################### Classes and Method Defs  ############################################

ctypedef unsigned long long uint64
ctypedef long long int64

cdef struct s_slope_obj:
    int8_t sign
    int whole
    double fract
ctypedef s_slope_obj slope_obj

cdef struct s_pwl_tuple:
    int x,dt
    slope_obj slope 
    int8_t sb
    uint64 fpga_cmd
ctypedef s_pwl_tuple pwl_tup

cdef struct s_coord_tuple:
    int x,t
ctypedef s_coord_tuple coord_tup

cdef int batch_size = <int> bs

cdef enum Tup_Type:
    COORD_TUP,
    PWL_TUP

cdef struct tup_list:
    int li_len, tup_size
    void *li
    Tup_Type tup_type 
ctypedef tup_list Tup_List 

cdef void set_item(Tup_List *tl, int i, void* el):
    if dref(tl).tup_type == PWL_TUP: (<pwl_tup*>(dref(tl).li))[i] = dref(<pwl_tup*>el) 
    if dref(tl).tup_type == COORD_TUP: (<coord_tup*>(dref(tl).li))[i] = dref(<coord_tup*>el)

cdef pwl_tup get_pwl_tup(Tup_List *tl, int i): return (<pwl_tup*>(dref(tl).li))[i]
cdef coord_tup get_coord_tup(Tup_List *tl, int i): return (<coord_tup*>(dref(tl).li))[i] 

cdef Tup_List Tup_List_Constructor(Tup_Type tup_type, int li_len):
    cdef Tup_List tupli
    cdef int tup_size = sizeof(pwl_tup) if tup_type == PWL_TUP else sizeof(coord_tup)
    tupli.li = <void*> malloc(tup_size*li_len)
    tupli.tup_type = tup_type
    tupli.li_len = li_len
    tupli.tup_size = tup_size 
    return tupli

cdef void destroy_tupli(Tup_List tl):
    if tl.li: 
        free(tl.li)
        tl.li = NULL 

cdef Tup_List create_c_coords(py_coords):
    cdef int size = len(py_coords)
    cdef Tup_List tl = Tup_List_Constructor(COORD_TUP, size)
    cdef coord_tup ct 
    cdef int i = 0
    cdef int x,t 
    for i in range(tl.li_len): 
        x,t = py_coords[i]
        ct = {"x": x, "t": t}
        set_item(&tl,i,&ct)
    return tl

cdef slope_obj cpy_slope(slope_obj slope):
    cdef slope_obj cpy 
    cpy.sign = slope.sign 
    cpy.whole = slope.whole
    cpy.fract = slope.fract
    return cpy 

cdef slope_obj create_slope_obj(double slope_in):
    cdef slope_obj slope
    slope.sign = 1 if slope_in > 0 else -1  
    slope.whole = <int>floor(slope_in) if slope.sign > 0 else <int>ceil(slope_in)
    slope.fract = round(slope.whole-slope_in,fixed_point_percision)
    slope.whole = abs(slope.whole)
    slope.fract = abs(slope.fract)
    return slope

cdef int scale(slope_obj slope,int i):
    cdef int out
    out = slope.sign*slope.whole*i
    out+= slope.sign*<int>floor(slope.fract*i)
    return out

cdef int8_t is_zero_slope(slope_obj slope): return slope.whole == 0 and slope.fract == 0.0

cdef int64 inv_num(int64 num, int bit_width):
    cdef int64 mask = ((<int64>1)<<bit_width)-1
    num = (abs(num) ^ mask)+1
    return num

cdef uint64 double_to_fixed(double num,int m, int n): 
    cdef uint64 raw_fixed = round(abs(num)*(2**n))
    if num < 0: raw_fixed = inv_num(raw_fixed,m+n)   
    return raw_fixed
    
cdef tupli_to_li(Tup_List* li, int n):
    out = []
    cdef pwl_tup e 
    for i in range(n):
        e = get_pwl_tup(li,i)
        el = (e.x,e.slope,e.dt,e.sb)
        out.append(el)
    return out

cdef class TupLiWrapper:
    cdef Tup_List tl

    def __cinit__(self, Tup_Type tup_type, int li_len): 
        self.tl = Tup_List_Constructor(tup_type, li_len)
    def __dealloc__(self): destroy_tupli(self.tl)
    def to_pylist(self):
        li = []
        cdef coord_tup ct
        cdef pwl_tup pt
        for i in range(self.tl.li_len):
            if self.tl.tup_type == COORD_TUP:
                ct = (<coord_tup*> self.tl.li)[i]
                li.append((ct.x,ct.t))
            if self.tl.tup_type == PWL_TUP:
                pt = (<pwl_tup*> self.tl.li)[i]
                li.append((pt.x,pt.slope,pt.dt,pt.sb))
        return li
    def __str__(self): return str(self.to_pylist())
    def __len__(self): return self.tl.li_len
    def __getitem__(self,i): 
        li = self.to_pylist()
        return li[i] 
    def __setitem__(self,i,el): 
        cdef coord_tup ct
        cdef pwl_tup pt
        if self.tl.tup_type == COORD_TUP:
            x,t = el 
            ct = {"x": x, "t": t}
            (<coord_tup*>(self.tl.li))[i] = ct 
        if self.tl.tup_type == PWL_TUP:
            x,slope,dt,sb = el 
            pt = {"x": x, "slope":slope, "dt": dt, "sb":sb}
            (<pwl_tup*>(self.tl.li))[i] = pt 

##################################### PWL C Functions  ############################################

cdef void printTL(Tup_List* tl, int n):
    cdef pwl_tup pwl_cmd
    li = [] 
    cdef double slope 
    for i in range(n):
        pwl_cmd = get_pwl_tup(tl,i)
        slope = pwl_cmd.slope.sign*(pwl_cmd.slope.whole+pwl_cmd.slope.fract)
        li.append((pwl_cmd.x,slope,pwl_cmd.dt,pwl_cmd.sb))
    print(li)

cdef int8_t are_slopes_eq(slope_obj slope1, slope_obj slope2): return slope1.sign == slope2.sign and slope1.whole == slope2.whole and slope1.fract == slope2.fract 

cdef void batchify(pwl_tup* pwl_cmd, int* newx, int* leftover_dt):
    cdef int clean_dt = <int> ((dref(pwl_cmd).dt/batch_size)*batch_size)
    if clean_dt == 0:
        dref(pwl_cmd).sb = 0 
        return  
    leftover_dt[0] = dref(pwl_cmd).dt-clean_dt 
    newx[0] = dref(pwl_cmd).x+scale(dref(pwl_cmd).slope,clean_dt)
    dref(pwl_cmd).dt = clean_dt
    dref(pwl_cmd).sb = 1
    
cdef int mk_pwl_cmds(Tup_List* coords, Tup_List* path):
    cdef int i = coords.li_len-1
    cdef int batch_t = 0 
    cdef int path_ptr = 0 
    cdef bint skip_calc = 0
    cdef pwl_tup pwl_cmd,prev_pwl_cmd
    pwl_cmd.dt = -1 
    cdef coord_tup coord 
    cdef int x1,t1,x2,t2,dx,dt,t,left_in_batch,newx,leftover_dt,ending_x
    cdef slope_obj slope 
    slope.sign = 1
    slope.whole = 0
    slope.fract = 0.0 
    pwl_cmd.slope = cpy_slope(slope)
    prev_pwl_cmd.slope = cpy_slope(slope)
    
    coord = get_coord_tup(coords,i)
    x1 = coord.x 
    t1 = coord.t
    i-=1
    # Fill up path with (x,slope,dt,sparse_bit) points
    while i >= -2: 
        if i > -1:
            if skip_calc: skip_calc = 0
            else:
                coord = get_coord_tup(coords,i)
                x2 = coord.x 
                t2 = coord.t 
                dx = x2-x1
                dt = t2-t1
                slope = create_slope_obj(<double>(<double>dx)/(<double>dt))

            # See if we must grow the current pwl_cmd before adding to path 
            if pwl_cmd.dt == -1:
                pwl_cmd.x = x1 
                pwl_cmd.slope = cpy_slope(slope) 
                pwl_cmd.dt = dt 
                pwl_cmd.sb = -1 
                # Move onto next point 
                x1 = x2
                t1 = t2 
                i-=1
                continue 
            if are_slopes_eq(slope,pwl_cmd.slope):
                pwl_cmd.dt+=dt 
                # Move onto next point
                x1 = x2
                t1 = t2 
                i-=1
                continue

        # If i is -2, we've completed everything and just need to make sure the last batch gets filled in (if we're currently filling one)
        if i == -2:
            if batch_t == 0 or batch_t == batch_size: 
                prev_pwl_cmd = get_pwl_tup(path,path_ptr-1)
                ending_x = prev_pwl_cmd.x + scale(prev_pwl_cmd.slope,prev_pwl_cmd.dt - 1)
                if ending_x == x2: break
            left_in_batch = batch_size-batch_t
            pwl_cmd.x = x2
            if left_in_batch == batch_size: pwl_cmd.sb = 1 
            else: pwl_cmd.sb = 0 
            # If the last slope was 0, we can consolidate 
            if is_zero_slope(pwl_cmd.slope):
                # If the only thing in the batch we have to finish is a cmd with 0 slope, fill it all with this. 
                if pwl_cmd.dt == batch_t:
                    pwl_cmd.dt = batch_size
                    pwl_cmd.sb = 1
                    prev_pwl_cmd = get_pwl_tup(path,path_ptr-2)
                    if is_zero_slope(prev_pwl_cmd.slope) and prev_pwl_cmd.sb:
                        prev_pwl_cmd.dt+=batch_size
                        path_ptr-=1
                        pwl_cmd = prev_pwl_cmd 
                else: pwl_cmd.dt+=left_in_batch
                set_item(path,path_ptr-1,&pwl_cmd)
                break
            pwl_cmd.dt = left_in_batch
            pwl_cmd.slope.sign = 1
            pwl_cmd.slope.whole = 0
            pwl_cmd.slope.fract = 0.0
            set_item(path,path_ptr,&pwl_cmd)
            path_ptr+=1
            break 

        # When are we allowed to add sparse cmds? If the current batch isn't fragmented and the current pwl_cmd would fill atleast 1 full batch
        if batch_t >= batch_size or (batch_t == 0 and pwl_cmd.dt >= batch_size):
            batchify(&pwl_cmd,&newx,&leftover_dt)
            set_item(path,path_ptr,&pwl_cmd)
            path_ptr+=1 
            batch_t = 0
            if leftover_dt != 0:
                # This means the current pwl_cmd was batchified but there's some overflow => it must still be handled 
                # Otherwise, the pwl_cmd filled up a perfect num of batches => move on to next point. 
                pwl_cmd.x = newx
                pwl_cmd.dt = leftover_dt  
                pwl_cmd.sb = -1 
                skip_calc = 1
                continue  
        else:
            if batch_t+pwl_cmd.dt <= batch_size: 
                # This means the pwl_cmd-to-add will not fully fill up a batch. So we add it, then consider the next pwl point.
                # (sb will surely be 0 since we'll need to fill the batch we're currently making)                
                pwl_cmd.sb = 0 
                set_item(path,path_ptr,&pwl_cmd)
                path_ptr+=1 
                batch_t+=pwl_cmd.dt
                if batch_t == batch_size: batch_t = 0
            else: 
                # This means the pwl_cmd-to-add will overflow the current batch. 
                # So we must complete the current batch, update the current pwl_cmd and continue (holding onto the next point)
                # (sb will be 1 if what's left of dt is enough to fill a batch, and 0 otherwise)
                left_in_batch = batch_size-batch_t
                full_pwlcmd_dt = pwl_cmd.dt
                pwl_cmd.dt = left_in_batch 
                pwl_cmd.sb = 0
                set_item(path,path_ptr,&pwl_cmd)
                path_ptr+=1 
                batch_t = 0
                pwl_cmd.x += scale(pwl_cmd.slope,left_in_batch)
                pwl_cmd.dt = full_pwlcmd_dt-left_in_batch
                pwl_cmd.sb = -1
                skip_calc = 1
                continue

        # Move onto next point (if there is one)
        if i > -1:
            pwl_cmd.x = x1
            pwl_cmd.slope = cpy_slope(slope)
            pwl_cmd.dt = dt 
            pwl_cmd.sb = -1 
            x1 = x2
            t1 = t2 
        i-=1
    return path_ptr

# Assuming a dma_width of 64 (x(16)+slope(32)+dt+sb(16))
cdef void mk_fpga_cmds(Tup_List* pwl_cmds, int n):
    cdef pwl_tup pwl_cmd
    cdef int64 x,dt,sb,slope
    cdef double slope_d  
    for i in range(n): 
        pwl_cmd = get_pwl_tup(pwl_cmds,i)
        x = pwl_cmd.x
        slope_d = pwl_cmd.slope.sign*(pwl_cmd.slope.whole+pwl_cmd.slope.fract)
        dt = pwl_cmd.dt
        sb = pwl_cmd.sb

        if x < 0: x = inv_num(x,16)
        x = x << (12*4) 
        slope = double_to_fixed(slope_d,16,16)
        slope = slope<<(4*4)
        dt = (dt << 1) + sb
        if dt & 0x8000: dt -= 0x8000
        pwl_cmd.fpga_cmd = x+slope+dt 
        set_item(pwl_cmds,i,&pwl_cmd)
    

##################################### Useful Functions and Main  ############################################

def create_c_coords_py(py_coords):
    cdef int size = len(py_coords)
    cdef TupLiWrapper tlw = TupLiWrapper(COORD_TUP, size)
    cdef Tup_List tl = tlw.tl 
    cdef coord_tup ct 
    cdef int i = 0
    cdef int x,t 
    for i in range(tl.li_len): 
        x,t = py_coords[i]
        ct = {"x": x, "t": t}
        set_item(&tl,i,&ct)
    return tlw

def decode_pwl_cmds(pwl_cmds):
    wave = []
    for x,slope,dt,_ in pwl_cmds:
        t = 0
        w = [] 
        slope = create_slope_obj(slope)
        while t < dt:
            w.append(x+scale(slope,t))
            t+=1 
        wave.append(w)
    return wave
    
def fixed_to_double(num,m,n):
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
        if x & 0x8000: x = -0x8000 + (x & 0x7fff)
        slope_mask = 0xffffffff << (4*4)
        slope = (num&slope_mask) >> (4*4)
        slope = fixed_to_double(slope,16,16)    
        dt_mask = 0xffff
        sb = num & 0b1
        dt = (num&dt_mask) >> 1
        pwl_cmds.append((x,slope,dt,sb)) 
    return pwl_cmds

def decode_pwl_cmds(pwl_cmds):
    wave = []
    batch = []
    for x,slope,dt,sb in pwl_cmds:
        t = 0
        while (t < dt):
            batch.append(x+slope*t)
            if len(batch) == batch_size:
                wave.append(batch)
                batch = []
            t+=1
    return wave

def expected_wave_formatter(pwl_cmds):
    wave = decode_pwl_cmds(pwl_cmds)
    out = f"logic[{len(wave)-1}:0][BATCH_SIZE-1:0][DATA_WIDTH-1:0] expected = {{"
    wave.reverse()
    for w in wave:
        w.reverse()
        out += "{"
        for el in w: out+=f"16'd{el}, "
        out = out[:-2] + "}, "
    out = out[:-2]+"};"
    return out 
    
def get_bs(): return batch_size

def main(coords):
    t0 = perf_counter() 
    cdef Tup_List cl = create_c_coords(coords)
    cdef Tup_List path = Tup_List_Constructor(PWL_TUP, (cl.li_len-1)*6)
    cdef int n = mk_pwl_cmds(&cl,&path)
    mk_fpga_cmds(&path,n)
    fpga_cmds = [0]*n
    for i in range(n): fpga_cmds[i] = ((<pwl_tup*>(path.li))[i]).fpga_cmd
    destroy_tupli(cl)
    destroy_tupli(path)
    intv = perf_counter() - t0
    return intv, fpga_cmds
    # cdef TupLiWrapper path_wrapper = TupLiWrapper(PWL_TUP, (cl.li_len-1)*6)
    # cdef int l = mk_pwl_cmds(&cl,&path_wrapper.tl)
    # intv = perf_counter() - t0 
    # destroy_tupli(cl)
    # return path_wrapper,l,intv
    