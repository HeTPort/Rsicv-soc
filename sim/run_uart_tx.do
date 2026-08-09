onerror {quit -code 1}
if {[file exists work_uart_tx]} {
  vdel -lib work_uart_tx -all
}
vlib work_uart_tx
vmap work work_uart_tx
vlog -sv -work work_uart_tx \
  ../src/periph/uart_tx.sv \
  ./tb/tb_uart_tx.sv
vsim -c -voptargs=+acc work_uart_tx.tb_uart_tx
run -all
quit -code [expr {[coverage attribute -name TESTSTATUS -concise] ne "OK"}]
