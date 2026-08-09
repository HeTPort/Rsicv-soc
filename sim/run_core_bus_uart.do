onerror {quit -code 1}
if {[file exists work_core_bus_uart]} {
  vdel -lib work_core_bus_uart -all
}
vlib work_core_bus_uart
vmap work work_core_bus_uart
vlog -sv -work work_core_bus_uart \
  ../src/core/riscv_pkg.sv \
  ../src/periph/uart_tx.sv \
  ../src/periph/uart_rx.sv \
  ../src/periph/core_bus_uart.sv \
  ./tb/tb_core_bus_uart.sv
vsim -c -voptargs=+acc work_core_bus_uart.tb_core_bus_uart
run -all
quit -code [expr {[coverage attribute -name TESTSTATUS -concise] ne "OK"}]
