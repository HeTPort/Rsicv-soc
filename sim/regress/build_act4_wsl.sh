#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
act4_root="${ACT4_ROOT:-${HOME}/riscv-arch-test}"
config_file="${repo_root}/verif/act4/rv32im_core/test_config.yaml"
work_dir="${repo_root}/build/act4/work"
extensions="${ACT4_EXTENSIONS:-I}"
jobs="${ACT4_JOBS:-1}"
debug="${ACT4_DEBUG:-True}"

for tool in make python3 riscv64-unknown-elf-gcc riscv64-unknown-elf-objdump sail_riscv_sim; do
  command -v "${tool}" >/dev/null || {
    echo "Missing ACT4 prerequisite: ${tool}" >&2
    exit 1
  }
done
[[ -f "${act4_root}/Makefile" ]] || {
  echo "ACT4 source not found at ${act4_root}. Set ACT4_ROOT to the riscv-arch-test 4.0.0 checkout." >&2
  exit 1
}

echo "[ACT4] source     ${act4_root}"
echo "[ACT4] config     ${config_file}"
echo "[ACT4] extensions ${extensions}"
echo "[ACT4] work       ${work_dir}"

make -C "${act4_root}" \
  CONFIG_FILES="${config_file}" \
  WORKDIR="${work_dir}" \
  EXTENSIONS="${extensions}" \
  DEBUG="${debug}" \
  --jobs "${jobs}"

elf_dir="${work_dir}/rsicv-soc-rv32im/elfs"
[[ -d "${elf_dir}" ]] || {
  echo "ACT4 completed but the expected ELF directory was not created: ${elf_dir}" >&2
  exit 1
}

python3 "${script_dir}/import_act4.py" "${elf_dir}" \
  --repo-root "${repo_root}" \
  --output-dir "${repo_root}/build/act4/images" \
  --manifest "${repo_root}/build/act4/tests.json" \
  --tag rv32i

echo "ACT4 images are ready. Run this from Windows PowerShell:"
echo "  sim\\regress\\run_regression.ps1 -Manifest build\\act4\\tests.json -Tag act4"
