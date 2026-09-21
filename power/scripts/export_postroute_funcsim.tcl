# Export a functional simulation netlist from the exact routed checkpoint.
# Usage:
#   vivado -mode batch -source export_postroute_funcsim.tcl \
#     -tclargs <routed.dcp> <output-directory>

if {$argc != 2} {
  error "Expected: <routed.dcp> <output-directory>"
}

set checkpoint [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
if {![file exists $checkpoint]} {
  error "Routed checkpoint not found: $checkpoint"
}
file mkdir $output_dir

open_checkpoint $checkpoint
if {[get_property DESIGN_MODE [current_design]] ne "GateLvl"} {
  puts "P0_POSTROUTE_DESIGN_MODE=[get_property DESIGN_MODE [current_design]]"
}

set timing_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $timing_path] != 1} {
  error "Expected one routed setup timing path"
}
set routed_wns [get_property SLACK $timing_path]
if {$routed_wns < 0.0} {
  error "Refusing netlist export from timing-failing checkpoint: WNS $routed_wns ns"
}

set netlist [file join $output_dir top_postroute_funcsim.v]
write_verilog -force -mode funcsim -include_xilinx_libs $netlist

set metadata [open [file join $output_dir export_metadata.txt] w]
puts $metadata "VIVADO_VERSION=[version -short]"
puts $metadata "CHECKPOINT=$checkpoint"
puts $metadata "ROUTED_WNS_NS=$routed_wns"
puts $metadata "NETLIST=$netlist"
close $metadata

puts "P0_POSTROUTE_NETLIST=$netlist"
puts "P0_POSTROUTE_WNS_NS=$routed_wns"
puts "P0_POSTROUTE_EXPORT: PASS"
