当前 data RAM 是同步读写 RAM：

|信号	|方向	|含义|
|--|--|--|
|dmem_ren	|CPU -> RAM	|load 读使能|
|dmem_wen	|CPU -> RAM	|store 写使能
|dmem_wstrb	|CPU -> RAM	|字节写使能|
|dmem_addr	|CPU -> RAM	|数据访问地址|
|dmem_wdata	|CPU -> RAM	|store 写数据|
|dmem_rdata	|RAM -> CPU	|load 返回数据，延迟一拍|


因为 load 数据延迟一拍返回，所以：
```
EX 阶段发起 load
下一拍 WB 阶段获得 dmem_rdata 并写回寄存器
```