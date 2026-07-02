`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;
// ============================================================
// Module: lsu
// Description:
//   Load/Store Unit — isolates all data memory interaction.
//   Uses packed structs for clean interface.
// ============================================================
module lsu #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW
)(
  // -------- EX stage inputs --------
  input  id_ex_pkt_t  pkt_ex_i,
  input  logic        ex_kill_i,       // pipe_kill | illegal | ecall | ebreak

  // -------- WB stage inputs --------
  input  mem_pkt_t    wb_mem_info_i,   // Latched mem info from ex2wb
  input  logic [DW-1:0] ram_rdata_i,   // Raw data from RAM

  // -------- Data RAM interface (SRAM-like, ready for future bus wrapper) --------
  output logic            ram_req_valid_o, // Valid read or write request
  output logic            ram_req_ready_i, // (Future) RAM ready to accept req
  output logic            ram_we_o,        // 1: Store, 0: Load
  output logic [DW/8-1:0] ram_wstrb_o,
  output logic [AW-1:0]   ram_addr_o,
  output logic [DW-1:0]   ram_wdata_o,
  input  logic            ram_resp_valid_i,// (Future) RAM response valid (defaults to 1)

  // -------- Pipeline outputs --------
  output mem_pkt_t      mem_info_o,      // To be latched into ex2wb pipeline reg
  output logic          mem_misaligned_o,// To EX exception logic
  output logic [DW-1:0] load_data_o,     // To WB stage mux / Forwarding network
  output logic          load_fault_o,    // (Future) Load access fault
  output logic          store_fault_o    // (Future) Store access fault
);
  localparam int BYTE_NUM = DW / 8;

  // Extract signals from packet
  logic          ex_valid;
  logic [DW-1:0] ex_op1;
  logic [DW-1:0] ex_imm;
  logic [DW-1:0] ex_store_data;
  logic          ex_mem_req;
  logic          ex_mem_we;
  mem_size_e     ex_mem_size;
  logic          ex_mem_unsigned;

  assign ex_valid       = pkt_ex_i.valid;
  assign ex_op1         = pkt_ex_i.ex_data.op1;
  assign ex_imm         = pkt_ex_i.ex_data.imm;
  assign ex_store_data  = pkt_ex_i.ex_data.store_data;
  assign ex_mem_req     = pkt_ex_i.ex_ctrl.mem_req;
  assign ex_mem_we      = pkt_ex_i.ex_ctrl.mem_we;
  assign ex_mem_size    = pkt_ex_i.ex_ctrl.mem_size;
  assign ex_mem_unsigned= pkt_ex_i.ex_ctrl.mem_unsigned;

  // ------------------------------------------------------------
  // Effective address & misalignment check (EX stage)
  // ------------------------------------------------------------
  logic [AW-1:0] eff_addr;
  logic [1:0]    byte_offset;

  assign eff_addr    = ex_op1[AW-1:0] + ex_imm[AW-1:0];
  assign byte_offset = eff_addr[1:0];

  always_comb begin
    mem_misaligned_o = 1'b0;
    if (ex_mem_req) begin
      unique case (ex_mem_size)
        MEM_SIZE_BYTE: mem_misaligned_o = 1'b0;
        MEM_SIZE_HALF: mem_misaligned_o = byte_offset[0];
        MEM_SIZE_WORD: mem_misaligned_o = |byte_offset;
        default:       mem_misaligned_o = 1'b1;
      endcase
    end
  end

  // Pack output mem_info for pipeline register
  assign mem_info_o.mem_size     = ex_mem_size;
  assign mem_info_o.mem_unsigned = ex_mem_unsigned;
  assign mem_info_o.load_offset  = byte_offset;

  // ------------------------------------------------------------
  // RAM control signals (EX stage)
  // ------------------------------------------------------------
  logic mem_op_active;
  assign mem_op_active = ex_valid && ex_mem_req && !ex_kill_i && !mem_misaligned_o;

  // Basic SRAM has no delay, so valid=active, ready=1, resp_valid=1
  assign ram_req_valid_o = mem_op_active;
  assign ram_req_ready_i = 1'b1; 
  assign ram_resp_valid_i= 1'b1;
  assign ram_we_o        = mem_op_active && ex_mem_we;
  assign ram_addr_o      = eff_addr;

  // Store byte strobe & shifted write data
  always_comb begin
    ram_wstrb_o = '0;
    ram_wdata_o = '0;
    if (ram_we_o) begin
      unique case (ex_mem_size)
        MEM_SIZE_BYTE: begin
          ram_wstrb_o[byte_offset] = 1'b1;
          ram_wdata_o[8*byte_offset +: 8] = ex_store_data[7:0];
        end
        MEM_SIZE_HALF: begin
          if (byte_offset[1] == 1'b0) begin
            ram_wstrb_o[1:0]   = 2'b11;
            ram_wdata_o[15:0]  = ex_store_data[15:0];
          end else begin
            ram_wstrb_o[3:2]   = 2'b11;
            ram_wdata_o[31:16] = ex_store_data[15:0];
          end
        end
        MEM_SIZE_WORD: begin
          ram_wstrb_o = {BYTE_NUM{1'b1}};
          ram_wdata_o = ex_store_data;
        end
        default: begin
          ram_wstrb_o = '0;
          ram_wdata_o = '0;
        end
      endcase
    end
  end

  // ------------------------------------------------------------
  // Load data alignment & sign/zero extension (WB stage)
  // ------------------------------------------------------------
  logic [7:0]  load_byte;
  logic [15:0] load_half;

  always_comb begin
    load_byte = 8'h00;
    unique case (wb_mem_info_i.load_offset)
      2'd0: load_byte = ram_rdata_i[7:0];
      2'd1: load_byte = ram_rdata_i[15:8];
      2'd2: load_byte = ram_rdata_i[23:16];
      2'd3: load_byte = ram_rdata_i[31:24];
      default: load_byte = 8'h00;
    endcase
  end

  always_comb begin
    load_half = 16'h0000;
    unique case (wb_mem_info_i.load_offset[1])
      1'b0: load_half = ram_rdata_i[15:0];
      1'b1: load_half = ram_rdata_i[31:16];
      default: load_half = 16'h0000;
    endcase
  end

  always_comb begin
    load_data_o = '0;
    unique case (wb_mem_info_i.mem_size)
      MEM_SIZE_BYTE: begin
        load_data_o = wb_mem_info_i.mem_unsigned ? 
                      {{(DW-8){1'b0}}, load_byte} : {{(DW-8){load_byte[7]}}, load_byte};
      end
      MEM_SIZE_HALF: begin
        load_data_o = wb_mem_info_i.mem_unsigned ? 
                      {{(DW-16){1'b0}}, load_half} : {{(DW-16){load_half[15]}}, load_half};
      end
      MEM_SIZE_WORD: begin
        load_data_o = ram_rdata_i;
      end
      default: begin
        load_data_o = '0;
      end
    endcase
  end

  // Future bus fault placeholders
  assign load_fault_o  = 1'b0;
  assign store_fault_o = 1'b0;

endmodule
`default_nettype wire