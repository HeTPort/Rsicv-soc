onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv ../src/core/riscv_pkg.sv ../src/core/decode.sv tb/tb_decode_fetch_error.sv
vsim -c -voptargs=+acc work.tb_decode_fetch_error
run -all
quit -code 0
