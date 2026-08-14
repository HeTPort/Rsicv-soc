# Phase 5 OOC check: synthesize the SoC with the same hello instruction/data
# images used by ModelSim and prove both inferred BRAM banks carry nonzero INIT.

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ../..]]
set output_dir [file normalize [file join $repo_root build vivado_phase5_firmware_init]]
set map_tcl    [file join $repo_root sim generated soc_map.tcl]
set program_image [file normalize [file join $repo_root testdata firmware_hello.imem.hex]]
set data_image    [file normalize [file join $repo_root testdata firmware_hello.dmem.hex]]

if {![file exists $map_tcl]} {
  error "Generated SoC map is missing: run python tools/gen_soc_map.py"
}
if {![file exists $program_image] || ![file exists $data_image]} {
  error "Phase 5 hello images are missing: run sw/build_firmware_wsl.sh --install hello"
}
source $map_tcl

if {[info exists ::env(PHASE5_PART)] && $::env(PHASE5_PART) ne ""} {
  set part_name $::env(PHASE5_PART)
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
  [file join $repo_root src periph uart_rx.sv] \
  [file join $repo_root src periph core_bus_uart.sv] \
  [file join $repo_root src periph core_bus_gpio.sv] \
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
    PROG_RAM_DEPTH=$SOC_PROG_RAM_DEPTH_WORDS \
    DATA_RAM_DEPTH=$SOC_DATA_RAM_DEPTH_WORDS \
    PROGRAM_INIT_FILE=$program_image \
    DATA_INIT_FILE=$data_image \
  ]

set bram_cells [get_cells -hier -filter {
  REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1
}]
set program_brams [get_cells -hier -filter {
  (REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1) && NAME =~ *u_prog_ram*
}]
set data_brams [get_cells -hier -filter {
  (REF_NAME == RAMB18E1 || REF_NAME == RAMB36E1) && NAME =~ *u_data_ram*
}]

proc has_nonzero_init {cells} {
  foreach cell $cells {
    foreach property [list_property -regexp $cell {^INIT_[0-9A-F][0-9A-F]$}] {
      set value [get_property $property $cell]
      set digits [regsub {^[^']*'h} $value ""]
      if {![regexp {^0+$} $digits]} {
        return 1
      }
    }
  }
  return 0
}

puts "PHASE5_PART=$part_name"
puts "PHASE5_PROGRAM_IMAGE=$program_image"
puts "PHASE5_DATA_IMAGE=$data_image"
puts "PHASE5_BRAM_COUNT=[llength $bram_cells]"
puts "PHASE5_PROGRAM_BRAM_COUNT=[llength $program_brams]"
puts "PHASE5_DATA_BRAM_COUNT=[llength $data_brams]"

if {[llength $program_brams] == 0} {
  error "Phase 5 failed: no program BRAM cells found below u_prog_ram"
}
if {[llength $data_brams] == 0} {
  error "Phase 5 failed: no data BRAM cells found below u_data_ram"
}
if {![has_nonzero_init $program_brams]} {
  error "Phase 5 failed: program BRAM INIT properties are all zero"
}
if {![has_nonzero_init $data_brams]} {
  error "Phase 5 failed: data BRAM INIT properties are all zero"
}

report_utilization -file [file join $output_dir riscv_soc_utilization.rpt]
write_checkpoint -force [file join $output_dir riscv_soc_firmware_init.dcp]
puts "PHASE5 PASS: program and data firmware images produced nonzero BRAM INIT properties"
