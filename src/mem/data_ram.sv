`timescale 1ns / 1ps
`default_nettype wire
// ============================================================
// Module: data_ram
// Description:
//   Pure Synthesizable BRAM for SoC level integration.
//   Address decoding and out-of-range protection should be 
//   handled by the System Bus (e.g., AXI Interconnect).
// ============================================================
module data_ram #(
  parameter int AW    = 32,
  parameter int DW    = 32,
  parameter int DEPTH = 4096,
  parameter string INIT_FILE = ""  // 新增：用于仿真时加载 firmware/linux镜像
)(
  input  wire logic            clk_i,
  input  wire logic            rst_ni,  // 保留接口兼容，但内部仅用于仿真复位
  input  wire logic            ren_i,
  input  wire logic            wen_i,
  input  wire logic [DW/8-1:0] wstrb_i,
  input  wire logic [AW-1:0]   addr_i,
  input  wire logic [DW-1:0]   wdata_i,
  output      logic [DW-1:0]   rdata_o
);
  localparam int BYTE_NUM = DW / 8;
  localparam int ADDR_LSB = (BYTE_NUM > 1) ? $clog2(BYTE_NUM) : 0;
  localparam int ADDR_W   = (DEPTH > 1) ? $clog2(DEPTH) : 1;

  // 物理存储器定义
  logic [DW-1:0] mem [0:DEPTH-1];

  // 提取字地址
  wire [ADDR_W-1:0] word_addr = addr_i[ADDR_LSB +: ADDR_W];

  // ---------------------------------------------------------
  // 仿真初始化与加载
  // ---------------------------------------------------------
  initial begin
    // 如果指定了初始化文件，则加载（常用于仿真加载C/汇编/内核程序）
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end 
    else begin
      // 仿真友好：默认全清零。综合时，Vivado会将其映射为BRAM的INIT属性
      for (int i = 0; i < DEPTH; i++) begin
        mem[i] = '0;
      end
    end
  end

  // ---------------------------------------------------------
  // 核心时序逻辑：纯净的 BRAM 模板
  // ---------------------------------------------------------
  always_ff @(posedge clk_i) begin
    // 1. 同步写操作 (支持字节写使能)
    if (wen_i) begin
      for (int i = 0; i < BYTE_NUM; i++) begin
        if (wstrb_i[i]) begin
          mem[word_addr][8*i +: 8] <= wdata_i[8*i +: 8];
        end
      end
    end

    // 2. 同步读操作
    // 注意：这里去掉了所有 if(rst_ni) 或 if(addr_in_range) 的判断
    // 这保证了 Vivado 会将其无缝推断为 Block RAM 的输出寄存器
    if (ren_i) begin
      rdata_o <= mem[word_addr];
    end 
    else begin
      // 当 ren_i 为低时，BRAM 输出默认保持上一次的值。
      // 如果你的外层 CPU 需要在 ren_i 为低时输出为 0，
      // 应该在 CPU 内部的 LSU (Load Store Unit) 里处理，而不是在 RAM 里。
      // 但为了不改变你原本“不读时就清零”的行为，这里保留：
      rdata_o <= '0; // 注意：这可能会消耗少量LUT，如果追求极致BRAM利用率可删掉此else。
    end
  end

  // ---------------------------------------------------------
  // 仅用于仿真的断言检查 (综合时会被忽略)
  // ---------------------------------------------------------
`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    // 检查：写使能开启，但字节掩码全0（这是一个潜在的软件BUG）
    if (wen_i && (wstrb_i == '0)) begin
      $warning("data_ram warning: wen_i is high but wstrb_i is 0 at addr=0x%h", addr_i);
    end
  end
`endif

endmodule
`default_nettype wire