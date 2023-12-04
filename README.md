# rfsoc_daq

Firmware and python drivers for data acquisition system used in nanowire electronics experiments.
Notable features are an arbitrary waveform generator based on piecewise-linear signal descriptions, as well as a timetagging sample buffer that can store nanowire switching events sparsely to make efficient use of high-bandwidth on-chip block RAM.

## Structure

```
./
  src/
    rtl/                synthesizable hardware description
    verif/              test-only code
    constraints/        XDC contraints
    pynq/               Python drivers and Jupyter notebook
  script/
    run_bitstream.sh    creates a temporary Vivado project and generates a bitstream
    run_simulation.sh   creates a temporary Vivado project with the necessary simulation sources
  README.md             this file
```

