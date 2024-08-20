#!/usr/bin/python3

import sys
import re

with open(sys.argv[1]) as fp:
    code = fp.readlines()

ios = []
clocks = []
resets = []
clock_groups = {}
ifnames = {}
directions = {}

save_lines = False
for line in code:
    line = line[:-1] # trim \n newline
    print(line)
    # if we're done with the module declaration, exit
    if ");" in line:
        break
    # only start saving after parameter list is closed
    # not robust if module doesn't have parameters
    if ")" in line and not(save_lines):
        save_lines = True
        continue
    if save_lines:
        # remove comments
        if re.search(r'^\s*//.*$', line) is not None:
            continue
        # remove empty lines
        if re.search(r'^\s*$', line) is not None:
            continue
        # strip to just signal name
        direction, io = re.sub(r'^\s*(in|out)put\s*logic\s*(\[[^\s]*\])*\s*([a-z0-9_]*),*$', r'\1:\3', line).split(':')
        print(direction, io)
        if "clk" in io:
            clock_groups[io] = []
            clocks.append(io)
        elif re.search(r'reset$', io) is not None:
            clock_groups[clocks[-1]].append(f'{io}n')
            clock_groups[clocks[-1]].append([])
            resets.append(io)
        else:
            ifname = "_".join(io.split("_")[:-1])
            ifnames[io] = ifname
            directions[io] = direction
            if ifname not in clock_groups[clocks[-1]][-1]:
                clock_groups[clocks[-1]][-1].append(ifname)
        ios.append(io)

print(ios)

with open("wrapper_temp.v", "w") as fp:
    for io in ios:
        if io in clocks:
            annotation = f'(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 {io} CLK" *)\n'
            annotation += f'(* X_INTERFACE_PARAMETER = "FREQ_HZ x, ASSOCIATED_BUSIF'
            for n, ifname in enumerate(clock_groups[io][-1]):
                annotation += f'\\\n{ifname}{":" if n < len(clock_groups[io][-1]) - 1 else ""}'
            annotation += '" *)\n'
            fp.write(annotation)
            fp.write(f'input wire {io},\n')
        elif io in resets:
            annotation = f'(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 {io} RST" *)\n'
            annotation += f'(* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)\n'
            fp.write(annotation)
            fp.write(f'input wire {io},\n')
        else:
            dtype = io.split('_')[-1].upper()
            annotation = f'(* X_INTERFACE_INFO = "xilinx.com:interface:axis_rtl:1.0 {ifnames[io]} {dtype}" *)\n'
            fp.write(annotation)
            fp.write(f'{directions[io]}put wire {io},\n')

    max_io_len = max(len(io) for io in ios)
    for io in ios:
        if io in resets:
            fp.write(f'.{io}{" "*(max_io_len-len(io))}(~{io}n),\n')
        else:
            fp.write(f'.{io}{" "*(max_io_len-len(io))}({io}),\n')
