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
      echo "FreeRTOS overrides: SOC_FREERTOS_MTIME_HZ, SOC_FREERTOS_DEMO_TIME_SCALE,"
      echo "SOC_FREERTOS_SIM_COMPLETION, and SOC_FREERTOS_IMAGE_SUFFIX (for example _sim)."
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
  artifact_name="${app}"
  if [[ "${app}" == "freertos_demo" ]]; then
    artifact_name+="${SOC_FREERTOS_IMAGE_SUFFIX:-}"
  fi
  out_dir="${output_root}/${artifact_name}"
  object_dir="${out_dir}/obj"
  mkdir -p "${object_dir}"

  sources=("${repo_root}/sw/common/startup.S")
  while IFS= read -r source_path; do
    sources+=("${source_path}")
  done < <(find "${repo_root}/sw/drivers" "${app_dir}" -maxdepth 1 -type f \
           \( -name '*.c' -o -name '*.S' \) | sort)

  app_flags=()
  include_dirs=(
    "${repo_root}/firmware/include"
    "${repo_root}/sw/common"
    "${repo_root}/sw/drivers"
    "${app_dir}"
  )

  if [[ "${app}" == "freertos_demo" ]]; then
    freertos_root="${repo_root}/third_party/FreeRTOS-Kernel"
    sources+=(
      "${repo_root}/sw/common/minilib.c"
      "${freertos_root}/tasks.c"
      "${freertos_root}/queue.c"
      "${freertos_root}/list.c"
      "${freertos_root}/portable/MemMang/heap_4.c"
      "${freertos_root}/portable/GCC/RISC-V/port.c"
      "${freertos_root}/portable/GCC/RISC-V/portASM.S"
    )
    include_dirs+=(
      "${repo_root}/sw/common/libc"
      "${freertos_root}/include"
      "${freertos_root}/portable/GCC/RISC-V"
      "${freertos_root}/portable/GCC/RISC-V/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions"
    )
    app_flags+=(
      "-DconfigCPU_CLOCK_HZ=${SOC_FREERTOS_MTIME_HZ:-25000000}UL"
      "-DSOC_FREERTOS_DEMO_TIME_SCALE=${SOC_FREERTOS_DEMO_TIME_SCALE:-1}U"
      "-DSOC_FREERTOS_SIM_COMPLETION=${SOC_FREERTOS_SIM_COMPLETION:-0}U"
    )
  fi

  objects=()
  for source_path in "${sources[@]}"; do
    relative="${source_path#${repo_root}/}"
    object_name="${relative//\//_}"
    object_path="${object_dir}/${object_name%.*}.o"
    include_flags=()
    for include_dir in "${include_dirs[@]}"; do
      include_flags+=("-I${include_dir}")
    done
    "${tool_prefix}gcc" "${common_flags[@]}" "${app_flags[@]}" -O2 -g3 \
      "${include_flags[@]}" \
      -c "${source_path}" -o "${object_path}"
    objects+=("${object_path}")
  done

  elf_path="${out_dir}/${artifact_name}.elf"
  map_path="${out_dir}/${artifact_name}.map"
  "${tool_prefix}gcc" "${common_flags[@]}" \
    -nostartfiles -nostdlib -no-pie \
    -Wl,--gc-sections \
    -Wl,--no-relax \
    -Wl,--orphan-handling=warn \
    -Wl,-Map,"${map_path}" \
    -T "${repo_root}/sw/common/linker.ld" \
    -o "${elf_path}" "${objects[@]}" -lgcc

  "${tool_prefix}readelf" -h -l -S -s "${elf_path}" > "${out_dir}/${artifact_name}.readelf"
  "${tool_prefix}objdump" -drwC "${elf_path}" > "${out_dir}/${artifact_name}.dis"
  "${tool_prefix}size" -A "${elf_path}" > "${out_dir}/${artifact_name}.size"

  python3 "${repo_root}/sim/regress/elf_to_mem.py" \
    "${elf_path}" \
    --imem "${out_dir}/${artifact_name}.imem.hex" \
    --dmem "${out_dir}/${artifact_name}.dmem.hex" \
    --split-map "${repo_root}/sim/generated/soc_map.json" \
    --dmem-uninitialized-fill 0xA5

  if ((install_images)); then
    cp "${out_dir}/${artifact_name}.imem.hex" "${repo_root}/testdata/firmware_${artifact_name}.imem.hex"
    cp "${out_dir}/${artifact_name}.dmem.hex" "${repo_root}/testdata/firmware_${artifact_name}.dmem.hex"
  fi

  echo "[FIRMWARE] ${artifact_name}: ${elf_path}"
done

echo "Built ${#requested_apps[@]} firmware app(s) under ${output_root}"
if ((install_images)); then
  echo "Installed selected program/data images under ${repo_root}/testdata"
fi
