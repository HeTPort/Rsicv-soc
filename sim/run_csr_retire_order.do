onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv ../src/core/riscv_pkg.sv ../src/core/retire_stage.sv ../src/core/csr_regfile.sv tb/tb_csr_retire_order.sv
vsim -c -voptargs=+acc work.tb_csr_retire_order
run -all
quit -code 0
