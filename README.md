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
## When writing a new module

Create the module `module` in a file called `module.sv` (located in `src/rtl/`), and a unit test module `module_test` in a file called `module_test.sv` (located in `src/verif/`).
Also add the test module name `module_test` to the list `test_module_list` in [`script/run_simulation.tcl`](script/run_simulation.tcl).

## Testing your module

Run vivado in batch mode, specifying the name of the test module as a TCL argument:

```
$ vivado -mode batch -source script/run_unit_test.tcl -tclargs module_test
```

## Running a regression test

Full regression test (should be done before every commit):

```
$ vivado -mode batch -source script/run_regression_test.tcl
```

Partial regression test (specific modules, may be useful for debugging changes):

```
$ vivado -mode batch -source script/run_unit_test.tcl -tclargs module1_test module2_test ...
```

