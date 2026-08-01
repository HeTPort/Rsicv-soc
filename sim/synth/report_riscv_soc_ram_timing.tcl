# Report post-synthesis static timing for one generated RAM-capacity profile.
#
# Prerequisite:
#   compare_riscv_soc_ram_utilization.tcl must have generated the profile DCP.
#
# Usage:
#   vivado -mode batch -source report_riscv_soc_ram_timing.tcl \
#     -tclargs ram_16k
#   vivado -mode batch -source report_riscv_soc_ram_timing.tcl \
#     -tclargs ram_64k
#
# This flow constrains the single core clock at 50 MHz and 25 MHz and reports
# internal register-to-register setup paths. It does not perform placement,
# routing, I/O timing, SDF simulation, or board timing closure.

set script_dir   [file dirname [file normalize [info script]]]
set repo_root    [file normalize [file join $script_dir ../..]]
set profiles_tcl [file join $repo_root sim generated soc_ram_utilization_profiles.tcl]

if {![file exists $profiles_tcl]} {
  error "Generated RAM profiles are missing: run python tools/gen_soc_map.py"
}
source $profiles_tcl

if {$argc != 1} {
  error "Expected one generated profile: $SOC_RAM_UTILIZATION_PROFILE_NAMES"
}
set profile_name [lindex $argv 0]
if {[lsearch -exact $SOC_RAM_UTILIZATION_PROFILE_NAMES $profile_name] < 0} {
  error "Unknown profile '$profile_name'; expected $SOC_RAM_UTILIZATION_PROFILE_NAMES"
}

set bank_bytes $SOC_RAM_UTILIZATION_BANK_BYTES($profile_name)
set depth_words $SOC_RAM_UTILIZATION_DEPTH_WORDS($profile_name)
set build_dir   [file normalize [file join $repo_root build vivado_$profile_name]]
set checkpoint  [file join $build_dir riscv_soc_synth.dcp]
set output_dir  [file join $build_dir timing]

if {![file exists $checkpoint]} {
  error "Missing synthesized checkpoint for $profile_name: run compare_riscv_soc_ram_utilization.tcl first"
}
file mkdir $output_dir

set metadata_file [open [file join $output_dir timing_metadata.txt] w]
puts $metadata_file "SOURCE_MAP=$SOC_RAM_UTILIZATION_SOURCE_MAP"
puts $metadata_file "PROFILE=$profile_name"
puts $metadata_file "VIVADO_VERSION=[version -short]"
puts $metadata_file "BANK_BYTES=$bank_bytes"
puts $metadata_file "DEPTH_WORDS=$depth_words"
puts $metadata_file "ANALYSIS_STAGE=post_synthesis_static_timing"
puts $metadata_file "PATH_SCOPE=internal_register_to_register_setup"

foreach timing_case {
  {50mhz 20.000}
  {25mhz 40.000}
} {
  lassign $timing_case case_name period_ns
  open_checkpoint $checkpoint

  set clock_port [get_ports -quiet clk]
  if {[llength $clock_port] != 1} {
    error "Expected exactly one top-level clock port named clk"
  }
  set design_registers [all_registers]
  if {[llength $design_registers] == 0} {
    error "No sequential registers found in synthesized checkpoint"
  }
  create_clock -name core_clk -period $period_ns $clock_port

  set critical_path [get_timing_paths \
    -delay_type max \
    -from $design_registers \
    -to $design_registers \
    -max_paths 1 \
    -nworst 1]
  if {[llength $critical_path] != 1} {
    error "Expected one internal register-to-register setup path for $case_name"
  }

  report_timing_summary \
    -delay_type max \
    -max_paths 1 \
    -nworst 1 \
    -file [file join $output_dir riscv_soc_timing_summary_$case_name.rpt]
  report_timing \
    -delay_type max \
    -from $design_registers \
    -to $design_registers \
    -max_paths 1 \
    -nworst 1 \
    -sort_by group \
    -file [file join $output_dir riscv_soc_register_timing_$case_name.rpt]

  set case_prefix [string toupper $case_name]
  puts $metadata_file "${case_prefix}_PERIOD_NS=$period_ns"
  puts $metadata_file "${case_prefix}_WNS_NS=[get_property SLACK $critical_path]"
  puts $metadata_file "${case_prefix}_DATAPATH_DELAY_NS=[get_property DATAPATH_DELAY $critical_path]"
  puts $metadata_file "${case_prefix}_LOGIC_LEVELS=[get_property LOGIC_LEVELS $critical_path]"
  puts $metadata_file "${case_prefix}_STARTPOINT=[get_property STARTPOINT_PIN $critical_path]"
  puts $metadata_file "${case_prefix}_ENDPOINT=[get_property ENDPOINT_PIN $critical_path]"

  puts "SOC_RAM_TIMING_PROFILE=$profile_name"
  puts "SOC_RAM_TIMING_CASE=$case_name"
  puts "SOC_RAM_TIMING_PERIOD_NS=$period_ns"
  puts "SOC_RAM_TIMING_WNS_NS=[get_property SLACK $critical_path]"
  close_design
}

close $metadata_file
puts "RAM timing report PASS: $profile_name"
