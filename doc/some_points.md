当程序执行到最后一条指令 ebreak 时，它流到 WB 阶段会触发 trap_event。在 trap_event 拉高的那一瞬间，halt_q 还是 0（它要到下一个时钟沿才会变 1）。如果此时由于结构体打包/解包的微小布线延迟差异，导致 ex2wb_pkt_out.exc.illegal_instr 出现了极短的瞬态高电平毛刺，illegal_instr_o 就会输出一个极短的脉冲。
由于 Testbench 中的 seen_illegal 是异步敏感于时钟上升沿的触发器，它很容易把这个毛刺锁存下来

重构前，由于散线的逻辑门延迟与结构体不同，这个毛刺恰好没有在时钟上升沿处出现，所以之前没有报错

最稳健的修改方式是：不要用一个永久的锁存器去抓可能带毛刺的异步脉冲，而是在 CPU 确认停机后，直接采样当时的 illegal_instr 信号。 因为当 halt 稳定时，illegal_instr 信号也一定稳定
即刪除 seen_illegal 锁存器逻辑
```
  logic  seen_illegal;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      seen_illegal <= 1'b0;
    end else if (illegal_instr) begin
      seen_illegal <= 1'b1;
    end
  end
```