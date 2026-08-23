onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv -f filelist.f tb/tb_fetch_error_timing.sv
vsim -c -voptargs=+acc work.tb_fetch_error_timing
run -all
if {[examine -radix decimal sim:/tb_fetch_error_timing/test_pass] != "1"} {
  quit -code 1
}
quit -code 0
