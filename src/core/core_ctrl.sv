`timescale 1ns/1ps
`default_nettype none
import riscv_pkg::*;

module core_ctrl (
  input  wire logic       clk_i,
  input  wire logic       rst_ni,

  input  wire logic       id_valid_i,
  input  wire logic [4:0] id_rs1_addr_i,
  input  wire logic [4:0] id_rs2_addr_i,
  input  wire logic       id_use_rs1_i,
  input  wire logic       id_use_rs2_i,

  input  wire logic       ex_valid_i,
  input  wire logic [4:0] ex_rd_addr_i,
  input  wire logic       ex_rf_we_i,
  input  wire exc_pkt_t   ex_exc_i,
  input  wire redirect_t  ex_redirect_i,
  input  wire logic       ex_wait_i,

  input  wire redirect_t  retire_redirect_i,
  input  wire logic       wfi_enter_i,
  input  wire logic       wfi_wait_i,

  output redirect_t       redirect_o,
  output pipe_ctrl_t      pipe_ctrl_o
);

  logic hazard_stall;
  logic ex_stall;
  logic ex_exception;
  logic fetch_kill_q;
  // Named internal actions remain visible in waveforms while the public
  // contract is one cohesive pipe_ctrl_t.
  logic pc_stall;
  logic ifid_stall;
  logic idex_stall;
  logic ifid_flush;
  logic idex_flush;
  logic pipe_kill;
  logic ex_kill;
  logic instr_req;

  // Retirement is older than EX and therefore wins every simultaneous
  // redirect. Invalid payloads are canonical all-zero values.
  always_comb begin
    redirect_o = '0;
    if (retire_redirect_i.valid)
      redirect_o = retire_redirect_i;
    else if (ex_redirect_i.valid)
      redirect_o = ex_redirect_i;
  end

  assign hazard_stall =
      id_valid_i && ex_valid_i && ex_rf_we_i && (ex_rd_addr_i != 5'd0) &&
      ((id_use_rs1_i && id_rs1_addr_i == ex_rd_addr_i) ||
       (id_use_rs2_i && id_rs2_addr_i == ex_rd_addr_i));

  assign ex_stall = ex_wait_i;
  assign ex_exception = ex_valid_i &&
      (ex_exc_i.illegal_instr || ex_exc_i.instr_access_fault ||
       ex_exc_i.ecall || ex_exc_i.ebreak);

  // Only an older architectural event kills the whole younger pipeline. An
  // EX exception cancels local LSU/RV32M work but its fault packet still moves
  // to retirement.
  assign pipe_kill = retire_redirect_i.valid || wfi_enter_i;
  assign ex_kill   = pipe_kill || ex_exception;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      fetch_kill_q <= 1'b0;
    else
      fetch_kill_q <= redirect_o.valid || wfi_enter_i;
  end

  assign pc_stall   = hazard_stall | ex_stall | pipe_kill | wfi_wait_i;
  assign ifid_stall = hazard_stall | ex_stall | wfi_wait_i;
  assign idex_stall = ex_stall | wfi_wait_i;
  assign instr_req  = !pipe_kill && (!pc_stall || redirect_o.valid);
  assign ifid_flush = redirect_o.valid | fetch_kill_q | pipe_kill;
  // A RAW bubble is inserted only when EX can advance. While the LSU owns a
  // transaction, ID/EX must retain the memory instruction until completion.
  assign idex_flush = redirect_o.valid |
                      (hazard_stall && !ex_stall) |
                      pipe_kill;

  always_comb begin
    pipe_ctrl_o = '0;
    pipe_ctrl_o.pc_stall   = pc_stall;
    pipe_ctrl_o.instr_req  = instr_req;
    pipe_ctrl_o.ifid_stall = ifid_stall;
    pipe_ctrl_o.idex_stall = idex_stall;
    pipe_ctrl_o.ifid_flush = ifid_flush;
    pipe_ctrl_o.idex_flush = idex_flush;
    pipe_ctrl_o.pipe_kill  = pipe_kill;
    pipe_ctrl_o.ex_kill    = ex_kill;
  end

`ifndef SYNTHESIS
  always_comb begin
    if (retire_redirect_i.valid) begin
      assert (redirect_o == retire_redirect_i)
        else $error("Retirement redirect lost priority over EX");
    end
    if (pipe_kill) begin
      assert (ex_kill && !instr_req)
        else $error("Pipeline kill did not suppress younger fetch/EX work");
    end
  end
`endif

endmodule
`default_nettype wire
