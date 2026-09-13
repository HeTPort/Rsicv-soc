onerror {quit -code 1}
if {[file exists work_rv32m]} {
  vdel -lib work_rv32m -all
}
vlib work_rv32m
vmap work work_rv32m
vlog -sv -work work_rv32m ../src/core/riscv_pkg.sv ../src/core/radix2_divider.sv ../src/core/rv32m_mul_comb.sv ../src/core/rv32m_unit.sv ./tb/tb_rv32m_unit.sv
vsim -c -voptargs=+acc work_rv32m.tb_rv32m_unit
run -all
quit -code 0
