# ModelSim marker-controlled capture for the exact routed functional netlist.
# Required environment variables:
#   POWER_SAIF_PATH   absolute output path using forward slashes
#   POWER_REPORT_PATH absolute tabular report path using forward slashes

if {![info exists env(POWER_SAIF_PATH)]} {
  error "POWER_SAIF_PATH is not set"
}
if {![info exists env(POWER_REPORT_PATH)]} {
  error "POWER_REPORT_PATH is not set"
}

# Capture ports recursively. Every routed net terminates on one or more cell
# ports, while this avoids tracking private behavioral arrays inside RAM models.
power add -r -ports /tb_power_postroute/u_dut/*
power add -ports -internal /tb_power_postroute/u_dut/*
power off -all

when -label power_start {/tb_power_postroute/capture_active == 1} {
  power reset -all
  power on -all
  nowhen power_start
  puts "POSTROUTE POWER-CAPTURE START"
}
when -label power_end {/tb_power_postroute/capture_complete == 1} {
  power off -all
  power report -all -file $env(POWER_REPORT_PATH) -bsaif $env(POWER_SAIF_PATH)
  nowhen power_end
  puts "POSTROUTE POWER-CAPTURE END"
  puts "POSTROUTE POWER-CAPTURE SAIF: $env(POWER_SAIF_PATH)"
}

run -all
quit -f
