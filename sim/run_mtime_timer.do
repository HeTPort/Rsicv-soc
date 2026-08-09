onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv ../src/core/riscv_pkg.sv ../src/periph/mtime_timer.sv tb/tb_mtime_timer.sv
vsim -c -voptargs=+acc work.tb_mtime_timer
run -all
quit -code 0
