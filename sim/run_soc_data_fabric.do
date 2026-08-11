onerror {quit -code 1}

if {[file exists work_soc_data_fabric]} {
  vdel -lib work_soc_data_fabric -all
}

vlib work_soc_data_fabric
vmap work work_soc_data_fabric

vlog -sv -work work_soc_data_fabric \
  ../src/core/riscv_pkg.sv \
  ../src/bus/core_bus_default_target.sv \
  ../src/bus/soc_data_fabric.sv \
  ./tb/tb_soc_data_fabric.sv

vsim -c -voptargs=+acc \
  work_soc_data_fabric.tb_soc_data_fabric

run -all

quit -code [expr {
  [coverage attribute -name TESTSTATUS -concise] ne "OK"
}]