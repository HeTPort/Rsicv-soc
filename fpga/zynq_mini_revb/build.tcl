# Reproducible Vivado 2019.2 batch build for the Bo Chen Jing Xin ZYNQ MINI
# 20240221/REVB board.
#
# Usage:
#   vivado -mode batch -source fpga/zynq_mini_revb/build.tcl -tclargs hello
#   vivado -mode batch -source fpga/zynq_mini_revb/build.tcl -tclargs timer_gpio
#   vivado -mode batch -source fpga/zynq_mini_revb/build.tcl -tclargs timer_irq
#   vivado -mode batch -source fpga/zynq_mini_revb/build.tcl -tclargs freertos_demo

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ../..]]

if {$argc > 1} {
  error "Expected zero or one application name: hello, timer_gpio, timer_irq, or freertos_demo"
}
set app_name [expr {$argc == 1 ? [lindex $argv 0] : "hello"}]

# Hardware-visible timer profiles.  The firmware images are unchanged; only
# the mtime prescaler differs so LED changes and interrupts can be observed.
array set timer_ticks {
  hello       1
  timer_gpio  1250000
  timer_irq   25000
  freertos_demo 1
}
if {![info exists timer_ticks($app_name)]} {
  error "Unknown application '$app_name'; expected hello, timer_gpio, timer_irq, or freertos_demo"
}
set timer_tick_cycles $timer_ticks($app_name)

if {[info exists ::env(ZYNQ_MINI_PART)] && $::env(ZYNQ_MINI_PART) ne ""} {
  set part_name $::env(ZYNQ_MINI_PART)
} else {
  # Conservative choice while the physical package does not expose a readable
  # speed-grade line.  Override only after positive device identification.
  set part_name xc7z010clg400-1
}

set program_image [file normalize [file join $repo_root testdata firmware_${app_name}.imem.hex]]
set data_image    [file normalize [file join $repo_root testdata firmware_${app_name}.dmem.hex]]
set xdc_file      [file normalize [file join $script_dir constraints.xdc]]
set output_dir    [file normalize [file join $repo_root build zynq_mini_revb $app_name]]

foreach required_file [list $program_image $data_image $xdc_file] {
  if {![file exists $required_file]} {
    error "Required input is missing: $required_file"
  }
}
file mkdir $output_dir

set rtl_files [list \
  [file join $repo_root src generated soc_mem_map_pkg.sv] \
  [file join $repo_root src core riscv_pkg.sv] \
  [file join $repo_root src core pc_counter.sv] \
  [file join $repo_root src core if2id.sv] \
  [file join $repo_root src core id2ex.sv] \
  [file join $repo_root src core ex2wb.sv] \
  [file join $repo_root src core decode.sv] \
  [file join $repo_root src core radix2_divider.sv] \
  [file join $repo_root src core execute.sv] \
  [file join $repo_root src core lsu.sv] \
  [file join $repo_root src core retire_stage.sv] \
  [file join $repo_root src core csr_regfile.sv] \
  [file join $repo_root src core regfile.sv] \
  [file join $repo_root src core core_ctrl.sv] \
  [file join $repo_root src mem prog_ram.sv] \
  [file join $repo_root src mem data_ram.sv] \
  [file join $repo_root src bus core_bus_data_ram.sv] \
  [file join $repo_root src bus core_bus_default_target.sv] \
  [file join $repo_root src periph mtime_timer.sv] \
  [file join $repo_root src periph uart_tx.sv] \
  [file join $repo_root src periph uart_rx.sv] \
  [file join $repo_root src periph core_bus_uart.sv] \
  [file join $repo_root src periph core_bus_gpio.sv] \
  [file join $repo_root src bus soc_data_fabric.sv] \
  [file join $repo_root src core riscv.sv] \
  [file join $repo_root src riscv_soc.sv] \
  [file join $script_dir top.sv] \
]

create_project -in_memory -part $part_name
set_property target_language Verilog [current_project]
read_verilog -sv $rtl_files
read_xdc $xdc_file

synth_design \
  -top top \
  -part $part_name \
  -generic [list \
    PROGRAM_INIT_FILE=$program_image \
    DATA_INIT_FILE=$data_image \
    TIMER_TICK_CYCLES=$timer_tick_cycles \
  ]

