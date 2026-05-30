valid  ：这一级有没有真指令
stall  ：这一级保持不动
flush  ：这一级清空成 bubble
halt   ：CPU 已经停止
trap   ：本周期发现异常/EBREAK/非法
kill   ：不要让后面的年轻指令继续提交
redirect：分支/跳转改 PC
fetch_kill：杀掉同步 RAM 下一拍返回的错误取指
hazard ：数据相关，需要暂停前端并插 bubble