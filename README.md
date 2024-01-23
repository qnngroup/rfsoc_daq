# rfsoc_daq

Firmware and python drivers for data acquisition system used in nanowire electronics experiments.
Notable features are an arbitrary waveform generator based on piecewise-linear signal descriptions, as well as a timetagging sample buffer that can store nanowire switching events sparsely to make efficient use of high-bandwidth on-chip block RAM.

## Structure

```
./
  src/
    rtl/                synthesizable modules and unit tests
    verif/              test-only code
    constraints/        XDC contraints
    pynq/               Python drivers and Jupyter notebook
  script/
    bitstream.sh        creates a temporary Vivado project and generates a bitstream
    unit.sh             creates a temporary Vivado project with the necessary simulation sources and runs one or more unit tests
    regression.sh       creates a temporary Vivado project and runs unit tests for all test modules in src/verif/
  README.md             this file
```
## Writing a new module

Create the module `my_module` in a file called `my_module.sv` (located in an appropriate subdirectory of `src/rtl/`), and a unit test module `my_module_test` in a file called `my_module_test.sv` (located in the same subdirectory as `my_module.sv`).

### Unit test architecture

Each unit test should create an instance of the `sim_util_pkg::debug` class to track errors in the module.
The `sim_util_pkg::debug` class offers 3 levels of verbosity: `DEFAULT` (lowest verbosity, good for regression tests or sanity checks), `VERBOSE` (medium verbosity), and `DEBUG` (highest verbosity, good if something is going wrong).

```
sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT);
```

The method `sim_util_pkg::debug.display(string msg, verbosity_t verbosity)` allows print statements to be generated at differing verbosity levels.
For example, if the method were called like so:

```
debug.display("Running test my_module_test", sim_util_pkg::DEFAULT);
```

then the message `Running test for module my_module` would always be printed out, regardless of what verbosity setting the instance `debug` is initialized with.
However, if the method were called like this

```
debug.display("Signal in submodule my_module_test.dut.dut_submodule is x", sim_util_pkg::VERBOSE);
```

then the message would only be printed if the `debug` was initialized with a verbosity setting of `VERBOSE` or `DEBUG`.
That is:

```
sim_util_pkg::debug debug = new(sim_util_pkg::VERBOSE);
// or
sim_util_pkg::debug debug = new(sim_util_pkg::DEBUG);
```

Here's a template:
```
`timescale 1ns / 1ps
module my_module_test ();

sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT);

logic reset;
logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

initial begin
  debug.display("### RUNNING TEST FOR MY_MODULE ", sim_util_pkg::DEFAULT);
  // run test
  ...

  debug.display("super verbose debug information to help debug when module breaks", sim_util_pkg::DEBUG);
  ...

  // check for an error, and report if so
  if (error) begin
    debug.error("error message");
  end

  // report total number of errors and exit the simulation with the appropriate exit code
  debug.finish();
end

endmodule
```

### Linting your module

To make sure you don't have any syntax errors and don't have sloppy coding practices, run the linter (`./script/lint.sh` from the repository root).
There are a couple violations that are ignored:
 - `INITIALDLY` in `*_test.sv`, `*_If.sv`, and `*/verif/*.sv` (this allows for the use of blocking assignments in initial blocks for code used in simulation, which is standard).
 - `MULTITOP` (this allows all of the modules to be linted)
 - `WIDTHEXPAND`, `WIDTHTRUNC`, and `WIDTHCONCAT` in `*_test.sv` and `*/verif/*.sv` (this allows for sloppier comparison/assignment regarding bitwidths of quantities in simulation-only code)


### Testing your module

Run `$ script/unit.sh my_module_test`. The script can be run from any directory, but it's preferrable to run it from either the repository root or the script directory to avoid cluttering other directories with Vivado log/journal files (the script will automatically clean any Vivado log files created in the repository root or in the script directory).

Also note that the unit test script can take a variable number of arguments, allowing for debugging of multiple modules simultaneously:

```
$ script/unit.sh my_module_test [other_module_test ...]
```

## Committing a new module

Make sure that the module works by running its unit test.
Also run a regression test to ensure that the new module (or any other code that was modified/created in the writing of the new module) does not break existing modules.

### Running a regression test

A full regression test (should be done before every commit or merge commit to main to ensure the proposed changes don't break anything) can be run like so:

```
$ script/regression.sh
```

This script generates a list of all test modules (named `[a-zA-Z0-9_]*_test`) in `src/` and passes them to the unit test script.
For this reason, it is important to name your unit tests following this naming scheme so that they are run in a regression test.
