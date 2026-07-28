`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

// Single-outstanding load/store transaction owner.
module lsu #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW
)(
  input  logic          clk_i,
  input  logic          rst_ni,

  // Held EX-stage instruction.
  input  id_ex_pkt_t    pkt_ex_i,
  input  logic          ex_kill_i,

  // CPU-local data bus.
  output logic          bus_req_valid_o,
  input  logic          bus_req_ready_i,
  output core_bus_req_t bus_req_o,
  input  logic          bus_rsp_valid_i,
  input  core_bus_rsp_t bus_rsp_i,

  // Completed transaction information.
  output mem_pkt_t      mem_info_o,
  output logic          mem_misaligned_o,
  output logic [DW-1:0] raw_rdata_o,
  output logic [DW-1:0] load_data_o,
  output logic          load_fault_o,
  output logic          store_fault_o,
  output logic          busy_o,
  output logic          complete_o
);
  localparam int BYTE_NUM = DW / 8;

  typedef enum logic [1:0] {
    LSU_IDLE,
    LSU_REQUEST,
    LSU_RESPONSE,
    LSU_COMPLETE
  } lsu_state_e;

  lsu_state_e state_q;
  core_bus_req_t req_q;
  mem_pkt_t mem_info_q;
  logic [DW-1:0] rsp_rdata_q;
  logic rsp_error_q;

  logic          ex_valid;
  logic [DW-1:0] ex_op1;
  logic [DW-1:0] ex_imm;
  logic [DW-1:0] ex_store_data;
  logic          ex_mem_req;
  logic          ex_mem_we;
  mem_size_e     ex_mem_size;
  logic          ex_mem_unsigned;
  logic [AW-1:0] eff_addr;
  logic [1:0]    byte_offset;
  logic          mem_start;

  assign ex_valid        = pkt_ex_i.valid;
  assign ex_op1          = pkt_ex_i.ex_data.op1;
  assign ex_imm          = pkt_ex_i.ex_data.imm;
  assign ex_store_data   = pkt_ex_i.ex_data.store_data;
  assign ex_mem_req      = pkt_ex_i.ex_ctrl.mem_req;
  assign ex_mem_we       = pkt_ex_i.ex_ctrl.mem_we;
  assign ex_mem_size     = pkt_ex_i.ex_ctrl.mem_size;
  assign ex_mem_unsigned = pkt_ex_i.ex_ctrl.mem_unsigned;
  assign eff_addr        = ex_op1[AW-1:0] + ex_imm[AW-1:0];
  assign byte_offset     = eff_addr[1:0];

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

  assign mem_start = state_q == LSU_IDLE &&
                     ex_valid &&
                     ex_mem_req &&
                     !ex_kill_i &&
                     !mem_misaligned_o;

  // ID/EX must hold from the first visible memory operation through RESPONSE.
  // COMPLETE releases it while presenting one result to EX/WB.
  assign busy_o     = mem_start ||
                      state_q == LSU_REQUEST ||
                      state_q == LSU_RESPONSE;
  assign complete_o = state_q == LSU_COMPLETE;

  assign bus_req_valid_o = state_q == LSU_REQUEST && !ex_kill_i;
  assign bus_req_o       = req_q;
  assign mem_info_o      = mem_info_q;
  assign raw_rdata_o     = rsp_rdata_q;
  assign load_fault_o    = complete_o && rsp_error_q && !req_q.write;
  assign store_fault_o   = complete_o && rsp_error_q && req_q.write;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q      <= LSU_IDLE;
      req_q        <= '0;
      mem_info_q   <= '0;
      rsp_rdata_q  <= '0;
      rsp_error_q  <= 1'b0;
    end else begin
      unique case (state_q)
        LSU_IDLE: begin
          if (mem_start) begin
            req_q.addr   <= eff_addr;
            req_q.write  <= ex_mem_we;
            req_q.size   <= ex_mem_size;
            req_q.wdata  <= '0;
            req_q.wstrb  <= '0;

            mem_info_q.mem_size     <= ex_mem_size;
            mem_info_q.mem_unsigned <= ex_mem_unsigned;
            mem_info_q.load_offset  <= byte_offset;
            rsp_error_q              <= 1'b0;

            if (ex_mem_we) begin
              unique case (ex_mem_size)
                MEM_SIZE_BYTE: begin
                  req_q.wstrb[byte_offset] <= 1'b1;
                  req_q.wdata[8*byte_offset +: 8] <= ex_store_data[7:0];
                end
                MEM_SIZE_HALF: begin
                  if (!byte_offset[1]) begin
                    req_q.wstrb[1:0]  <= 2'b11;
                    req_q.wdata[15:0] <= ex_store_data[15:0];
                  end else begin
                    req_q.wstrb[3:2]   <= 2'b11;
                    req_q.wdata[31:16] <= ex_store_data[15:0];
                  end
                end
                MEM_SIZE_WORD: begin
                  req_q.wstrb <= {BYTE_NUM{1'b1}};
                  req_q.wdata <= ex_store_data;
                end
                default: begin
                  req_q.wstrb <= '0;
                  req_q.wdata <= '0;
                end
              endcase
            end
            state_q <= LSU_REQUEST;
          end
        end

        LSU_REQUEST: begin
          if (ex_kill_i) begin
            state_q <= LSU_IDLE;
          end else if (bus_req_valid_o && bus_req_ready_i) begin
            state_q <= LSU_RESPONSE;
          end
        end

        LSU_RESPONSE: begin
          if (bus_rsp_valid_i) begin
            rsp_rdata_q <= bus_rsp_i.rdata;
            rsp_error_q <= bus_rsp_i.error;
            state_q     <= LSU_COMPLETE;
          end
        end

        LSU_COMPLETE: begin
          state_q <= LSU_IDLE;
        end

        default: begin
          state_q <= LSU_IDLE;
        end
      endcase
    end
  end

  logic [7:0]  load_byte;
  logic [15:0] load_half;

  always_comb begin
    unique case (mem_info_q.load_offset)
      2'd0:    load_byte = rsp_rdata_q[7:0];
      2'd1:    load_byte = rsp_rdata_q[15:8];
      2'd2:    load_byte = rsp_rdata_q[23:16];
      2'd3:    load_byte = rsp_rdata_q[31:24];
      default: load_byte = '0;
    endcase

    unique case (mem_info_q.load_offset[1])
      1'b0:    load_half = rsp_rdata_q[15:0];
      1'b1:    load_half = rsp_rdata_q[31:16];
      default: load_half = '0;
    endcase

    unique case (mem_info_q.mem_size)
      MEM_SIZE_BYTE:
        load_data_o = mem_info_q.mem_unsigned ?
                      {{(DW-8){1'b0}}, load_byte} :
                      {{(DW-8){load_byte[7]}}, load_byte};
      MEM_SIZE_HALF:
        load_data_o = mem_info_q.mem_unsigned ?
                      {{(DW-16){1'b0}}, load_half} :
                      {{(DW-16){load_half[15]}}, load_half};
      MEM_SIZE_WORD:
        load_data_o = rsp_rdata_q;
      default:
        load_data_o = '0;
    endcase
  end

`ifndef SYNTHESIS
  core_bus_req_t stalled_req_q;
  logic stalled_q;
  logic complete_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      stalled_req_q <= '0;
      stalled_q     <= 1'b0;
      complete_q    <= 1'b0;
    end else begin
      if (stalled_q && !ex_kill_i) begin
        assert (bus_req_valid_o)
          else $error("LSU request valid dropped before acceptance");
        assert (bus_req_o === stalled_req_q)
          else $error("LSU request payload changed under back-pressure");
      end

      assert (!(bus_rsp_valid_i && state_q != LSU_RESPONSE))
        else $error("LSU received a response without an outstanding request");
      assert (!(complete_o && complete_q))
        else $error("LSU completion lasted more than one cycle");
      assert (!(ex_kill_i && bus_req_valid_o))
        else $error("LSU issued a request while killed");

      stalled_q <= bus_req_valid_o && !bus_req_ready_i;
      if (bus_req_valid_o && !bus_req_ready_i)
        stalled_req_q <= bus_req_o;
      complete_q <= complete_o;
    end
  end
`endif

endmodule
`default_nettype wire