set bram_cells [get_cells -hier -filter {
  REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1
}]
set program_brams [get_cells -hier -filter {
  (REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1) && NAME =~ *u_prog_ram*
}]
set data_brams [get_cells -hier -filter {
  (REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1) && NAME =~ *u_data_ram*
}]

proc has_nonzero_init {cells} {
  foreach cell $cells {
    foreach property [list_property -regexp $cell {^INIT_[0-9A-F][0-9A-F]$}] {
      set value [get_property $property $cell]
      set digits [regsub {^[^']*'h} $value ""]
      if {![regexp {^0+$} $digits]} {
        return 1
      }
    }
  }
  return 0
}

if {[llength $program_brams] == 0 || ![has_nonzero_init $program_brams]} {
  error "Program BRAM initialization was not preserved by synthesis"
}
if {[llength $data_brams] == 0 || ![has_nonzero_init $data_brams]} {
  error "Data BRAM initialization was not preserved by synthesis"
}

write_checkpoint -force [file join $output_dir top_post_synth.dcp]
report_utilization -file [file join $output_dir utilization_post_synth.rpt]

opt_design
place_design
phys_opt_design
route_design

set timing_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $timing_path] != 1} {
  error "Expected one routed setup timing path"
}
set routed_wns [get_property SLACK $timing_path]

report_timing_summary -delay_type max -max_paths 20 -file [file join $output_dir timing_summary_routed.rpt]
report_timing -delay_type max -max_paths 20 -sort_by group -file [file join $output_dir timing_paths_routed.rpt]
report_utilization -hierarchical -file [file join $output_dir utilization_routed.rpt]
report_clock_utilization -file [file join $output_dir clock_utilization.rpt]
report_power -file [file join $output_dir power_estimate.rpt]
report_drc -file [file join $output_dir drc_routed.rpt]

# Do not rely on bitgen to reject hazardous DRCs. In particular, a
# combinational-loop Critical Warning invalidates timing even if WNS is positive.
set blocking_drc {}
foreach violation [get_drc_violations -quiet] {
  set severity [get_property SEVERITY $violation]
  if {$severity eq "Error" || $severity eq "Critical Warning"} {
    lappend blocking_drc $violation
  }
}
if {[llength $blocking_drc] != 0} {
  error "Blocking routed DRC violations remain: $blocking_drc"
}

write_checkpoint -force [file join $output_dir top_routed.dcp]

set metadata [open [file join $output_dir build_metadata.txt] w]
puts $metadata "BOARD=Bo Chen Jing Xin ZYNQ MINI 20240221/REVB"
puts $metadata "VIVADO_VERSION=[version -short]"
puts $metadata "PART=$part_name"
puts $metadata "PART_ASSUMPTION=conservative -1 speed grade; package mark not readable"
puts $metadata "APPLICATION=$app_name"
puts $metadata "PROGRAM_IMAGE=$program_image"
puts $metadata "DATA_IMAGE=$data_image"
puts $metadata "CORE_CLOCK_HZ=25000000"
puts $metadata "TIMER_TICK_CYCLES=$timer_tick_cycles"
puts $metadata "ROUTED_WNS_NS=$routed_wns"
puts $metadata "BRAM_COUNT=[llength $bram_cells]"
puts $metadata "PROGRAM_BRAM_COUNT=[llength $program_brams]"
puts $metadata "DATA_BRAM_COUNT=[llength $data_brams]"
close $metadata

if {$routed_wns < 0.0} {
  error "Routed timing failed: WNS is $routed_wns ns"
}

set bitstream_file [file join $output_dir zynq_mini_revb_${app_name}.bit]
write_bitstream -force $bitstream_file

puts "ZYNQ_MINI_BOARD=20240221/REVB"
puts "ZYNQ_MINI_PART=$part_name"
puts "ZYNQ_MINI_APPLICATION=$app_name"
puts "ZYNQ_MINI_TIMER_TICK_CYCLES=$timer_tick_cycles"
puts "ZYNQ_MINI_ROUTED_WNS_NS=$routed_wns"
puts "ZYNQ_MINI_BITSTREAM=$bitstream_file"
puts "ZYNQ MINI REVB BUILD PASS"
