# ModelSim 2019.2 marker-controlled backward-SAIF capture.
# Required environment variables:
#   POWER_SAIF_PATH   absolute output path using forward slashes
#   POWER_REPORT_PATH absolute tabular report path using forward slashes

if {![info exists env(POWER_SAIF_PATH)]} {
  error "POWER_SAIF_PATH is not set"
}
if {![info exists env(POWER_REPORT_PATH)]} {
  error "POWER_REPORT_PATH is not set"
}

# Track the complete logic hierarchy while treating inferred RAM storage arrays
# at their synthesizable port/boundary level. Recursing into both 64 KiB RTL
# memory arrays is prohibitively slow and does not create corresponding routed
# scalar nets; BRAM clock/address/data/enable activity is the mapping boundary.
power add -ports -internal /tb_power/u_soc/*
power add -r /tb_power/u_soc/u_riscv/*
power add -r /tb_power/u_soc/u_data_fabric/*
power add -r /tb_power/u_soc/u_gpio_target/*
power add -r /tb_power/u_soc/u_uart_target/*
power add -r /tb_power/u_soc/u_timer_target/*
power add -ports /tb_power/u_soc/u_prog_ram/*
power add -ports -internal /tb_power/u_soc/u_data_target/*
power add -ports /tb_power/u_soc/u_data_target/u_data_ram/*
power off -all

# Optional diagnostic VCD uses the same architectural window. It is not the
# power annotation input, and is kept off in routine repeatability runs.
if {[info exists env(POWER_VCD_PATH)] && $env(POWER_VCD_PATH) ne ""} {
  vcd file $env(POWER_VCD_PATH)
  vcd add -ports /tb_power/u_soc/*
  vcd add -ports /tb_power/u_soc/u_riscv/*
  vcd add -ports -internal /tb_power/u_soc/u_timer_target/*
  vcd add -ports /tb_power/u_soc/u_prog_ram/*
  vcd add -ports /tb_power/u_soc/u_data_target/*
  vcd off
}

when -label power_start {/tb_power/capture_active == 1} {
  power reset -all
  power on -all
  if {[info exists env(POWER_VCD_PATH)] && $env(POWER_VCD_PATH) ne ""} {
    vcd on
  }
  nowhen power_start
  puts "POWER-CAPTURE START"
}
when -label power_end {/tb_power/capture_complete == 1} {
  power off -all
  if {[info exists env(POWER_VCD_PATH)] && $env(POWER_VCD_PATH) ne ""} {
    vcd off
    vcd flush
    puts "POWER-CAPTURE VCD: $env(POWER_VCD_PATH)"
  }
  power report -all -file $env(POWER_REPORT_PATH) -bsaif $env(POWER_SAIF_PATH)
  nowhen power_end
  puts "POWER-CAPTURE END"
  puts "POWER-CAPTURE SAIF: $env(POWER_SAIF_PATH)"
  puts "POWER-CAPTURE REPORT: $env(POWER_REPORT_PATH)"
}

run -all
quit -f
