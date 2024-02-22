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
      $error(message);
      error_count = error_count + 1;
    endtask

    task fatal(input string message);
      $display("### ENCOUNTERED A FATAL ERROR, STOPPING SIMULATION NOW ###");
      $fatal(message);
    endtask

    task finish();
      if (error_count == 0) begin
        $display("### FINISHED WITH ZERO ERRORS ###");
        $finish;
      end else begin
        $fatal(1, "### FINISHED WITH %0d ERRORS ###", error_count);
      end
    endtask

  endclass

  class queue #(type T=int, type T2=int);

    math #(.T(T)) math_i = new;

    task automatic compare_threshold(
      debug debug_i,
      input T a_q [$],
      input T b_q [$],
      input T threshold
    );
      debug_i.display($sformatf("a_q.size() = %0d, b_q.size() = %0d", a_q.size(), b_q.size()), DEBUG);
      if (a_q.size() !== b_q.size()) begin
        debug_i.error($sformatf("a_q.size() = %0d != b_q.size() = %0d", a_q.size(), b_q.size()));
      end
      while ((a_q.size() > 0) & (b_q.size() > 0)) begin
        debug_i.display($sformatf("processing pair (%x, %x)", a_q[$], b_q[$]), DEBUG);
        if ($isunknown(a_q[$])) begin
          debug_i.error("a_q[$] is undefined");
        end
        if ($isunknown(b_q[$])) begin
          debug_i.error("b_q[$] is undefined");
        end
        if (math_i.abs(a_q[$] - b_q[$]) > threshold) begin
          debug_i.error($sformatf("mismatch, got %x expected %x", a_q[$], b_q[$]));
        end
        a_q.pop_back();
        b_q.pop_back();
      end
    endtask

    task automatic compare(
      debug debug_i,
      input T a_q [$],
      input T b_q [$]
    );
      compare_threshold(debug_i, a_q, b_q, '0);
    endtask

    task automatic samples_from_batches (
      input T2 in_q [$],
      output T out_q [$],
      input int sample_width,
      input int parallel_samples
    );
      T2 batch;
      T new_sample;
      while (in_q.size() > 0) begin
        batch = in_q.pop_back();
        for (int sample = 0; sample < parallel_samples; sample++) begin
          for (int b = 0; b < sample_width; b++) begin
            new_sample[b] = batch[sample*sample_width+b];
          end
          out_q.push_front(new_sample);
        end
      end
    endtask

  endclass

endpackage
