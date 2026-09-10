# In ModelSim: open the recorded WLF, then do this script.
quietly WaveActivateNextPane {} 0
add wave -divider {Protocol: active-high control except rst_n}
add wave /tb_divider_lab/clk /tb_divider_lab/rst_n
add wave /tb_divider_lab/start /tb_divider_lab/kill
add wave /tb_divider_lab/busy /tb_divider_lab/complete
add wave -divider {State and datapath}
add wave /tb_divider_lab/dut/state_q
add wave -radix unsigned /tb_divider_lab/dut/iteration_q
add wave -radix hexadecimal /tb_divider_lab/dut/quotient_work_q
add wave -radix unsigned /tb_divider_lab/dut/remainder_work_q
add wave -radix unsigned /tb_divider_lab/dut/divisor_q
add wave -divider {Results: change radix to signed for case 2}
add wave -radix hexadecimal /tb_divider_lab/quotient /tb_divider_lab/remainder
configure wave -namecolwidth 260
configure wave -valuecolwidth 130
wave zoom range 100ns 1500ns
