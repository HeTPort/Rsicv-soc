# Resume the retained first 95 MHz route and apply the same deterministic
# post-route closure step used by fpga/zynq_mini_revb/build.tcl.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../..]]
set build_dir [file join $repo_root build zynq_mini_revb p0_mix_95mhz]
set input_dcp [file join $build_dir top_routed.dcp]
set output_dcp [file join $build_dir top_routed_95mhz_closed.dcp]

if {![file exists $input_dcp]} {
  error "Input routed checkpoint not found: $input_dcp"
}

open_checkpoint $input_dcp
set timing_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $timing_path] != 1} {
  error "Expected one routed setup timing path"
}
set initial_wns [get_property SLACK $timing_path]
puts "P0_95MHZ_INITIAL_WNS_NS=$initial_wns"

if {$initial_wns < 0.0} {
  phys_opt_design -directive AggressiveExplore
}

set timing_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $timing_path] != 1} {
  error "Expected one post-optimization setup timing path"
}
set final_wns [get_property SLACK $timing_path]

report_timing_summary -delay_type max -max_paths 20 \
  -file [file join $build_dir timing_summary_95mhz_closed.rpt]
report_timing -delay_type max -max_paths 20 -sort_by group \
  -file [file join $build_dir timing_paths_95mhz_closed.rpt]
report_drc -file [file join $build_dir drc_95mhz_closed.rpt]
write_checkpoint -force $output_dcp

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
if {$final_wns < 0.0} {
  error "95 MHz timing remains open after post-route phys_opt: WNS $final_wns ns"
}

puts "P0_95MHZ_FINAL_WNS_NS=$final_wns"
puts "P0_95MHZ_CLOSED_DCP=$output_dcp"
puts "P0_95MHZ_TIMING_CLOSURE: PASS"
