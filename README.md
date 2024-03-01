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

## Installation/setup

Clone repository with
```
$ git clone git@github.com:qnngroup/rfsoc_daq.git
```

### Tools
Linting is performed with [`verible-verilog-lint`](https://github.com/chipsalliance/verible) (`v0.0-3567-gfeb51185`) and [`slang`](https://sv-lang.com/) (`5.0.33+f904c154`).
Both tools are already installed on the lab computer, but to run linting on your personal machine, you will need to install them.
Verible already has prebuilt packages for Windows, macOS, and Linux, but slang requires building from source.
The latest version of slang uses features of C++20, and thus requires a recent version of gcc/clang to be installed.

### Pre-commit hooks
To prevent accidentally pushing broken code, or pushing code to the wrong branch, I've added a couple pre-commit checks which run before any commits can be executed.
See [this](https://stackoverflow.com/questions/40462111/prevent-commits-in-master-branch) StackOverflow post on protecting the main branch.
I also added a couple other pre-commit hooks to check for file size and unresolved merge conflicts.
Install these hooks like so:
```
$ pip install pre-commit
$ pre-commit install
```

## Writing a new module

Create the module `my_module` in a file called `my_module.sv` (located in an appropriate subdirectory of `src/rtl/`), and a unit test module `my_module_test` in a file called `my_module_test.sv` (located in the same subdirectory as `my_module.sv`).

### Unit test architecture

A unit test should test all of the functionality in a module. Even if a particular function of the module gets used rarely, that function must be tested in the unit test.

Unit tests should generally be written in a modular way, by combining SystemVerilog `task`s and `function`s into either a separate `_tb.sv` testbench module or `_pkg.sv` SystemVerilog package.
However, in some cases, if the unit test is simple enough, adding a separate module or package with utilities just introduces overhead and complexity and doesn't really improve code clarity.
For example, if you precompute a test vector of stimulus and expected response for your device under test (DUT), those snippets of code can be put into separate `task`s or `function`s (see these forum posts [1](https://verificationacademy.com/forums/t/task-vs-function/32019), [2](https://www.reddit.com/r/FPGA/comments/pvz4m8/when_to_use_a_function_vs_a_task/) for deciding between `task`s and `function`s).
That way, if your module is included in another module in the hierarchy and you want to test its behavior (either as an integration test, or a thorough unit test of the super-module), you can just call the modular blocks of code in the testbench module or package, reducing code duplication.

See [dds_tb.sv](src/rtl/transmit_chain/dds/dds_tb.sv) and [dds_test.sv](src/rtl/transmit_chain/dds/dds_test.sv) for an example of a use case where introducing a `_tb.sv` testbench module is helpful.
In the case of [axis_differentiator_test.sv](src/rtl/axis_processing/axis_differentiator), the test is simple enough that introducing a `_tb.sv` testbench module would make the test more confusing to understand and would do little to improve reusability.

Each unit test should create an instance of the [`sim_util_pkg::debug` class](src/verif/sim_util_pkg.sv) to track errors in the module and to provide tunable test verbosity.
This instance should be named `debug` and is used by the [run_unit_test.tcl](script/run_unit_test.tcl) script that is called during unit/regression tests to determine if a specific simulation test passes or fails.

```
sim_util_pkg::debug debug = new(sim_util_pkg::DEFAULT);
```

The `sim_util_pkg::debug` class offers 3 levels of verbosity for stdout: `DEFAULT` (lowest verbosity, good for regression tests or sanity checks to make sure that your simulation actually ran), `VERBOSE` (medium verbosity, useful to check if the individual parts of your simulation ran), and `DEBUG` (highest verbosity, good if something is going wrong).
The method `sim_util_pkg::debug.display(string msg, verbosity_t verbosity)` allows print statements to be generated at differing verbosity levels.
Whenever you call `sim_util_pkg::debug.display()`, you must pass a verbosity argument, which determines the verbosity level at which that particular `display()` statement will actually print to the console.
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
// my_module_test.sv - Your Name
// Brief description of the goal of the test
// - more detailed bullets of specifics
// - make sure to keep this comment updated when you change the file

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
This will run `verible-verilog-lint` and `slang` on all `*.v` and `*.sv` files in the project.
`verible-verilog-lint` primarly checks for coding style, since it only parses a single file at a time.
`slang` parses dependencies and can check that modules are used correctly.

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
