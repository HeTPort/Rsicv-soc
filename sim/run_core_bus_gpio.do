onerror {quit -code 1}

if {[file exists work_core_bus_gpio]} {
  vdel -lib work_core_bus_gpio -all
}

vlib work_core_bus_gpio
vmap work work_core_bus_gpio

vlog -sv -work work_core_bus_gpio \
  ../src/core/riscv_pkg.sv \
  ../src/periph/core_bus_gpio.sv \
  ./tb/tb_core_bus_gpio.sv

vsim -c -voptargs=+acc work_core_bus_gpio.tb_core_bus_gpio
run -all

quit -code [expr {
  [coverage attribute -name TESTSTATUS -concise] ne "OK"
}]