transcript on
onerror {quit -code 1}
if {[file exists work_uart_rx]} {
  vdel -lib work_uart_rx -all
}
vlib work_uart_rx
vmap work work_uart_rx
vlog -sv -work work_uart_rx \
  ../src/periph/uart_rx.sv \
  ./tb/tb_uart_rx.sv
vsim -c -voptargs=+acc work_uart_rx.tb_uart_rx
run -all
quit -code 0
