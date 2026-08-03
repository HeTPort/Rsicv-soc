# Run the ACT4 4.0.0 RV32I build/import for the rsicv-soc target.
# This script exists because the wsl.exe command is too long to paste
# reliably into PowerShell without line breaks being interpreted.

$ErrorActionPreference = "Stop"

$envVars = @(
    "PATH=/home/het/.local/bin:/home/het/.local/sail-riscv-0.10/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    "ACT4_ROOT=/home/het/riscv-arch-test",
    "ACT4_WORK_DIR=/home/het/act4-work/rsicv-soc",
    "ACT4_TARGET_NAME=rsicv-soc-rv32im-clang",
    "ACT4_EXTENSIONS=I",
    "ACT4_JOBS=8",
    "ACT4_CONFIG_FILE=/mnt/d/Rsicv-soc/verif/act4/rv32im_core/test_config_clang.yaml",
    "ACT4_COMPILER_TOOL=clang",
    "ACT4_OBJDUMP_TOOL=llvm-objdump"
)

$wslArgs = @("-e", "env") + $envVars + @(
    "bash", "-o", "pipefail", "-lc",
    "cd /mnt/d/Rsicv-soc && bash sim/regress/build_act4_wsl.sh 2>&1 | tee build/act4/act4_rv32i_build_resume.log"
)

wsl.exe @wslArgs
