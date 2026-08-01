# SoC Memory-Map Configuration

[`soc_map.json`](soc_map.json) is the authoritative machine-readable source for
the proposed first FreeRTOS SoC map. It currently describes the
`freertos_64k_proposal`; `status: proposed` means the values are available for
review and utilization experiments but are not yet the implemented RTL ABI.

## Generate and check

From the repository root:

```powershell
python tools/gen_soc_map.py
python tools/gen_soc_map.py --check
python -m unittest tools/test_gen_soc_map.py
```

Generation uses only the Python standard library. Generated files are committed
so Vivado, firmware, and verification flows do not need Python while consuming
the map. Never edit a generated file directly; update `soc_map.json`, regenerate,
review the complete diff, and run `--check`.

## Ownership and relationships

| File | Function | Current consumer/status |
|---|---|---|
| `config/soc_map.json` | Sole editable definition and proposal status | Input to the generator |
| `tools/gen_soc_map.py` | Schema/semantic validation and deterministic rendering | Developer and CI command |
| `src/generated/soc_mem_map_pkg.sv` | RTL bases, bounds, byte sizes, word depths, timer registers, and default-target policy | Future decoder/SoC integration; parsed by the utilization synthesis |
| `firmware/include/soc_memory_map.h` | C-visible addresses and sizes | Future startup, drivers, and FreeRTOS port |
| `firmware/linker/soc_memory.ldh` | GNU linker `MEMORY` regions and reserved `tohost` symbol | Include fragment for the future firmware linker script |
| `sim/generated/soc_map.json` | Normalized numeric data for Python/PowerShell/test consumers | Future address-aware regression integration |
| `sim/generated/soc_map.tcl` | Vivado-safe scalar values | Used by `check_riscv_soc_configured_ram.tcl` |
| `sim/generated/soc_ram_utilization_profiles.tcl` | Named candidate bank capacities and derived word depths | Used by the paired 16 KiB/64 KiB synthesis comparison |
| `verif/act4/generated_memory_map.yaml` | Proposed map fragment | Future ACT4/UDB integration; not a complete UDB file |

The generator rejects overlapping regions, missing RAM regions, invalid widths,
non-power-of-two or misaligned windows, duplicate registers, timer registers
outside their target, an invalid `tohost`, and a default target that could hide
an error or perform a write.

`tohost` is expressed as `placement: last_word`, not as a duplicated numeric
offset. Changing data-RAM capacity therefore regenerates the completion address
automatically.

## Boundary between proposal and implementation

Current directed tests still use the implemented legacy map and their existing
`tohost` values. The generated proposal must not replace those values until
AR-009 is accepted and the decoder, base subtraction, instruction error path,
linker, images, and tests change together.

The generated capacity profiles drive a paired physical-resource experiment:

```powershell
Set-Location D:\Rsicv-soc\sim\synth
$env:SOC_MAP_PART = "xc7z010clg400-1" # replace with the exact board part
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' `
  -mode batch -source .\compare_riscv_soc_ram_utilization.tcl `
  -tclargs ram_16k
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' `
  -mode batch -source .\compare_riscv_soc_ram_utilization.tcl `
  -tclargs ram_64k
```

Each invocation writes independent metadata, flat/hierarchical utilization
reports, and a checkpoint under `build/vivado_ram_16k` or
`build/vivado_ram_64k`. The preserved comparison and reports are in
[`doc/AR015_RAM_CAPACITY_UTILIZATION_COMPARISON.md`](../doc/AR015_RAM_CAPACITY_UTILIZATION_COMPARISON.md).
This out-of-context synthesis measures inferred resources only; it does not
prove address-map correctness, timing closure, or board integration.

The resulting profile DCPs can be compared with identical 25/50 MHz internal
clock constraints:

```powershell
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' `
  -mode batch -source .\report_riscv_soc_ram_timing.tcl `
  -tclargs ram_16k
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' `
  -mode batch -source .\report_riscv_soc_ram_timing.tcl `
  -tclargs ram_64k
```

This is post-synthesis static timing for internal register-to-register paths,
not SDF timing simulation or post-route timing closure. AR-015 records the
preserved timing reports and the current failing combinational MULDIV path.
