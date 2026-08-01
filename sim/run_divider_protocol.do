transcript on
if {[file exists work_divider]} {
  vdel -lib work_divider -all
}
vlib work_divider
vmap work work_divider
vlog -sv -work work_divider ../src/core/radix2_divider.sv ./tb/tb_radix2_divider.sv
vsim -c -voptargs=+acc work_divider.tb_radix2_divider
run -all
quit -f
