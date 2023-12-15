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
## Writing a new module

Create the module `module` in a file called `module.sv` (located in `src/rtl/`), and a unit test module `module_test` in a file called `module_test.sv` (located in `src/verif/`).
Also add the test module name `module_test` to the list `test_module_list` in [`script/run_simulation.tcl`](script/run_simulation.tcl).

### Unit test architecture

Each unit test should have a single input `start` and a parameter `MULTI_TEST` with default value 0.

Here's a template:
```
import sim_util_pkg::*;

`timescale 1ns / 1ps
module module_test #(
  parameter int MULTI_TEST = 0
) (
  input wire start,
  output logic done
);

sim_util_pkg::debug #(.VERBOSITY(DEFAULT)) dbg = new;

logic reset;
logic clk = 0;
localparam CLK_RATE_HZ = 100_000_000;
always #(0.5s/CLK_RATE_HZ) clk = ~clk;

initial begin
  if (MULTI_TEST) begin
    done <= 1'b0;
    wait (start === 1'b1);
  end

  // rest of test bench
  ...

  dbg.report_errors();
  if (MULTI_TEST) begin
    done <= 1'b1;
  end else begin
    $finish;
  end
end

endmodule
```

By giving the `MULTI_TEST` parameter a default value of `0`, when running the unit test as a toplevel, it will run immediately.
However, when the unit test is instantiated in the regression test wrapper which runs all of the unit tests, it will wait until the previous unit test completes before running.

The unit test must also be instantiated in `src/verif/regression_test.sv` like so:

```
...
module_test #(.(1)) module_test_i (.start(), .done());
...
```
This is crucial to ensure that future changes to the module (or any modules/packages/classes/libraries it depends on) that break its functionality are caught.

### Testing your module

Run vivado in batch mode, specifying the name of the test module as a TCL argument:

```
$ vivado -mode batch -source script/run_unit_test.tcl -tclargs module_test
```

Also note that unit_test can take a variable number of arguments, allowing for debugging of multiple modules simultaneously:

```
$ vivado -mode batch -source script/run_unit_test.tcl -tclargs module1_test [module2_test ...]
```

## Committing a new module

Make sure that the module works by running its unit test.
Also run a regression test to ensure that the new module (or any other code that was modified/created in the writing of the new module) does not break existing modules.

### Running a regression test

A full regression test (should be done before every commit) can be run by specifiying `regression_test` as the toplevel for the unit test script:

```
$ vivado -mode batch -source script/run_unit_test.tcl -tclargs regression_test
```
