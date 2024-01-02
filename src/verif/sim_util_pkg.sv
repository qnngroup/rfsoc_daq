// sim_util_pkg.sv - Reed Foster
// package with various simulation utilities:
// a class with max and absolute value for generic types,
// and a debugging class for tracking errors and printing messages with varying
// degrees of verbosity

package sim_util_pkg;

  class math #(type T=int);

    function T max(input T A, input T B);
      return (A > B) ? A : B;
    endfunction

    function T abs(input T x);
      return (x < 0) ? -x : x;
    endfunction

  endclass

  typedef enum {DEFAULT=0, VERBOSE=1, DEBUG=2} verbosity_t;

  class debug;

    verbosity_t verbosity;
    int error_count;

    function new (verbosity_t v);
      verbosity = v;
      error_count = 0;
    endfunction

    task display(input string message, input verbosity_t message_verbosity);
      if (verbosity >= message_verbosity) begin
        unique case (message_verbosity)
          DEFAULT:  $display("%s", message);
          VERBOSE:  $display("  %s", message);
          DEBUG:    $display("    %s", message);
        endcase
      end
    endtask

    task error(input string message);
      $warning(message);
      error_count = error_count + 1;
    endtask

    task finish();
      if (error_count == 0) begin
        $display("### finished with zero errors ###");
        $finish;
      end else begin
        $fatal(1, "### finished with %0d errors ###", error_count);
      end
    endtask

  endclass

endpackage
