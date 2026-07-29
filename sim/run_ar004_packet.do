transcript on
if {[file exists work_ar004]} {
  vdel -lib work_ar004 -all
}
vlib work_ar004
vmap work work_ar004
vlog -sv -work work_ar004 \
  ./../src/core/riscv_pkg.sv \
  ./../src/core/wb_stage.sv \
  ./tb/tb_ar004_packet_contract.sv
vsim -c -voptargs=+acc work_ar004.tb_ar004_packet_contract
run -all
quit -f
