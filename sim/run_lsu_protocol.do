transcript on
if {[file exists work_lsu]} {
  vdel -lib work_lsu -all
}
vlib work_lsu
vmap work work_lsu
vlog -sv -work work_lsu -f filelist.f
vsim -c -voptargs=+acc work_lsu.tb_lsu_protocol
run -all
quit -f
