// sim_util_pkg.sv - Reed Foster
// package with various simulation utilities:
// a class with max and absolute value for generic types,
// and a debugging class for tracking errors and printing messages with varying
// degrees of verbosity

`timescale 1ns/1ps

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
  typedef enum {GREEN=32, RED=31, BLUE=34, DEFAULT_COLOR=33} color_t; 

  class debug;

    verbosity_t verbosity;
    protected int error_count;
    protected bit test_complete; 
    protected string test_name;  
    int test_num, total_tests;
    int timeout_counter;
    bit timeout_reset, is_integrated, done, timed_out;

    function new (verbosity_t v, int total_tests_in = 0, string test_name_in = "XXX", bit is_integrated_in = 0);
      verbosity = v;
      {error_count,test_num,test_complete} = 0;
      {timeout_counter, timeout_reset, done} = 0;       
      total_tests = total_tests_in;
      test_name = test_name_in;
      is_integrated = is_integrated_in; 
    endfunction

    function string get_test_name();
      return test_name;
    endfunction 

    task automatic reset_timeout(ref logic clk);
      timeout_reset <= 1;
      @(posedge clk); 
      timeout_reset <= 0;
      @(posedge clk); 
    endtask 
    task automatic timeout_watcher(ref logic clk, input int TIMEOUT);
      fork   
        begin : timeout_thread 
          int curr_test;
          curr_test = test_num;
          while (timeout_counter < TIMEOUT) begin
            if (test_complete) break; 
              if ((curr_test != test_num) || timeout_reset) begin
                  timeout_counter = 0; 
                  curr_test = test_num; 
              end 
              else timeout_counter++;
              @(posedge clk);
          end
          if (~test_complete) fatalc($sformatf("### TIMEOUT ON TEST %0d ###", test_num));
        end 

        begin 
          while (1) begin
            timed_out = done && ~test_complete; 
            @(posedge clk);
          end
        end 
      join_none
    endtask 

    task automatic check_test(input bit cond, input bit has_parts = 0, input string fail_msg = "");
      string passed_string = (cond)? "PASSED" : $sformatf("FAILED: %s",fail_msg); 
      color_t string_color = (cond)? GREEN : RED;  
      if (test_num >= total_tests) fatalc($sformatf("### TEST NUMBER %0d EXCEEDS EXPECTED LIMIT %0d ###",test_num, total_tests));
      if (~cond && ~has_parts) error_count++;
      displayc($sformatf("\n### TEST %0d %s ###", test_num, passed_string), string_color, VERBOSE);
      test_num++;
      if (test_num == total_tests) begin 
        test_complete = 1;  
        finishc();
      end 
    endtask

    function void set_test_complete();
      test_complete = 1;
    endfunction

    function void clear_error_count();
      error_count = 0;
    endfunction

    function void set_error_count(input int err);
      error_count = err;
    endfunction

    function int get_error_count();
      return error_count;
    endfunction

    function bit disp_test_part(input int test_part, input bit cond, input string msg);
      color_t string_color = (cond)? GREEN : RED; 
      displayc($sformatf("%0d_%0d", test_num, test_part), string_color, DEBUG,.do_write(1));
      if (~cond) displayc($sformatf("(-)\n(%s) ", msg), string_color, DEBUG,.do_write(1));
      else displayc($sformatf("(+) "), string_color, DEBUG,1);
      if (~cond) error_count++;
      return cond;
    endfunction

    function void displayc(input string msg, input color_t msg_color = DEFAULT_COLOR, input verbosity_t msg_verbosity=DEFAULT, input bit do_write = 0);
        $write("%c[1;%0dm",27,msg_color); 
        display(msg, msg_verbosity,do_write);
        $write("%c[0m",27); 
    endfunction 

    task fatalc(input string msg);
      displayc($sformatf("\n### ENCOUNTERED A FATAL ERROR, STOPPING %s TEST NOW ###\n%s",test_name, msg), RED, DEFAULT);
      if (~is_integrated) $fatal(1,"");
      done = 1;
    endtask

    task finishc();
      if (error_count == 0) begin
        displayc($sformatf("\n### FINISHED %0d TESTS OF %s MODULE WITH ZERO ERRORS ###\n\n",test_num,test_name), GREEN, DEFAULT);
        if (~is_integrated) $finish;
        done = 1;
      end else begin
        displayc($sformatf("\n### FINISHED %0d TESTS OF %s MODULE WITH %0d ERRORS ###\n\n",test_num,test_name, error_count), RED, DEFAULT);
        if (~is_integrated) $fatal(1,"");
        done = 1;
      end
    endtask

    function void display(input string message, input verbosity_t message_verbosity, input bit do_write = 0);
      if (verbosity >= message_verbosity) begin
        unique case (message_verbosity)
          DEFAULT:begin 
            if (do_write) $write("%s", message);
            else $display("%s", message);
          end 
          VERBOSE:begin 
            if (do_write) $write("%s", message);
            else $display("%s", message);
          end 
          DEBUG:  begin 
            if (do_write) $write("%s", message);
            else $display("%s", message);
          end 
        endcase
      end
    endfunction

    task error(input string message);
      $error(message);
      error_count = error_count + 1;
    endtask


    task fatal(input string message);
      $display("### ENCOUNTERED A FATAL ERROR, STOPPING SIMULATION NOW ###");
      $fatal(1, message);
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
