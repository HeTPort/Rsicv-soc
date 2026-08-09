transcript on
onerror {quit -code 1}
if {[file exists work_compile_soc]} {
  vdel -lib work_compile_soc -all
}
vlib work_compile_soc
vmap work work_compile_soc
vlog -sv -work work_compile_soc -f filelist.f
quit -code 0
