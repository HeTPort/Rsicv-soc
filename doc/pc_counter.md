flush / stall 关系
|信号	|含义|
|--|--|
|redirect_en	|EX 阶段发现 branch taken / JAL / JALR|
|redirect_pc	|重定向目标 PC|
|flush_req	|冲刷年轻指令|
|fetch_kill_q	|同步取指带来的“下一拍错误返回指令”杀掉标志|
|hazard_stall	|ID 指令依赖 EX 结果，需要停顿一拍|


由于同步指令 RAM 存在一拍延迟，branch/jump 后需要杀掉：

1. 当前 IF/ID 中的错误指令；
2. 下一拍 RAM 返回的错误指令。

因此顶层用了：
```
ifid_flush = ex_flush_req | fetch_kill_q;
```