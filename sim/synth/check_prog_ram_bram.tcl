# AR-005 out-of-context synthesis check for synchronous instruction BRAM.
#
# Override the provisional part when the exact board is known:
#   set AR005_PART xc7z010clg400-1
#   vivado -mode batch -source check_prog_ram_bram.tcl

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ../..]]
set output_dir [file normalize [file join $repo_root build vivado_ar005]]

if {[info exists ::env(AR005_PART)] && $::env(AR005_PART) ne ""} {
  set part_name $::env(AR005_PART)
} else {
  set part_name xc7z010clg400-1
}

file mkdir $output_dir
read_verilog -sv [file join $repo_root src mem prog_ram.sv]
synth_design -top prog_ram -part $part_name -mode out_of_context

set bram_cells [get_cells -hier -filter {
  REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1
}]
set bram_count [llength $bram_cells]

report_utilization -file [file join $output_dir prog_ram_utilization.rpt]
write_checkpoint -force [file join $output_dir prog_ram_synth.dcp]

puts "AR005_PART=$part_name"
puts "AR005_BRAM_COUNT=$bram_count"
foreach bram_cell $bram_cells {
  puts "AR005_BRAM_CELL=$bram_cell REF_NAME=[get_property REF_NAME $bram_cell]"
}

if {$bram_count == 0} {
  error "AR-005 failed: prog_ram did not infer RAMB18E1/RAMB36E1 cells"
}

puts "AR-005 PASS: prog_ram inferred Block RAM"
