# Run from an isolated output directory, never from sim/work.
onerror {quit -force -code 2}
# ModelSim invokes onbreak for normal $finish as well. The Python runner is
# the authoritative gate: requires PASS, rejects errors, validates trace JSON.
onbreak {quit -force -code 0}
set lab_root $env(DIVIDER_LAB_ROOT)
vlib work
if {$env(DIVIDER_LAB_MODE) eq "original"} {
    vlog -sv -work work [file join $lab_root src core radix2_divider.sv] [file join $lab_root sim tb tb_radix2_divider.sv]
    vsim -onfinish stop -sv_seed 20260909 -voptargs=+acc work.tb_radix2_divider
} else {
    vlog -sv -work work [file join $lab_root src core radix2_divider.sv] [file join $lab_root tools divider_lab tb_divider_lab.sv]
    set extra_args {}
    if {$env(DIVIDER_LAB_MODE) eq "negative"} {lappend extra_args +BAD_EXPECT_Q}
    vsim -onfinish stop -sv_seed 20260909 -voptargs=+acc -wlf divider.wlf work.tb_divider_lab {*}$extra_args
    log -r /tb_divider_lab/*
    vcd file divider.vcd
    vcd add -r /tb_divider_lab/*
}
run -all
# $finish and $fatal both stop with -onfinish stop; Python checks the PASS/error
# markers as well as the process return code. A zero exit alone is not proof.
quit -force -code 0
