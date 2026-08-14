#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
output_root="${repo_root}/build/firmware"
install_images=0
requested_apps=()

while (($# > 0)); do
  case "$1" in
    --install)
      install_images=1
      ;;
    --help|-h)
      echo "Usage: $0 [--install] [app ...]"
      echo "Builds sw/apps/<app> with the Phase 5 runtime and split memory map."
      exit 0
      ;;
    *)
      requested_apps+=("$1")
      ;;
  esac
  shift
done

tool_prefix="${RISCV_PREFIX:-riscv64-unknown-elf-}"
for tool in gcc objdump readelf size; do
  command -v "${tool_prefix}${tool}" >/dev/null || {
    echo "Missing tool: ${tool_prefix}${tool}" >&2
    exit 1
  }
done
command -v python3 >/dev/null || { echo "Missing tool: python3" >&2; exit 1; }

if ((${#requested_apps[@]} == 0)); then
  mapfile -t requested_apps < <(
    find "${repo_root}/sw/apps" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
  )
fi

common_flags=(
  -march=rv32im_zicsr
  -mabi=ilp32
  -mcmodel=medlow
  -msmall-data-limit=0
  -ffreestanding
  -fno-builtin
  -fno-pic
  -fno-pie
  -fno-stack-protector
  -fno-unwind-tables
  -fno-asynchronous-unwind-tables
  -ffunction-sections
  -fdata-sections
  -Wall
  -Wextra
  -Werror
)

for app in "${requested_apps[@]}"; do
  app_dir="${repo_root}/sw/apps/${app}"
  [[ -d "${app_dir}" ]] || { echo "Unknown firmware app: ${app}" >&2; exit 1; }
  out_dir="${output_root}/${app}"
  object_dir="${out_dir}/obj"
  mkdir -p "${object_dir}"

  sources=("${repo_root}/sw/common/startup.S")
  while IFS= read -r source_path; do
    sources+=("${source_path}")
  done < <(find "${repo_root}/sw/drivers" "${app_dir}" -maxdepth 1 -type f \
           \( -name '*.c' -o -name '*.S' \) | sort)

  objects=()
  for source_path in "${sources[@]}"; do
    relative="${source_path#${repo_root}/}"
    object_name="${relative//\//_}"
    object_path="${object_dir}/${object_name%.*}.o"
    "${tool_prefix}gcc" "${common_flags[@]}" -O2 -g3 \
      -I"${repo_root}/firmware/include" \
      -I"${repo_root}/sw/common" \
      -I"${repo_root}/sw/drivers" \
      -c "${source_path}" -o "${object_path}"
    objects+=("${object_path}")
  done

  elf_path="${out_dir}/${app}.elf"
  map_path="${out_dir}/${app}.map"
  "${tool_prefix}gcc" "${common_flags[@]}" \
    -nostartfiles -nostdlib -no-pie \
    -Wl,--gc-sections \
    -Wl,--no-relax \
    -Wl,--orphan-handling=warn \
    -Wl,-Map,"${map_path}" \
    -T "${repo_root}/sw/common/linker.ld" \
    -o "${elf_path}" "${objects[@]}" -lgcc

  "${tool_prefix}readelf" -h -l -S -s "${elf_path}" > "${out_dir}/${app}.readelf"
  "${tool_prefix}objdump" -drwC "${elf_path}" > "${out_dir}/${app}.dis"
  "${tool_prefix}size" -A "${elf_path}" > "${out_dir}/${app}.size"

  python3 "${repo_root}/sim/regress/elf_to_mem.py" \
    "${elf_path}" \
    --imem "${out_dir}/${app}.imem.hex" \
    --dmem "${out_dir}/${app}.dmem.hex" \
    --split-map "${repo_root}/sim/generated/soc_map.json" \
    --dmem-uninitialized-fill 0xA5

  if ((install_images)); then
    cp "${out_dir}/${app}.imem.hex" "${repo_root}/testdata/firmware_${app}.imem.hex"
    cp "${out_dir}/${app}.dmem.hex" "${repo_root}/testdata/firmware_${app}.dmem.hex"
  fi

  echo "[FIRMWARE] ${app}: ${elf_path}"
done

echo "Built ${#requested_apps[@]} firmware app(s) under ${output_root}"
if ((install_images)); then
  echo "Installed selected program/data images under ${repo_root}/testdata"
fi
