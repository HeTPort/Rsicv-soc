onerror {quit -code 1}
onbreak {quit -code 1}
if {[file exists work_core_ctrl]} {vdel -lib work_core_ctrl -all}
vlib work_core_ctrl
vmap work work_core_ctrl
vlog -sv -work work_core_ctrl ../src/core/riscv_pkg.sv ../src/core/core_ctrl.sv ./tb/tb_core_ctrl.sv
vsim -c -voptargs=+acc work_core_ctrl.tb_core_ctrl
set BreakOnAssertion 2
run -all
quit -code 0
