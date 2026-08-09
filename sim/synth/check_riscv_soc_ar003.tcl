# AR-003 out-of-context synthesis check for the external CPU data bus, LSU
# transaction state machine, and core-bus-to-data-RAM adapter.
#
# Override the provisional part when the exact board is known:
#   set AR003_PART xc7z010clg400-1
#   vivado -mode batch -source check_riscv_soc_ar003.tcl

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ../..]]
set output_dir [file normalize [file join $repo_root build vivado_ar003]]

if {[info exists ::env(AR003_PART)] && $::env(AR003_PART) ne ""} {
  set part_name $::env(AR003_PART)
} else {
  set part_name xc7z010clg400-1
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
  [file join $repo_root src bus soc_data_fabric.sv] \
  [file join $repo_root src core riscv.sv] \
  [file join $repo_root src riscv_soc.sv] \
]

read_verilog -sv $rtl_files
synth_design -top riscv_soc -part $part_name -mode out_of_context

set bram_cells [get_cells -hier -filter {
  REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1
}]
set lsu_state_cells [get_cells -hier -regexp {
  .*u_riscv/u_lsu/state_q_reg.*
}]

report_utilization -file [file join $output_dir riscv_soc_utilization.rpt]
write_checkpoint -force [file join $output_dir riscv_soc_synth.dcp]

puts "AR003_PART=$part_name"
puts "AR003_BRAM_COUNT=[llength $bram_cells]"
puts "AR003_LSU_STATE_CELL_COUNT=[llength $lsu_state_cells]"

if {[llength $bram_cells] == 0} {
  error "AR-003 failed: riscv_soc did not retain Block RAM cells"
}
if {[llength $lsu_state_cells] == 0} {
  error "AR-003 failed: LSU transaction state was not synthesized"
}

puts "AR-003 PASS: SoC bus/LSU/RAM hierarchy synthesized"
