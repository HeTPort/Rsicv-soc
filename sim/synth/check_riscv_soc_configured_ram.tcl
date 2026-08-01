# Out-of-context utilization experiment driven by the generated SoC map.
# This proves physical RAM inference/cost only. It does not implement or verify
# the proposed architectural decoder, base subtraction, or access-fault paths.

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ../..]]
set map_tcl    [file join $repo_root sim generated soc_map.tcl]

if {![file exists $map_tcl]} {
  error "Generated SoC map is missing: run python tools/gen_soc_map.py"
}
source $map_tcl

set output_dir [file normalize [file join $repo_root build vivado_$SOC_MAP_NAME]]
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
  [file join $repo_root src core wb_stage.sv] \
  [file join $repo_root src core csr_regfile.sv] \
  [file join $repo_root src core regfile.sv] \
  [file join $repo_root src core core_ctrl.sv] \
  [file join $repo_root src mem prog_ram.sv] \
  [file join $repo_root src mem data_ram.sv] \
  [file join $repo_root src bus core_bus_data_ram.sv] \
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
    PROG_RAM_DEPTH=$SOC_PROG_RAM_DEPTH_WORDS \
    DATA_RAM_DEPTH=$SOC_DATA_RAM_DEPTH_WORDS \
  ]

set bram_cells [get_cells -hier -filter {
  REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1
}]

report_utilization -file [file join $output_dir riscv_soc_utilization.rpt]
write_checkpoint -force [file join $output_dir riscv_soc_synth.dcp]

puts "SOC_MAP_NAME=$SOC_MAP_NAME"
puts "SOC_MAP_STATUS=$SOC_MAP_STATUS"
puts "SOC_MAP_PART=$part_name"
puts "SOC_PROG_RAM_DEPTH_WORDS=$SOC_PROG_RAM_DEPTH_WORDS"
puts "SOC_DATA_RAM_DEPTH_WORDS=$SOC_DATA_RAM_DEPTH_WORDS"
puts "SOC_MAP_BRAM_COUNT=[llength $bram_cells]"

if {[llength $bram_cells] == 0} {
  error "Configured SoC did not retain Block RAM cells"
}

puts "Configured SoC RAM utilization synthesis PASS"
