# Run from any directory with Vivado 2019.2:
# vivado -mode batch -source tools/divider_lab/vivado_lab.tcl
# This lab never writes a bitstream and never edits the production RTL.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ../..]]
set out_dir [file join $repo_root build divider_lab vivado]
file mkdir $out_dir

proc lab_report_paths {out_dir tag} {
  report_timing_summary -delay_type min_max -report_unconstrained -max_paths 10 \
    -file [file join $out_dir timing_summary_${tag}.rpt]
  report_timing -delay_type max -from [all_registers] -to [all_registers] \
    -max_paths 5 -nworst 1 -path_type full_clock_expanded -input_pins \
    -file [file join $out_dir reg2reg_setup_${tag}.rpt]
  report_timing -delay_type min -from [all_registers] -to [all_registers] \
    -max_paths 5 -nworst 1 -path_type full_clock_expanded -input_pins \
    -file [file join $out_dir reg2reg_hold_${tag}.rpt]
}

proc lab_main {repo_root script_dir out_dir} {
  set part_name xc7z010clg400-1
  create_project -in_memory -part $part_name
  set_property target_language Verilog [current_project]
  read_verilog -sv [file join $repo_root src core radix2_divider.sv]
  read_xdc [file join $script_dir divider_lab.xdc]
  synth_design -top radix2_divider -part $part_name -mode out_of_context
  write_checkpoint -force [file join $out_dir divider_synth.dcp]
  write_verilog -force -mode funcsim [file join $out_dir divider_synth_funcsim.v]
  report_utilization -file [file join $out_dir utilization_synth.rpt]

  # OOC clock root is a declared global-clock site, not a placed board MMCM.
  # This enables clock insertion-delay modeling at the isolated block boundary.
  set clock_site [lindex [get_sites -filter {SITE_TYPE == BUFGCTRL}] 0]
  if {$clock_site eq ""} {error "No BUFGCTRL site exists for the selected part"}
  set_property HD.CLK_SRC $clock_site [get_ports clk_i]
  opt_design
  place_design
  phys_opt_design
  route_design
  lab_report_paths $out_dir routed_40ns
  report_utilization -file [file join $out_dir utilization_routed.rpt]
  report_drc -file [file join $out_dir drc_routed.rpt]
  report_route_status -file [file join $out_dir route_status.rpt]
  report_exceptions -file [file join $out_dir exceptions.rpt]
  check_timing -verbose -file [file join $out_dir check_timing.rpt]
  write_checkpoint -force [file join $out_dir divider_routed_40ns.dcp]
  write_verilog -force -mode funcsim [file join $out_dir divider_routed_funcsim.v]
  write_xdc -force [file join $out_dir effective_routed.xdc]

  set worst [get_timing_paths -delay_type max -from [all_registers] \
    -to [all_registers] -max_paths 1 -nworst 1]
  if {[llength $worst] != 1} {error "Expected one register-to-register setup path"}
  set properties_file [open [file join $out_dir worst_path_properties.rpt] w]
  foreach prop [list_property $worst] {
    puts $properties_file "$prop=[get_property $prop $worst]"
  }
  close $properties_file
  set start_pin [get_property STARTPOINT_PIN $worst]
  set end_pin [get_property ENDPOINT_PIN $worst]
  set slack40 [get_property SLACK $worst]
  set delay40 [get_property DATAPATH_DELAY $worst]
  set requirement40 [get_property REQUIREMENT $worst]
  set hold40 [get_property SLACK [get_timing_paths -delay_type min \
    -from [all_registers] -to [all_registers] -max_paths 1]]
  set global_setup40 [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
  set global_hold40 [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
  set blocking_drc {}
  foreach violation [get_drc_violations -quiet] {
    set severity [get_property SEVERITY $violation]
    if {$severity eq "Error" || $severity eq "Critical Warning"} {
      lappend blocking_drc $violation
    }
  }
  set mapping [open [file join $out_dir rtl_netlist_mapping.rpt] w]
  puts $mapping "CURRENT_RTL=[file join $repo_root src core radix2_divider.sv]"
  puts $mapping "WORST_START=$start_pin"
  puts $mapping "WORST_END=$end_pin"
  puts $mapping "\nCells on the ACTUAL worst setup path (tool properties, no inferred line mapping):"
  set seen {}
  # Vivado 2019.2 exposes a path's pins through get_pins -of_objects; the
  # newer-looking TIMING_POINTS property is not available in this version.
  foreach pin [get_pins -of_objects $worst] {
    set cells [get_cells -quiet -of_objects $pin]
    foreach cell $cells {
      if {[lsearch -exact $seen $cell] >= 0} {continue}
      lappend seen $cell
      puts $mapping "\nCELL=$cell REF_NAME=[get_property REF_NAME $cell]"
      foreach prop [list_property $cell] {
        if {[regexp -nocase {file|line|orig|source|loc|bel} $prop]} {
          puts $mapping "$prop=[get_property $prop $cell]"
        }
      }
    }
  }
  puts $mapping "\nSequential cells retaining useful RTL names:"
  foreach cell [get_cells -hier -filter {REF_NAME =~ FD*}] {
    puts $mapping "$cell [get_property REF_NAME $cell]"
  }
  close $mapping

  # Requirement-only experiment: same cells, placement, routes and data delay.
  # Replacing the clock leaves clock-named IO/uncertainty constraints attached;
  # reapply XDC first on restore so the delivered checkpoint is always 40 ns.
  create_clock -name divider_clk -period 5.000 [get_ports clk_i]
  set_clock_uncertainty -setup 0.100 [get_clocks divider_clk]
  set_clock_uncertainty -hold 0.050 [get_clocks divider_clk]
  lab_report_paths $out_dir same_routes_5ns
  set tight [get_timing_paths -delay_type max -from $start_pin -to $end_pin -max_paths 1]
  set slack5 [get_property SLACK $tight]
  set delay5 [get_property DATAPATH_DELAY $tight]
  set requirement5 [get_property REQUIREMENT $tight]
  read_xdc [file join $script_dir divider_lab.xdc]

  set summary [open [file join $out_dir lab_summary.txt] w]
  puts $summary "VIVADO_VERSION=[version -short]"
  puts $summary "PART=$part_name"
  puts $summary "SCOPE=DW32 divider only; current RTL; out-of-context routed block"
  puts $summary "CLOCK_SITE=$clock_site"
  puts $summary "RESET_CAVEAT=all rst_ni paths false-pathed; reset release safety NOT proven"
  puts $summary "IO_CAVEAT=illustrative delays; not measured board/interface budgets"
  puts $summary "ROUTE_CAVEAT=data ports lack HD.PARTPIN_LOCS; boundary routes/IO timing are NOT signoff evidence"
  puts $summary "CLOCK_CAVEAT=HD.CLK_SRC models an OOC clock root; no board MMCM/BUFG tree is implemented"
  puts $summary "SIGNOFF=NOT_CLAIMED; global IO hold may fail under illustrative constraints"
  puts $summary "WORST_START=$start_pin"
  puts $summary "WORST_END=$end_pin"
  puts $summary "REG2REG_SLACK_40NS=$slack40"
  puts $summary "REG2REG_DATAPATH_DELAY_40NS=$delay40"
  puts $summary "REG2REG_REQUIREMENT_40NS=$requirement40"
  puts $summary "REG2REG_HOLD_SLACK_40NS=$hold40"
  puts $summary "GLOBAL_SETUP_SLACK_40NS=$global_setup40"
  puts $summary "GLOBAL_HOLD_SLACK_40NS=$global_hold40"
  puts $summary "BLOCKING_DRC_COUNT=[llength $blocking_drc]"
  puts $summary "SAME_PATH_SLACK_5NS=$slack5"
  puts $summary "SAME_PATH_DATAPATH_DELAY_5NS=$delay5"
  puts $summary "SAME_PATH_REQUIREMENT_5NS=$requirement5"
  puts $summary "FD_CELLS=[llength [get_cells -hier -filter {REF_NAME =~ FD*}]]"
  puts $summary "LUT_CELLS=[llength [get_cells -hier -filter {REF_NAME =~ LUT*}]]"
  puts $summary "CARRY4_CELLS=[llength [get_cells -hier -filter {REF_NAME == CARRY4}]]"
  puts $summary "DSP_CELLS=[llength [get_cells -hier -filter {REF_NAME =~ DSP*}]]"
  puts $summary "BRAM_CELLS=[llength [get_cells -hier -filter {REF_NAME =~ RAMB*}]]"
  puts $summary "RESTORED_CLOCK_PERIOD=[get_property PERIOD [get_clocks divider_clk]]"
  close $summary
  if {$slack40 < 0} {error "25 MHz register-to-register setup failed: $slack40 ns"}
  if {$hold40 < 0} {error "Register-to-register hold failed: $hold40 ns"}
  if {[llength $blocking_drc] != 0} {error "Blocking DRC violations: $blocking_drc"}
  if {$slack5 >= 0} {error "Expected the deliberately tight 5 ns same-path example to fail"}
  if {abs($delay40 - $delay5) > 0.002} {error "Data delay changed in requirement-only experiment"}
  puts "DIVIDER_VIVADO_LAB PASS (scoped internal-path experiment, NOT whole-design timing signoff)"
}

if {[catch {lab_main $repo_root $script_dir $out_dir} lab_error lab_options]} {
  puts stderr "DIVIDER_VIVADO_LAB FAIL: $lab_error"
  puts stderr [dict get $lab_options -errorinfo]
  exit 1
}
exit 0
