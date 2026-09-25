`timescale 1ns/1ps

module u0_uvm_smoke_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class u0_uvm_smoke_test extends uvm_test;
    `uvm_component_utils(u0_uvm_smoke_test)

    function new(string name = "u0_uvm_smoke_test",
                 uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      `uvm_info("U0_VERSION",
                $sformatf("U0_UVM_VERSION=%s", uvm_revision_string()),
                UVM_NONE)
      `uvm_info("U0_SMOKE", "U0_UVM_SMOKE_PASS", UVM_NONE)
      phase.drop_objection(this);
    endtask
  endclass

  initial begin
    run_test("u0_uvm_smoke_test");
  end
endmodule
