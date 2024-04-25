cdef class Tup_List:
    cdef void *void_li
    cdef int li_len, tup_len

    def __cinit__(self, *args):
        self.tup_len = args[0]
        self.li_len = args[1]
        self.void_li = <void *> malloc(self.li_len*self.tup_len)
    def py_free(self):
        if self.void_li:
            free(self.void_li) 
            self.void_li = NULL
    def __len__(self): return self.li_len
    def __dealloc__(self): self.py_free()
    def __str__(self):
        out = "["
        for i in range(self.li_len):
            el = self.__getitem__(i)
            out+=str(el)
            if i == 100: 
                out+=" ..."
                break
            if i != self.li_len-1: out+=", "
        out+= "]"
        return out
    def __eq__(self, li):
        b1 = all([li[i] == self.__getitem__(i) for i in range(len(li))])
        return b1 and len(li) == self.li_len
    cdef int index_correct(self, int i):
        cdef int index 
        if i >= 0: index = i 
        else: index = self.li_len+i
        return index

cdef class Pwl_List(Tup_List):
    cdef pwl_tup *li 

    def __cinit__(self, *args): self.li = <pwl_tup *> self.void_li
    def py_free(self):
        super().py_free()
        self.li = NULL 
    def __getitem__(self,i): 
        to_tup = lambda di: tuple([e for e in di.values()])
        if type(i) == slice:
            out = []
            start = i.start if i.start else 0 
            stop = i.stop if i.stop is not None else len(self)
            step = i.step if i.step else 1
            for j in range(start,stop,step): out.append(to_tup(self.li[j]))
            return out 
        cdef int index = self.index_correct(i) 
        di = self.li[index]
        return to_tup(di)
    def __setitem__(self, i, tup):
        cdef int index = self.index_correct(i) 
        self.li[index].x = tup[0]
        self.li[index].slope = tup[1]
        self.li[index].dt = tup[2]
        self.li[index].sb = tup[3]
    cdef void set_item(self, int index, pwl_tup pt):
        cdef int i = self.index_correct(index)
        self.li[i].x = pt.x 
        self.li[i].slope = pt.slope
        self.li[i].dt = pt.dt 
        self.li[i].sb = pt.sb  
    cdef pwl_tup get_item(self, int index):
        cdef int i = self.index_correct(index)
        return self.li[i]

cdef class Coord_List(Tup_List):
    cdef coord_tup *li 

    def __cinit__(self, *args): self.li = <coord_tup *> self.void_li
    def py_free(self):
        super().py_free()
        self.li = NULL 
    def __getitem__(self,i): 
        cdef int index = self.index_correct(i) 
        di = self.li[index]
        return tuple([e for e in di.values()])
    def __setitem__(self, i, tup):
        cdef int index = self.index_correct(i) 
        self.li[index].x = tup[0]
        self.li[index].t = tup[1]
    cdef void set_item(self, int i, coord_tup ct):
        cdef int index = self.index_correct(i)
        self.li[index].x = ct.x 
        self.li[index].t = ct.t 
    cdef coord_tup get_item(self, int i):
        cdef int index = self.index_correct(i)
        return self.li[index]


##########################################################################################################################


