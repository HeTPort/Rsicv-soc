# Compare vectorless and marker-window SAIF power on one routed checkpoint.
# Usage:
#   vivado -mode batch -source analyze_vivado_power.tcl \
#     -tclargs <routed.dcp> <activity.saif> <output-dir> <strip-path> \
#              ?<reviewed-activity-bridge.tcl> ...?

if {$argc < 4} {
  error "Expected: <routed.dcp> <activity.saif> <output-dir> <strip-path> ?<activity-bridge.tcl> ...?"
}

set checkpoint [file normalize [lindex $argv 0]]
set saif_file [file normalize [lindex $argv 1]]
set output_dir [file normalize [lindex $argv 2]]
set strip_path [lindex $argv 3]
set bridge_files [list]
foreach bridge_arg [lrange $argv 4 end] {
  lappend bridge_files [file normalize $bridge_arg]
}

set required_files [list $checkpoint $saif_file]
set required_files [concat $required_files $bridge_files]
foreach required_file $required_files {
  if {![file exists $required_file]} {
    error "Required input not found: $required_file"
  }
}
file mkdir $output_dir

open_checkpoint $checkpoint
set timing_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $timing_path] != 1} {
  error "Expected one routed setup timing path"
}
set routed_wns [get_property SLACK $timing_path]
if {$routed_wns < 0.0} {
  error "Refusing power analysis on timing-failing checkpoint: WNS $routed_wns ns"
}

report_power -file [file join $output_dir power_vectorless.rpt]

puts "P0_READ_SAIF_INPUT=$saif_file"
puts "P0_READ_SAIF_STRIP_PATH=$strip_path"
set read_result [read_saif -strip_path $strip_path $saif_file]
puts "P0_READ_SAIF_RESULT=$read_result"

if {[llength $bridge_files] != 0} {
  report_power -file [file join $output_dir power_saif_raw.rpt]
}
foreach bridge_file $bridge_files {
  puts "P0_ACTIVITY_BRIDGE=$bridge_file"
  source $bridge_file
}

if {[llength [info commands report_switching_activity]] != 0} {
  set switching_nets [get_nets -hierarchical *]
  if {[catch {
    report_switching_activity -file \
      [file join $output_dir switching_activity.rpt] $switching_nets
  } switching_error]} {
    puts "P0_SWITCHING_ACTIVITY_REPORT_WARNING=$switching_error"
  }
}
if {[llength $bridge_files] != 0} {
  report_power -file [file join $output_dir power_activity.rpt]
} else {
  report_power -file [file join $output_dir power_saif.rpt]
}

set metadata [open [file join $output_dir vivado_power_metadata.txt] w]
puts $metadata "VIVADO_VERSION=[version -short]"
puts $metadata "CHECKPOINT=$checkpoint"
puts $metadata "SAIF_FILE=$saif_file"
puts $metadata "SAIF_STRIP_PATH=$strip_path"
puts $metadata "ACTIVITY_BRIDGES=[join $bridge_files {;}]"
puts $metadata "ROUTED_WNS_NS=$routed_wns"
close $metadata

puts "P0_ROUTED_WNS_NS=$routed_wns"
puts "P0_VIVADO_POWER_OUTPUT=$output_dir"
puts "P0_VIVADO_POWER_ANALYSIS: PASS"
