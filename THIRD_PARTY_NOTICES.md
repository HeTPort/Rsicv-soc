# Third-Party Notices and External Dependencies

The root [`LICENSE`](LICENSE) applies only to original HeTPort material. It
does not replace the terms of third-party code, generated artifacts, tools,
standards, or reference implementations.

## Redistributed third-party source

### FreeRTOS Kernel V11.3.0

- Location: `third_party/FreeRTOS-Kernel/`
- Upstream: <https://github.com/FreeRTOS/FreeRTOS-Kernel>
- Pinned commit: `9b777ae5c5b8e9e456065a00294d1e5f5f9facf5`
- License: MIT; see
  [`third_party/FreeRTOS-Kernel/LICENSE.md`](third_party/FreeRTOS-Kernel/LICENSE.md)
- Provenance and imported subset:
  [`third_party/FreeRTOS-Kernel/UPSTREAM.md`](third_party/FreeRTOS-Kernel/UPSTREAM.md)

FreeRTOS remains usable commercially under its upstream MIT terms. The root
noncommercial license does not restrict or relicense the upstream FreeRTOS
files. Original platform integration outside that directory remains covered by
the root license unless a file says otherwise.

## External tools, standards, and reference projects

The repository contains integration/configuration for, or documentation links
to, projects such as RISC-V ACT4, Sail, the RISC-V ISA specifications,
ModelSim/Questa, Vivado, and CoralNPU. Unless a file expressly says that source
was imported, those projects are external dependencies or references and are
not redistributed or relicensed here.

Generated ACT4 test programs are created from an external ACT4 checkout and
are not part of the original HeTPort RTL license merely because the local
scripts can build or execute them. Preserve the upstream licenses and notices
for any generated or imported artifacts you choose to distribute.

No CoralNPU source has been copied into this repository. Its organization is a
design reference only; CoralNPU is separately licensed under Apache-2.0.

## Adding another dependency

Before committing third-party material, record its upstream URL, exact commit
or release, license, imported files, modifications, and generated outputs.
Keep its license text and notices intact and update this file.
