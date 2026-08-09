transcript on
onerror {quit -code 1}
if {[file exists work_core_bus_uart_rx]} {
  vdel -lib work_core_bus_uart_rx -all
}
vlib work_core_bus_uart_rx
vmap work work_core_bus_uart_rx
vlog -sv -work work_core_bus_uart_rx \
  ../src/core/riscv_pkg.sv \
  ../src/periph/uart_tx.sv \
  ../src/periph/uart_rx.sv \
  ../src/periph/core_bus_uart.sv \
  ./tb/tb_core_bus_uart_rx.sv
vsim -c -voptargs=+acc work_core_bus_uart_rx.tb_core_bus_uart_rx
run -all
quit -code 0