def batchify_py(pwl_coords):
    batched_coords = []
    t = 0
    for (x,slope,dt,_) in pwl_coords:
        if t+dt >= batch_size:
            if t != 0:
                t_remain_in_batch = batch_size - t
                batched_coords.append((x,slope,t_remain_in_batch,0))
                x += slope*t_remain_in_batch
                dt -= t_remain_in_batch
            if dt >= batch_size:
                covered_batches,dt = (dt//batch_size, dt%batch_size)
                batched_coords.append((x,slope,batch_size*covered_batches,1))
                x += slope*(batch_size*covered_batches)
            batched_coords.append((x,slope,dt))
            return batched_coords
        else: batched_coords.append((x,slope,dt,0))
        t+=dt

def squash_sloped_points_py(pwl_coords):
    x1,slope1,dt1,_ = pwl_coords[0]
    new_coords = []
    pwl_coords.append((None,None,-1,None))
    for x2,slope2,dt2,_ in pwl_coords[1:]:
        new_coord = (x1,slope1,dt1,0)
        if slope1 == slope2:
            dt1 = dt1+dt2
        else:
            new_coords.append(new_coord)
            x1,slope1,dt1 = x2,slope2,dt2
        if dt2 == -1: break
    if len(new_coords) == 1:
        (x,slope,dt,_) = new_coords[0]
        new_coords = [(x,slope,dt,1)]
    return new_coords

def clean_path_py(path):
    cleaned_path = []
    pwl_batch_cmds = []
    batch_t = 0
    must_squash = False
    curr_slope = -1
    for i,cmd in enumerate(path):
        x,slope,dt,sb = cmd
        if dt == 0 and isfinite(slope): continue

        pwl_batch_cmds.append(cmd)
        batch_t+=dt
        if len(pwl_batch_cmds) >= 2 and curr_slope == slope: must_squash = True
        curr_slope = slope
        if batch_t >= batch_size:
            if must_squash:
                pwl_batch_cmds = squash_sloped_points_py(pwl_batch_cmds)
                must_squash = False
            if len(pwl_batch_cmds) == 1 and i < len(path)-1:
                _,_,_,nxt_sparse_bit = path[i+1]
                if nxt_sparse_bit == 1: continue
            cleaned_path += pwl_batch_cmds
            batch_t = 0
            pwl_batch_cmds = []
            curr_slope = -1
    return cleaned_path



    return path_ptr

# Given a list of incomplete pwl_coords of the form (x,dx/dt,dt,-1), creates as many batched coordinates
# (where dt is a multiple of batch_size) as possible and assigns all but the last to have a valid sparse_bit
# (since assignment of the last depends on the points that follow). Assumes function was called the moment sum of all t's in coords >= batch_size
# Returns the number of pwl_tups that were modified or changed in the passed pwl_coord list
cdef int batchify(Tup_List* batched_coords, int curr_len):
    cdef pwl_tup pwl_cmd
    cdef int batched_ptr = 0 
    cdef int t = 0
    cdef int x,slope,dt,t_remain_in_batch,covered_batches
    for i in range(curr_len+2):
        pwl_cmd = get_pwl_tup(batched_coords,i) 
        x = pwl_cmd.x
        slope = pwl_cmd.slope
        dt = pwl_cmd.dt

        if t+dt >= batch_size:
            if t != 0:
                t_remain_in_batch = batch_size - t
                pwl_cmd.dt = t_remain_in_batch
                pwl_cmd.sb = 0 
                set_item(batched_coords,batched_ptr,&pwl_cmd)
                batched_ptr+=1 
                pwl_cmd.x += slope*t_remain_in_batch
                dt -= t_remain_in_batch
            if dt >= batch_size:
                covered_batches= dt/batch_size
                dt = dt%batch_size
                pwl_cmd.dt = batch_size*covered_batches
                pwl_cmd.sb = 1 
                set_item(batched_coords,batched_ptr,&pwl_cmd)
                batched_ptr+=1 
                pwl_cmd.x += slope*(batch_size*covered_batches)
            pwl_cmd.dt = dt 
            pwl_cmd.sb = -1 
            set_item(batched_coords,batched_ptr,&pwl_cmd)
            batched_ptr+=1 
            return batched_ptr
        else: 
            pwl_cmd.sb = 0 
            set_item(batched_coords,batched_ptr,&pwl_cmd)
            batched_ptr+=1
        t+=dt

# Copies the first n elements of src into dst starting at strt_ptr
cdef int cpy_pwl_tups(Tup_List *src, Tup_List *dst, int strt_ptr, int n):
    if (dref(src).tup_type != PWL_TUP or dref(src).tup_type != dref(dst).tup_type): return -1
    cdef pwl_tup pwl_cmd
    for i in range(n):
        pwl_cmd = get_pwl_tup(src,i)
        set_item(dst,strt_ptr+i,&pwl_cmd)
    return 0 

# Given pwl_commands, returns new pwl_commands that ommit redundancies
# (ie when more than one command describes consecutive points on the same line, it will be squashed into one command).
cdef int squash_sloped_points(Tup_List *pwl_cmds, int n):
    cdef int x1,slope1,dt1,x2,slope2,dt2
    cdef int cmd_ptr = 0 
    cdef pwl_tup pwl_cmd = get_pwl_tup(pwl_cmds,0)
    x1 = pwl_cmd.x
    slope1 = pwl_cmd.slope
    dt1 = pwl_cmd.dt
    pwl_cmd.dt = -1
    set_item(pwl_cmds,n,&pwl_cmd)

    for i in range(1,n+1):
        pwl_cmd = get_pwl_tup(pwl_cmds,i)
        x2 = pwl_cmd.x
        slope2 = pwl_cmd.slope
        dt2 = pwl_cmd.dt
        if slope1 == slope2 and dt2 != -1: dt1 = dt1+dt2
        else: 
            pwl_cmd.x = x1 
            pwl_cmd.slope = slope1
            pwl_cmd.dt = dt1 
            pwl_cmd.sb = 0 
            set_item(pwl_cmds,cmd_ptr,&pwl_cmd)
            cmd_ptr+=1 
            x1 = x2
            slope1 = slope2
            dt1 = dt2
        if dt2 == -1: break 

    if cmd_ptr == 1: 
        pwl_cmd = get_pwl_tup(pwl_cmds,0)
        pwl_cmd.sb = 1 
        set_item(pwl_cmds,0,&pwl_cmd)
    return cmd_ptr


# Given a path with els of the form (x,dx/dt,dt,sparse_bit), cleans up by and squishing pwl commands together
# if they fall within the same batch and have same slope (pwl_commands in path should already be batched)
cdef int clean_path(Tup_List *path, int n):
    cdef Tup_List pwl_batch_cmds = Tup_List_Constructor(PWL_TUP, n)
    cdef Tup_List cleaned_path = Tup_List_Constructor(PWL_TUP, n)
    cdef pwl_tup pwl_cmd
    cdef int8_t must_squash = 0 
    cdef int batch_t = 0
    cdef int curr_slope = -1
    cdef int batch_ptr = 0 
    cdef int cpath_ptr = 0
    for i in range(n): 
        pwl_cmd = get_pwl_tup(path,i)
        if pwl_cmd.dt == 0: continue 
        set_item(&pwl_batch_cmds,batch_ptr,&pwl_cmd)
        batch_ptr+=1
        batch_t+=pwl_cmd.dt    
        
        if batch_ptr >= 2 and curr_slope == pwl_cmd.slope: must_squash = 1
        curr_slope = pwl_cmd.slope 

        if batch_t >= batch_size:
            if must_squash:
                batch_ptr = squash_sloped_points(&pwl_batch_cmds,batch_ptr)
                must_squash = 0

            if batch_ptr == 1 and i < n-1:
                pwl_cmd = get_pwl_tup(path,i+1)
                if pwl_cmd.sb == 1: continue
            cpy_pwl_tups(&pwl_batch_cmds,&cleaned_path,cpath_ptr,batch_ptr)
            cpath_ptr+=batch_ptr
            batch_t = 0
            batch_ptr = 0 
            curr_slope = -1
    destroy_tupli(pwl_batch_cmds)
    cpy_pwl_tups(&cleaned_path,path,0,cpath_ptr)
    destroy_tupli(cleaned_path)
    return cpath_ptr 


# Given coords of the form (x,t) that describe a wave, produces pwl_coords of the form (x,dx/dt,dt,sparse_bit).
# Also produces a list of hex numbers (representing the same pwl commands) that can be sent to the FPGA.
# Bitwidths look like (16,16,16,1)
cdef int mk_pwl_cmds(Tup_List* coords, Tup_List* path):
    cdef int pwl_list_len = dref(path).li_len
    if pwl_list_len > batch_size: pwl_list_len = batch_size 
    cdef Tup_List pwl_cmd_buff = Tup_List_Constructor(PWL_TUP, pwl_list_len)

    cdef int i = dref(coords).li_len-1
    cdef int x1,t1,x2,t2,dx,dt,slope,t,tups_to_cpy
    cdef coord_tup coord = get_coord_tup(coords,i)
    cdef pwl_tup pwl_cmd
    x1 = coord.x 
    t1 = coord.t
    cdef int batch_t = 0 
    cdef int pbuff_ptr = 0 
    cdef int path_ptr = 0 
    i-=1 
    # Fill up path with (x,slope,dt,sparse_bit) points
    while i >= 0:  
        coord = get_coord_tup(coords,i)
        x2 = coord.x 
        t2 = coord.t 
        dx = x2-x1
        dt = t2-t1
        slope = round_slope(<float>(<float>dx)/(<float>dt))
        # If out of bounds:
        if (slope > 0 and x1+slope*(dt-1) > x2) or (slope < 0 and x1+slope*(dt-1) < x2):
            t = 0
            if slope > 0:
                while x1+slope*(t+1) <= x2: t+=1
            else:
                while x1+slope*(t+1) >= x2: t+=1
            coord.x = x1+slope*t 
            coord.t = t1+t 
            set_item(coords,i+1,&coord)
            i+=1
            continue
        # Build pwl command buffer until a batch is reached, then batchify, add to path, and reset 
        pwl_cmd.x = x1 
        pwl_cmd.slope = slope 
        pwl_cmd.dt = dt 
        pwl_cmd.sb = -1 
        set_item(&pwl_cmd_buff,pbuff_ptr,&pwl_cmd)
        pbuff_ptr+=1 
        batch_t+=dt
        
        if batch_t >= batch_size: 
            tups_to_cpy = batchify(&pwl_cmd_buff, pbuff_ptr)
            cpy_pwl_tups(&pwl_cmd_buff, path, path_ptr, tups_to_cpy-1)
            path_ptr+=(tups_to_cpy-1)

            pwl_cmd = get_pwl_tup(&pwl_cmd_buff,tups_to_cpy-1)
            set_item(&pwl_cmd_buff,0,&pwl_cmd)
            pbuff_ptr = 1 
            batch_t = pwl_cmd.dt 
        # Move onto next point 
        x1 = x2
        t1 = t2 
        i-=1

    # Fill in last batch 
    batch_t = 0 
    for j in range(pbuff_ptr): 
        pwl_cmd = get_pwl_tup(&pwl_cmd_buff,j)
        batch_t+=pwl_cmd.dt 
    pwl_cmd.x = x2 
    pwl_cmd.slope = 0 
    pwl_cmd.dt = batch_size-batch_t 
    pwl_cmd.sb = -1
    set_item(&pwl_cmd_buff,pbuff_ptr,&pwl_cmd)
    pbuff_ptr+=1  
    tups_to_cpy = batchify(&pwl_cmd_buff,pbuff_ptr)
    cpy_pwl_tups(&pwl_cmd_buff, path, path_ptr, tups_to_cpy-1)
    path_ptr+=(tups_to_cpy-1)

    # Clean the path (connect points together and remove nonsensical commands (where dt = 0))
    path_ptr = clean_path(path,path_ptr)
    # Connect last added point if neccessary
    pwl_cmd = get_pwl_tup(path,path_ptr-1)
    x = pwl_cmd.x 
    slope = pwl_cmd.slope 
    dt = pwl_cmd.dt 
    if pwl_cmd.sb: 
        pwl_cmd = get_pwl_tup(path,path_ptr-2)
        if slope == pwl_cmd.slope: 
            pwl_cmd.x = x 
            pwl_cmd.dt += dt 
            pwl_cmd.sb = 1
            path_ptr-=1 
            set_item(path,path_ptr-1,&pwl_cmd)
    destroy_tupli(pwl_cmd_buff)
    return path_ptr 
    # Make hex commands


def mk_pwl_cmds(coords):
    for x,slope,dt,sb in path:
            if dt == 0: continue
            cmd = ""
            x,slope,dt = [toBin(el,sample_width) for el in [x,slope,dt]]
            for el in [x,slope,dt]: cmd+=el
            sb = "1" if sb else "0"
            cmd+=sb
            cmd = eval("0b"+cmd)
            path_cmds.append(cmd)
    return path,path_cmds