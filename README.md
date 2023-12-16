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
    bitstream.sh        creates a temporary Vivado project and generates a bitstream
    unit.sh             creates a temporary Vivado project with the necessary simulation sources and runs one or more unit tests
    regression.sh       creates a temporary Vivado project and runs unit tests for all test modules in src/verif/
  README.md             this file
```
## Writing a new module

Create the module `my_module` in a file called `my_module.sv` (located in `src/rtl/`), and a unit test module `my_module_test` in a file called `my_module_test.sv` (located in `src/verif/`).

### Unit test architecture

Each unit test should create an instance of the `sim_util_pkg::debug` class to track errors in the module.
The `sim_util_pkg::debug` class offers 3 levels of verbosity: `DEFAULT` (lowest verbosity, good for regression tests or sanity checks), `VERBOSE` (medium verbosity), and `DEBUG` (highest verbosity, good if something is going wrong).

```
sim_util_pkg::debug #(.VERBOSITY(DEFAULT)) dbg = new;
```

The method `sim_util_pkg::debug.display(string msg, verbosity_t verbosity)` allows print statements to be generated at differing verbosity levels.
For example, if the method were called like so:

```
dbg.display("Running test my_module_test", DEFAULT);
```

then the message `Running test for module my_module` would always be printed out, regardless of what verbosity setting the instance `dbg_i` is initialized with.
However, if the method were called like this

```
dbg.display("Signal in submodule my_module_test.dut.dut_submodule is x", VERBOSE);
```

then the message would only be printed if the `dbg_i` was initialized with a verbosity setting of `VERBOSE` or `DEBUG`.

Here's a template:
```
import sim_util_pkg::*;

`timescale 1ns / 1ps
module my_module_test ();

sim_util_pkg::debug #(.VERBOSITY(DEFAULT)) dbg = new;

logic reset;
logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

initial begin
  dbg.display("running test for my_module_test", DEFAULT);
  // run test
  ...

  dbg.display("super verbose debug information", DEBUG);
  ...

  // check for an error, and report if so
  if (error) begin
    dbg.error("error message");
  end

  // report total number of errors and exit the simulation
  dbg.finish();
end

endmodule
```

### Testing your module

Run `$ script/unit.sh my_module_test`. The script can be run from any directory, but it's preferrable to run it from either the repository root or the script directory to avoid cluttering other directories with Vivado log/journal files.

Also note that the unit test script can take a variable number of arguments, allowing for debugging of multiple modules simultaneously:

```
$ script/unit.sh my_module_test [other_module_test ...]
```

## Committing a new module

Make sure that the module works by running its unit test.
Also run a regression test to ensure that the new module (or any other code that was modified/created in the writing of the new module) does not break existing modules.

### Running a regression test

A full regression test (should be done before every commit) can be run like so:

```
$ script/regression.sh
```

This script generates a list of all test modules (named `[a-zA-Z0-9_]*_test`) located in `src/verif/` and passes them to the unit test script.
