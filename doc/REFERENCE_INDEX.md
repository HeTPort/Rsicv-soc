# Engineering Reference Index

**Last reviewed:** 2026-09-07

Use references for principles, interfaces, tooling, and test patterns. A linked
project is not automatically compatible with this SoC's CoreBus, memory map,
tool versions, FPGA, or license. Record the exact upstream version and license
before copying any source.

## Classification

- **Direct:** a standard/tool/workflow can be used with limited adaptation.
- **Adapt:** reuse the architecture or verification pattern, not source code
  wholesale.
- **Study:** a useful system-level reference that is not a current dependency.

## Verification and CPU architecture

| Reference | Class | What to reuse |
| --- | --- | --- |
| [Accellera UVM](https://www.accellera.org/downloads/standards/uvm) | Direct | Standard library/version semantics supported by the simulator |
| [cocotb simulator support](https://docs.cocotb.org/en/stable/simulator_support.html) | Study/direct later | Legal Python-driven layer for ModelSim/Questa or Verilator; not required for P0 activity capture |
| [Verilator language support](https://verilator.org/guide/latest/languages.html) | Study/direct later | Fast open-source RTL simulation; prove project/UVM limitations before migration |
| [CORE-V-VERIF](https://github.com/openhwgroup/core-v-verif) | Adapt | Retirement/ISS comparison and reusable environment layering |
| [OpenTitan DV methodology](https://github.com/lowRISC/opentitan/blob/master/doc/contributing/dv/methodology/README.md) | Adapt | DV plan, test/coverage traceability, regression discipline |
| [riscv-dv](https://github.com/chipsalliance/riscv-dv) | Direct after U1 | Custom RV32IM target, seeds, generated instruction programs |
| [RISC-V privileged architecture](https://docs.riscv.org/reference/isa/priv/machine.html) | Direct | Machine CSR, traps, counters, WFI and architectural semantics |
| [RISC-V Vector extension](https://docs.riscv.org/reference/isa/unpriv/v-st-ext) | Study | RVV semantics only if A1 entry gates pass |

## Low power and counters

| Reference | Class | What to reuse |
| --- | --- | --- |
| [Vivado vector/SAIF power analysis](https://docs.amd.com/r/en-US/ug907-vivado-power-analysis-optimization/Vector-SAIF-Based-Power-Analysis) | Direct | Activity-based `report_power` workflow and assumptions |
| [Vivado supported power inputs](https://docs.amd.com/r/2022.2-English/ug907-vivado-power-analysis-optimization/Supported-Inputs) | Direct | Activity-input priority and vectorless fallback semantics |
| [Vivado power optimization guidance](https://docs.amd.com/r/en-US/ug907-vivado-power-analysis-optimization/Guidelines-to-Maximize-Power-Saving-with-Power-Optimization) | Direct | FPGA clock-enable/resource optimization workflow |
| [Ibex integration](https://github.com/lowRISC/ibex/blob/master/doc/02_user/integration.rst) | Adapt | Truthful `core_sleep_o` after WFI and outstanding-access checks |
| [OpenTitan power manager](https://opentitan.org/book/hw/ip/pwrmgr/index.html) | Adapt | Request/ack sequencing, wake/reset cause and always-on boundary |
| [OpenTitan pwrmgr testplan](https://opentitan.org/book/hw/ip/pwrmgr/data/pwrmgr_testplan.html) | Adapt | Entry/wake race, handshake and low-power verification cases |
| [CV32E40P performance counters](https://docs.openhwgroup.org/projects/cv32e40p-user-manual/en/cv32e40p_v1.3.0/perf_counters.html) | Adapt | Small-core event set and synthesis-parameterized counters |
| [IEEE 1801 / UPF](https://standards.ieee.org/ieee/1801/11890/) | Study | Later ASIC power-intent domains, isolation and retention |

## Control, protection, registers, and data movement

| Reference | Class | What to reuse |
| --- | --- | --- |
| [TI C2000 ePWM API](https://software-dl.ti.com/C2000/docs/f29h85x-sdk/latest/docs/html/group__epwm__api.html) | Adapt | Shadow update, complementary/dead-band, trigger and trip-zone semantics |
| [PULP advanced timer](https://github.com/pulp-platform/apb_adv_timer) | Adapt | Timer/PWM channel decomposition and waveform features |
| [PULP ControlPULP](https://github.com/pulp-platform/control-pulp) | Study | Control/power-management SoC partition and software relationship |
| [OpenTitan AON timer](https://opentitan.org/book/hw/ip/aon_timer/index.html) | Adapt | Bark/bite watchdog and always-on escalation model |
| [OpenTitan SPI host](https://opentitan.org/book/hw/ip/spi_host/index.html) | Adapt | Command/FIFO/event/error design; actual ADC timing remains device-specific |
| [PULP iDMA](https://github.com/pulp-platform/iDMA) | Adapt | Frontend/midend/backend DMA decomposition |
| [OpenTitan DMA](https://opentitan.org/book/hw/ip/dma/index.html) | Study | Descriptor, error and system-integration concerns |
| [Accellera SystemRDL](https://www.accellera.org/downloads/standards/systemrdl) | Direct pilot | Machine-readable register semantics |
| [PeakRDL](https://peakrdl.readthedocs.io/en/latest/index.html) | Direct pilot | Generate/register model ecosystem from SystemRDL |
| [PULP register interface](https://github.com/pulp-platform/register_interface) | Adapt | Generated register and bus-adapter architecture |

## Modelling, SIL, HIL, and propulsion studies

| Reference | Class | What to reuse |
| --- | --- | --- |
| [PX4 Autopilot](https://github.com/PX4/PX4-Autopilot) | Adapt | Modular controller and reproducible SITL/HITL workflow |
| [PX4 simulation docs](https://github.com/PX4/PX4-Autopilot/blob/main/docs/en/simulation/index.md) | Adapt | Distinguish SITL, HITL, SIH and richer simulation |
| [FMI standard](https://fmi-standard.org/docs/main/) | Direct later | Model exchange/co-simulation interface, not model validity |
| [OpenModelica](https://github.com/OpenModelica/OpenModelica) | Direct later | Equation-based multi-domain modelling |
| [OMSimulator](https://github.com/OpenModelica/OMSimulator) | Direct later | FMI-based co-simulation orchestration |
| [Verilator connecting guide](https://verilator.org/guide/latest/connecting.html) | Direct | Host/RTL integration patterns where useful |
| [SU2](https://github.com/su2code/SU2) | Study | CFD only after low-order model/BC sensitivity is understood |
| [Cantera](https://github.com/Cantera/cantera) | Study | Reacting/plasma chemistry only when required and parameterized |
| [NASA Aviary](https://github.com/OpenMDAO/Aviary) | Study | Later mission-level multidisciplinary trade studies |

## Accelerators, vector/NPU, and GPU

| Reference | Class | What to reuse |
| --- | --- | --- |
| [Chipyard MMIO versus RoCC](https://chipyard.readthedocs.io/en/latest/Customization/RoCC-or-MMIO.html) | Adapt | Coupling tradeoff; MMIO is the first path here |
| [Gemmini](https://github.com/ucb-bar/gemmini) | Study | Accelerator + scratchpad/DMA/software/verification full stack |
| [VTA](https://github.com/apache/tvm-vta) | Study | Simulator/driver/runtime/compiler integration and tiny-first bring-up |
| [Ara](https://github.com/pulp-platform/ara) | Study | RVV coprocessor integration; not a CoreBus drop-in |
| [CoralNPU](https://github.com/google-coral/coralnpu) | Study | Programmable scalar/vector/matrix subsystem scope |
| [CoralNPU RVV common RTL](https://github.com/google-coral/coralnpu/tree/main/hdl/verilog/rvv/common) | Study | Contract-driven register/FIFO/handshake/arithmetic organization; do not bulk-copy |
| [NVDLA hardware](https://github.com/nvdla/hw) and [software](https://github.com/nvdla/sw) | Study | Full RTL/bus/memory/driver/toolchain requirements |
| [Vortex GPGPU](https://github.com/vortexgpgpu/vortex) | Study | Complete RISC-V GPGPU simulator/RTL/FPGA/driver/OpenCL stack |

## Licensing, release, and later assurance

| Reference | Use |
| --- | --- |
| [GitHub licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository) | Consequence of no license and repository setup |
| [Open Source Definition](https://opensource.org/osd) | Explains why a commercial-use restriction is source-available, not open source |
| [Repository root license](../LICENSE) | Adopted custom noncommercial source-available terms; professional review still required before commercial reliance |
| [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.html) | Permissive software/RTL option with express patent terms |
| [CERN Open Hardware Licence v2](https://cern-ohl.web.cern.ch/) | Hardware-specific permissive/weak/strong reciprocal options |
| [GNU GPLv3 guide](https://www.gnu.org/licenses/quick-guide-gplv3.html) | Strong reciprocal software option |
| [Mozilla Public License 2.0](https://www.mozilla.org/en-US/MPL/2.0/) | File-level weak reciprocal software option |
| [Creative Commons BY 4.0](https://creativecommons.org/licenses/by/4.0/) | Attribution license for original prose/figures/media |
| [GitHub default branch](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-branches-in-your-repository/changing-the-default-branch) | Later reviewed integration/default-branch operation |
| [GitHub releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) | Tagged release and release-note workflow |
| [FAA AC 20-115D](https://www.faa.gov/regulations_policies/advisory_circulars/index.cfm/go/document.information/documentID/1041323) | Later airborne-software assurance context, not prototype certification |
| [FAA airborne software overview](https://www.faa.gov/aircraft/air_cert/design_approvals/air_software/software_regs) | Later assurance/regulatory orientation |

## Reuse checklist

Before adding a referenced component:

1. record URL, commit/release, license, files imported, and modifications;
2. confirm bus, clock/reset, tool, ISA, memory, and software compatibility;
3. define which requirement it satisfies and the local verification oracle;
4. preserve notices and source obligations;
5. test it as third-party input—repository popularity is not evidence that the
   integration is correct or safe.
