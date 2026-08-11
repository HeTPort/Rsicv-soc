# SoC Memory-Map Configuration

[`soc_map.json`](soc_map.json) is the authoritative machine-readable source for
the accepted first FreeRTOS SoC map. It describes
`freertos_split_64k_v1`; `status: accepted` freezes the hardware/software ABI.
Implementation status is tracked separately because a map definition alone
does not create decoder or peripheral behavior.

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
| `config/soc_map.json` | Sole editable definition and lifecycle status | Input to the generator |
| `tools/gen_soc_map.py` | Schema/semantic validation and deterministic rendering | Developer and CI command |
| `src/generated/soc_mem_map_pkg.sv` | RTL bases, bounds, byte sizes, word depths, peripheral registers, and default-target policy | Consumed by the implemented SoC decoder/targets |
| `firmware/include/soc_memory_map.h` | C-visible addresses, sizes, and registers including `SOC_GPIO_OUT_ADDR` | Generated firmware contract; reusable driver stack pending |
| `firmware/linker/soc_memory.ldh` | GNU linker `MEMORY` regions and reserved `tohost` symbol | Accepted linker fragment; complete firmware linker pending |
| `sim/generated/soc_map.json` | Normalized numeric data for Python/PowerShell/test consumers | Generated simulation contract |
| `sim/generated/soc_map.tcl` | Vivado-safe scalar values | Used by `check_riscv_soc_configured_ram.tcl` |
| `sim/generated/soc_ram_utilization_profiles.tcl` | Named candidate bank capacities and derived word depths | Used by the paired 16 KiB/64 KiB synthesis comparison |
| `verif/act4/generated_memory_map.yaml` | Accepted map fragment | Future ACT4/UDB integration; not a complete UDB file |

The generator rejects overlapping regions, missing RAM regions, invalid widths,
non-power-of-two or misaligned windows, duplicate registers, timer registers
outside their target, an invalid `tohost`, and a default target that could hide
an error or perform a write.

`tohost` is expressed as `placement: last_word`, not as a duplicated numeric
offset. Changing data-RAM capacity therefore regenerates the completion address
automatically.

## Boundary between acceptance and implementation

The implemented decoder now consumes the accepted timer, UART, GPIO, data-RAM,
default-target, and `tohost` definitions. `gpio_out` at region-local `0x00`
generates `SOC_GPIO_OUT_ADDR=0x10001000` for SystemVerilog and C plus the
corresponding normalized simulation definition. The register's R/W behavior,
strobes, response timing, and side effects remain the responsibility of
`core_bus_gpio.sv`; `permissions: "rw"` is a region-level contract, not RTL.

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
