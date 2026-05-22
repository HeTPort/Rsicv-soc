transcript on
if {[file exists work]} {
    vdel -all
}
vlib work
vmap work work
vlog -sv -f filelist.f
vsim -voptargs=+acc work.tb_riscv_core
add wave -r /*
run -all