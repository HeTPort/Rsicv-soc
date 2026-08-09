# Compare one generated RAM-capacity profile per Vivado invocation.
# Usage:
#   vivado -mode batch -source compare_riscv_soc_ram_utilization.tcl \
#     -tclargs ram_16k
#   vivado -mode batch -source compare_riscv_soc_ram_utilization.tcl \
#     -tclargs ram_64k
#
# The generated profiles control physical RAM depths and therefore the
# implemented data-RAM decode end. This script proves neither functional decode
# behavior nor exact-board timing closure.

set script_dir   [file dirname [file normalize [info script]]]
set repo_root    [file normalize [file join $script_dir ../..]]
set map_tcl      [file join $repo_root sim generated soc_map.tcl]
set profiles_tcl [file join $repo_root sim generated soc_ram_utilization_profiles.tcl]

foreach generated_file [list $map_tcl $profiles_tcl] {
  if {![file exists $generated_file]} {
    error "Generated SoC configuration is missing: run python tools/gen_soc_map.py"
  }
}
source $map_tcl
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
set output_dir [file normalize [file join $repo_root build vivado_$profile_name]]

if {[info exists ::env(SOC_MAP_PART)] && $::env(SOC_MAP_PART) ne ""} {
  set part_name $::env(SOC_MAP_PART)
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
  [file join $repo_root src periph uart_tx.sv] \
  [file join $repo_root src periph core_bus_uart.sv] \
  [file join $repo_root src bus soc_data_fabric.sv] \
  [file join $repo_root src core riscv.sv] \
  [file join $repo_root src riscv_soc.sv] \
]

read_verilog -sv $rtl_files
synth_design \
  -top riscv_soc \
  -part $part_name \
  -mode out_of_context \
  -generic [list \
    AW=$SOC_ADDRESS_WIDTH \
    DW=$SOC_DATA_WIDTH \
    PROG_RAM_DEPTH=$depth_words \
    DATA_RAM_DEPTH=$depth_words \
    DATA_REQ_WAIT_CYCLES=0 \
    DATA_RSP_WAIT_CYCLES=0 \
  ]

set bram18_cells [get_cells -hier -filter {REF_NAME == RAMB18E1}]
set bram36_cells [get_cells -hier -filter {REF_NAME == RAMB36E1}]

report_utilization -file [file join $output_dir riscv_soc_utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 4 \
  -file [file join $output_dir riscv_soc_hierarchical_utilization.rpt]
write_checkpoint -force [file join $output_dir riscv_soc_synth.dcp]

set metadata_file [open [file join $output_dir experiment_metadata.txt] w]
puts $metadata_file "SOURCE_MAP=$SOC_RAM_UTILIZATION_SOURCE_MAP"
puts $metadata_file "SOURCE_STATUS=$SOC_MAP_STATUS"
puts $metadata_file "PROFILE=$profile_name"
puts $metadata_file "PART=$part_name"
puts $metadata_file "VIVADO_VERSION=[version -short]"
puts $metadata_file "BANK_BYTES=$bank_bytes"
puts $metadata_file "DEPTH_WORDS=$depth_words"
puts $metadata_file "RAMB18E1_COUNT=[llength $bram18_cells]"
puts $metadata_file "RAMB36E1_COUNT=[llength $bram36_cells]"
close $metadata_file

puts "SOC_RAM_PROFILE=$profile_name"
puts "SOC_RAM_BANK_BYTES=$bank_bytes"
puts "SOC_RAM_DEPTH_WORDS=$depth_words"
puts "SOC_RAM_PART=$part_name"
puts "SOC_RAM_RAMB18E1_COUNT=[llength $bram18_cells]"
puts "SOC_RAM_RAMB36E1_COUNT=[llength $bram36_cells]"

if {[llength $bram18_cells] + [llength $bram36_cells] == 0} {
  error "RAM utilization profile did not retain Block RAM cells"
}

puts "RAM utilization profile synthesis PASS: $profile_name"
