# Inspect power-relevant implemented objects and installed command syntax.
# Usage: vivado -mode batch -source inspect_routed_activity_objects.tcl \
#          -tclargs <routed.dcp> <output.txt>

if {$argc != 2} {
  error "Expected: <routed.dcp> <output.txt>"
}
set checkpoint [file normalize [lindex $argv 0]]
set output_path [file normalize [lindex $argv 1]]
open_checkpoint $checkpoint

set output [open $output_path w]
puts $output "VIVADO_VERSION=[version -short]"
puts $output "SET_SWITCHING_ACTIVITY_HELP_BEGIN"
help set_switching_activity
puts $output "See Vivado batch log for installed command help."
puts $output "SET_SWITCHING_ACTIVITY_HELP_END"

foreach ref_name {DSP48E1 RAMB36E1} {
  set cells [get_cells -hierarchical -filter "REF_NAME == $ref_name"]
  puts $output "REF_NAME=$ref_name COUNT=[llength $cells]"
  foreach cell $cells {
    puts $output "CELL=$cell"
    foreach pin [get_pins -quiet -of_objects $cell] {
      set nets [get_nets -quiet -of_objects $pin]
      if {[llength $nets] != 0} {
        puts $output "  PIN=$pin NETS=$nets"
      }
    }
  }
}
close $output
puts "P0_ROUTED_ACTIVITY_OBJECTS=$output_path"
