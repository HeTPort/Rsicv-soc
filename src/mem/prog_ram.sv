`timescale 1ns / 1ps
`default_nettype none
module prog_ram #(
  parameter int    AW            = 32,          // 地址宽度，单位：bit
  parameter int    DW            = 32,          // 数据宽度，单位：bit
  parameter int    DEPTH         = 4096,        // RAM 深度，单位：word
  parameter string FILE          = "D:/Rsicv-soc/testdata/prog.hex",  // 初始化文件
  parameter logic [DW-1:0] INVALID_RDATA = '0   // 非法读时返回的数据
)(
  input  wire logic          clk_i,
  // 读端口，一般用于取指
  input  wire logic          ren_i,
  input  wire logic [AW-1:0] instr_addr_i,
  output      logic [DW-1:0] instr_data_o,
  // 写端口
  input  wire logic          wen_i,
  input  wire logic [AW-1:0] waddr_i,
  input  wire logic [DW-1:0] wdata_i
  // 错误输出
  //output    logic          rerr_o,   // 读错误，读越界或读地址未对齐
  //output    logic          werr_o    // 写错误，写越界或写地址未对齐
);
  // ------------------------------------------------------------
  // 参数计算
  // ------------------------------------------------------------
  // 每个 word 包含多少 byte
  localparam int BYTE_NUM = DW / 8;
  // word 地址中的低位 byte offset 位数
  // 例如 DW = 32，则 BYTE_NUM = 4，ADDR_LSB = 2
  // 地址 [1:0] 是 byte offset，地址 [AW-1:2] 是 word 地址
  localparam int ADDR_LSB = (BYTE_NUM > 1) ? $clog2(BYTE_NUM) : 0;
  // RAM index 所需位宽
  // 例如 DEPTH = 4096，则 ADDR_W = 12
  localparam int DEPTH_SAFE = (DEPTH > 0) ? DEPTH : 1;
  localparam int ADDR_W     = (DEPTH_SAFE > 1) ? $clog2(DEPTH_SAFE) : 1;
  // 完整 word 地址宽度
  // 从 byte 地址去掉低 ADDR_LSB 位之后得到 word 地址
  localparam int WORD_AW = (AW > ADDR_LSB) ? (AW - ADDR_LSB) : 1;
  // 用于把完整 word 地址转换成 RAM index
  localparam int COPY_W = (ADDR_W < WORD_AW) ? ADDR_W : WORD_AW;
  // 地址低位检查宽度，用于判断是否对齐
  localparam int LOW_W = (ADDR_LSB < AW) ? ADDR_LSB : AW;
  // ------------------------------------------------------------
  // RAM 存储体
  // ------------------------------------------------------------
  logic [DW-1:0] mem [0:DEPTH_SAFE-1];
  // ------------------------------------------------------------
  // 地址相关信号
  // ------------------------------------------------------------
  // 完整 word 地址
  // 例如 byte 地址为 0x0000_4000，DW = 32 时，
  // word 地址为 0x0000_1000
  logic [WORD_AW-1:0] fetch_word_addr_full;
  logic [WORD_AW-1:0] write_word_addr_full;
  // 实际用于访问 mem 的 index
  logic [ADDR_W-1:0] fetch_word_addr;
  logic [ADDR_W-1:0] write_word_addr;
  // 地址是否未对齐
  logic fetch_misaligned;
  logic write_misaligned;
  // 地址是否在 RAM 范围内
  logic fetch_in_range;
  logic write_in_range;
  // 读写访问是否合法
  logic fetch_valid;
  logic write_valid;
  // ------------------------------------------------------------
  // 参数合法性检查
  // ------------------------------------------------------------
  initial begin
    if (DW <= 0) begin
      $fatal(1, "prog_ram parameter error: DW must be greater than 0");
    end
    if ((DW % 8) != 0) begin
      $fatal(1, "prog_ram parameter error: DW must be a multiple of 8");
    end
    if (BYTE_NUM <= 0) begin
      $fatal(1, "prog_ram parameter error: BYTE_NUM must be greater than 0");
    end
    if ((BYTE_NUM & (BYTE_NUM - 1)) != 0) begin
      $fatal(1, "prog_ram parameter error: BYTE_NUM must be power of 2");
    end
    if (DEPTH <= 0) begin
      $fatal(1, "prog_ram parameter error: DEPTH must be greater than 0");
    end
    if (AW <= 0) begin
      $fatal(1, "prog_ram parameter error: AW must be greater than 0");
    end
  end
  // ------------------------------------------------------------
  // 初始化 RAM
  // ------------------------------------------------------------
  initial begin
    if (FILE != "") begin
      $readmemh(FILE, mem);
    end
  end
  // ------------------------------------------------------------
  // 取完整 word 地址
  // ------------------------------------------------------------
  generate
    if (AW > ADDR_LSB) begin : gen_word_addr_extract
      assign fetch_word_addr_full = instr_addr_i[AW-1:ADDR_LSB];
      assign write_word_addr_full = waddr_i[AW-1:ADDR_LSB];
    end else begin : gen_word_addr_zero
      assign fetch_word_addr_full = '0;
      assign write_word_addr_full = '0;
    end
  endgenerate
  // ------------------------------------------------------------
  // 取 RAM index
  // ------------------------------------------------------------
  //
  // 注意：
  // fetch_word_addr_full 是完整 word 地址。
  // fetch_word_addr 是 mem 的 index。
  //
  // 如果 DEPTH = 4096，则 fetch_word_addr 只有 12 位。
  // 但是越界判断不能只看这 12 位，否则高位会被忽略。
  //
  // 所以：
  // 1. 先用 fetch_word_addr_full 判断是否越界；
  // 2. 如果合法，再用 fetch_word_addr 访问 mem。
  //
  always_comb begin
    fetch_word_addr = '0;
    write_word_addr = '0;
    fetch_word_addr[COPY_W-1:0] = fetch_word_addr_full[COPY_W-1:0];
    write_word_addr[COPY_W-1:0] = write_word_addr_full[COPY_W-1:0];
  end
  // ------------------------------------------------------------
  // 对齐检查
  // ------------------------------------------------------------
  //
  // 例如 DW = 32：
  //
  // BYTE_NUM = 4
  // ADDR_LSB = 2
  //
  // 合法地址必须满足：
  //
  // addr[1:0] == 2'b00
  //
  // 也就是 4 字节对齐。
  //
  generate
    if (LOW_W > 0) begin : gen_align_check
      assign fetch_misaligned = |instr_addr_i[LOW_W-1:0];
      assign write_misaligned = |waddr_i[LOW_W-1:0];
    end else begin : gen_no_align_check
      assign fetch_misaligned = 1'b0;
      assign write_misaligned = 1'b0;
    end
  endgenerate
  // ------------------------------------------------------------
  // 越界检查函数
  // ------------------------------------------------------------
  //
  // DEPTH 表示 RAM 有多少个 word。
  //
  // 合法 word 地址范围是：
  //
  // 0 <= word_addr < DEPTH
  //
  // 例如 DEPTH = 4096，则合法范围是：
  //
  // 0 ~ 4095
  //
  function automatic logic addr_in_range(
    input logic [WORD_AW-1:0] word_addr
  );
    addr_in_range =
       $unsigned(word_addr) < $unsigned(DEPTH_SAFE);
  endfunction
  assign fetch_in_range = addr_in_range(fetch_word_addr_full);
  assign write_in_range = addr_in_range(write_word_addr_full);
  // ------------------------------------------------------------
  // 访问合法性判断
  // ------------------------------------------------------------
  assign fetch_valid = fetch_in_range && !fetch_misaligned;
  assign write_valid = write_in_range && !write_misaligned;
  // ------------------------------------------------------------
  // RAM 读写逻辑
  // ------------------------------------------------------------
  //
  // 行为说明：
  //
  // 1. 合法写：
  //    mem[write_word_addr] <= wdata_i;
  //
  // 2. 非法写：
  //    不写 RAM，同时 werr_o 置 1 一个周期。
  //
  // 3. 合法读：
  //    instr_data_o <= mem[fetch_word_addr];
  //
  // 4. 非法读：
  //    instr_data_o <= INVALID_RDATA，同时 rerr_o 置 1 一个周期。
  //
  // 5. 同周期读写同一个地址：
  //    返回 wdata_i，避免读到旧值。
  //
  always_ff @(posedge clk_i) begin
    // 默认每个周期清零错误标志
   // rerr_o <= 1'b0;
    //werr_o <= 1'b0;
    // ----------------------------
    // 写逻辑
    // ----------------------------
    if (wen_i) begin
      if (write_valid) begin
        mem[write_word_addr] <= wdata_i;
      end else begin
        $error("write_word_addr failed");
      end
    end
    // ----------------------------
    // 读逻辑
    // ----------------------------
    if (ren_i) begin
      if (fetch_valid) begin
        // 同周期读写同一个合法 word 地址，直接旁路写数据
        if (wen_i &&
            write_valid &&
            write_word_addr_full == fetch_word_addr_full) begin
          instr_data_o <= wdata_i;
        end else begin
          instr_data_o <= mem[fetch_word_addr];
        end
      end else begin
        //rerr_o       <= 1'b1;
        instr_data_o <= INVALID_RDATA;
      end
    end
  end
  // ------------------------------------------------------------
  // 仿真错误提示
  // ------------------------------------------------------------
  //
  // 注意：
  // 下面这些 $error 主要用于仿真排查问题。
  // 综合时一般会被综合工具忽略。
  //
`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (ren_i && fetch_misaligned) begin
      $error("prog_ram read misaligned address: addr = 0x%h",
             instr_addr_i);
    end
    if (ren_i && !fetch_in_range) begin
      $error("prog_ram read address out of range: addr = 0x%h, word_addr = 0x%h, DEPTH = %0d",
             instr_addr_i,
             fetch_word_addr_full,
             DEPTH_SAFE);
    end
    if (wen_i && write_misaligned) begin
      $error("prog_ram write misaligned address: addr = 0x%h",
             waddr_i);
    end
    if (wen_i && !write_in_range) begin
      $error("prog_ram write address out of range: addr = 0x%h, word_addr = 0x%h, DEPTH = %0d",
             waddr_i,
             write_word_addr_full,
             DEPTH_SAFE);
    end
  end
`endif
endmodule
`default_nettype wire