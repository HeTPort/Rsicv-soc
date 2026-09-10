# Interactive use: vivado -mode gui -source tools/divider_lab/open_vivado_lab.tcl
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../..]]
set dcp [file join $repo_root build divider_lab vivado divider_routed_40ns.dcp]
if {![file exists $dcp]} {error "Run vivado_lab.tcl first; missing $dcp"}
open_checkpoint $dcp
add_files -norecurse [file join $repo_root src core radix2_divider.sv]
report_timing_summary -delay_type min_max -name divider_timing_40ns
set divider_path [get_timing_paths -delay_type max -from [all_registers] \
  -to [all_registers] -max_paths 1 -nworst 1]
report_timing -delay_type max -from [all_registers] -to [all_registers] \
  -max_paths 1 -nworst 1 -path_type full_clock_expanded \
  -input_pins -name divider_worst_path
puts "Open divider_worst_path; select the path, then right-click Schematic."
puts "Useful Tcl: get_cells -hier *remainder*"
puts "Useful Tcl: report_property \[get_cells {remainder_o_reg\[31\]}\]"
