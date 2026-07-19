#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../.." && pwd)"
output_dir="${repo_root}/build/tests"
install_images=0
requested_tests=()

while (($# > 0)); do
  case "$1" in
    --install)
      install_images=1
      ;;
    --help|-h)
      echo "Usage: $0 [--install] [test-name ...]"
      echo "Builds testdata/*.S into build/tests. --install copies .hex files to testdata/."
      exit 0
      ;;
    *)
      requested_tests+=("$1")
      ;;
  esac
  shift
done

tool_prefix="${RISCV_PREFIX:-riscv64-unknown-elf-}"
march="${RISCV_MARCH:-rv32im_zicsr}"
mabi="${RISCV_MABI:-ilp32}"

for tool in as ld objcopy objdump; do
  command -v "${tool_prefix}${tool}" >/dev/null || {
    echo "Missing tool: ${tool_prefix}${tool}" >&2
    exit 1
  }
done
command -v od >/dev/null || { echo "Missing tool: od" >&2; exit 1; }

mkdir -p "${output_dir}"

if ((${#requested_tests[@]} == 0)); then
  mapfile -t sources < <(find "${repo_root}/testdata" -maxdepth 1 -type f -name '*.S' | sort)
else
  sources=()
  for test_name in "${requested_tests[@]}"; do
    source_path="${repo_root}/testdata/${test_name%.S}.S"
    [[ -f "${source_path}" ]] || { echo "Test source not found: ${source_path}" >&2; exit 1; }
    sources+=("${source_path}")
  done
fi

for source_path in "${sources[@]}"; do
  test_name="$(basename "${source_path}" .S)"
  object_path="${output_dir}/${test_name}.o"
  elf_path="${output_dir}/${test_name}.elf"
  binary_path="${output_dir}/${test_name}.bin"
  hex_path="${output_dir}/${test_name}.hex"

  echo "[BUILD] ${test_name}"
  "${tool_prefix}as" -march="${march}" -mabi="${mabi}" -mno-relax \
    -o "${object_path}" "${source_path}"
  "${tool_prefix}ld" -m elf32lriscv --no-relax -Ttext=0x0 -e _start \
    -o "${elf_path}" "${object_path}"
  "${tool_prefix}objcopy" -O binary "${elf_path}" "${binary_path}"
  od -An -v -t x4 "${binary_path}" | tr -s ' ' '\n' | sed '/^$/d' > "${hex_path}"
  "${tool_prefix}objdump" -d "${elf_path}" > "${output_dir}/${test_name}.dis"

  if ((install_images)); then
    cp "${hex_path}" "${repo_root}/testdata/${test_name}.hex"
  fi
done

echo "Built ${#sources[@]} test(s) in ${output_dir}"
if ((install_images)); then
  echo "Installed generated .hex images into ${repo_root}/testdata"
fi
