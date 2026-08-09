onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv ../src/core/riscv_pkg.sv ../src/core/retire_stage.sv tb/tb_retire_stage.sv
vsim -c -voptargs=+acc work.tb_retire_stage
run -all
quit -code 0
