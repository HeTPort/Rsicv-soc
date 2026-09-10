onerror {quit -force -code 2}
onbreak {quit -force -code 0}
set lab_root $env(DIVIDER_LAB_ROOT)
vlib work
vlog -sv -work work \
  [file join $lab_root build divider_lab lint width_explicit radix2_divider.sv] \
  [file join $lab_root sim tb tb_radix2_divider.sv]
vsim -onfinish stop -sv_seed 20260909 -voptargs=+acc work.tb_radix2_divider
run -all
quit -force -code 0
