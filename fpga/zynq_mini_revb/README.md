# ZYNQ MINI 20240221/REVB FPGA build

This directory targets the Bo Chen Jing Xin ZYNQ MINI board marked
`20240221/REVB`, with an XC7Z010 in the CLG400 package. The visible package
marking does not show a readable speed grade, so the flow uses the conservative
Vivado part `xc7z010clg400-1`. Set `ZYNQ_MINI_PART` only after positively
identifying a different speed grade.

The top includes a retained but otherwise unused PS7 hard block because Vivado
requires it for correct Zynq device configuration. It supplies no clock or
application service: the custom RISC-V SoC remains entirely in PL.

No physical board is needed to build the bitstreams. A connected board is
needed only to verify JTAG discovery, program the device, and observe the real
clock/reset, LEDs, and UART.

Physical status on 2026-08-15: onboard FT232HL JTAG works after installing the
bundled Digilent Adept runtime; `timer_gpio` and `timer_irq` pass on the exact
board. External-UART `hello`, repeated PL K2 reset, and speed-grade
identification remain open. The detailed recovery evidence is in the
[JTAG bring-up log](../../doc/ZYNQ_MINI_REVB_JTAG_BRINGUP_LOG.md).

## Interfaces

| Function | FPGA pin | Board location | Direction/polarity |
|---|---:|---|---|
| 50 MHz PL clock | K17 | X1 / `PL_CLK_50M` | input |
| Reset | M20 | PL K2 | input, active low |
| LED 0..3 | T12, U12, V12, W13 | PL D1..D4 | output, active high |
| UART RX | U15 | EXT IO U15 | adapter TX to board |
| UART TX | W15 | EXT IO W15 | board to adapter RX |

The onboard USB-UART is connected to Zynq PS MIO48/MIO49. It cannot carry the
custom PL UART. Use a separate **3.3 V TTL** USB-UART adapter:

1. adapter TX to EXT IO U15;
2. adapter RX to EXT IO W15;
3. adapter GND to EXT IO GND;
4. leave the adapter VCC pin disconnected.

Use 115200 baud, 8 data bits, no parity, one stop bit, and no flow control.

## Build firmware images

From WSL, build and install the Phase 5 images or the production FreeRTOS
image. The production FreeRTOS build keeps scheduling indefinitely; only its
separate `_sim` profile terminates through `tohost`:

```bash
cd /mnt/d/Rsicv-soc-worktrees/phase2-act4-cleanup
bash sw/build_firmware_wsl.sh --install hello timer_gpio timer_irq
bash sw/build_firmware_wsl.sh --install freertos_demo
```

## Build bitstreams with Vivado 2019.2

From PowerShell at the repository root:

```powershell
$vivado = 'D:\vivado\Vivado\2019.2\bin\vivado.bat'
& $vivado -mode batch -notrace `
  -source .\fpga\zynq_mini_revb\build.tcl -tclargs hello
& $vivado -mode batch -notrace `
  -source .\fpga\zynq_mini_revb\build.tcl -tclargs timer_gpio
& $vivado -mode batch -notrace `
  -source .\fpga\zynq_mini_revb\build.tcl -tclargs timer_irq
& $vivado -mode batch -notrace `
  -source .\fpga\zynq_mini_revb\build.tcl -tclargs freertos_demo
```

Each run reads RTL and XDC, synthesizes, checks that both firmware images
survive as nonzero BRAM initialization, places, routes, writes utilization,
timing/clock/power/DRC reports, rejects negative routed WNS or any Error/Critical
Warning DRC, and generates:

```text
build/zynq_mini_revb/<application>/zynq_mini_revb_<application>.bit
```

The Phase 5 hardware profiles keep the same firmware images but slow `mtime`
so the results are visible: `timer_gpio` changes LEDs about once per second,
while `timer_irq` generates one interrupt about once per second for ten
interrupts. `freertos_demo` uses the real 25 MHz MTIME rate configured in its
production image, giving a 1 kHz RTOS tick.

## Program and observe the board

These are the steps that require the board:

1. Power the board off and set BOOT to JTAG `00` (both switches toward the
   silk-screened ON/KEY side, according to the board legend).
2. Power the board only through its documented 5 V Type-C input. Connect the
   JTAG Type-C cable and the external 3.3 V UART wiring above. Do not connect
   the USB-UART adapter's VCC pin.
3. In Vivado, open Hardware Manager, select **Open Target > Auto Connect**, and
   confirm an XC7Z010 is detected.
4. Program one generated `.bit` file. If needed, press PL K2 once after
   programming.
5. For `hello`, confirm the expected UART banner at 115200 8N1. For
   `timer_gpio`, confirm the PL LEDs step through the firmware sequence. For
   `timer_irq`, confirm the ten timer-interrupt completion behavior. For
   `freertos_demo`, confirm `FreeRTOS RV32IM`, then a `heartbeat` line every
   second, while PL D1 toggles every 500 ms. Leave it running to exercise tick
   preemption, queue blocking/unblocking, and repeated context switches.

Observed on 2026-08-15:

- `timer_gpio`: PASS, `0001 -> 0010 -> 0100 -> 1000 -> 0101`, approximately
  one update per second;
- `timer_irq`: PASS, binary interrupt count `0001` through `1010`,
  approximately one update per second, with final D2/D4 on;
- `hello`: not yet physically observed because the required external 3.3 V
  USB-TTL adapter is not connected.

Programming is volatile: after power is removed, reload the bitstream. JTAG
operation is proven; QSPI/SD boot-image generation remains deferred until the
UART and repeated-reset baseline is complete.

## JTAG cable recovery

If Hardware Manager connects to `hw_server` but shows `localhost (0)`, the
server is alive but has enumerated zero hardware cables. On this machine,
Windows already saw the FT232HL as `VID_0403:PID_6014` / `Digilent USB Device`,
which ruled out a power-only Type-C cable and moved the investigation to the
Vivado cable runtime.

Close Vivado, open an elevated PowerShell, and install the support bundled with
the same Vivado release:

```powershell
Set-Location -LiteralPath `
  'D:\vivado\Vivado\2019.2\data\xicom\cable_drivers\nt64'
.\install_drivers_wrapper.bat
```

The successful log installed Xilinx PC USB support, Digilent Adept Runtime
2.18.2/USB support, and SmartLynq support. After restarting/re-enumerating the
device, Vivado could program the board. Do not rewrite the FTDI EEPROM as a
first repair: this unit already reports a Digilent identity. Commands,
evidence, source links, rejected paths, and the reusable layer-by-layer
decision tree are in the
[JTAG bring-up log](../../doc/ZYNQ_MINI_REVB_JTAG_BRINGUP_LOG.md).

## What still needs manual review

- Confirm the physical package's speed grade with a vendor record or readable
  device-identification source. The `-1` build is deliberately conservative.
- Confirm `Hello, UART!` through an external 3.3 V USB-TTL adapter on U15/W15.
- The 50 MHz clock, active-high LED mapping, BRAM boot, timer progression, and
  interrupt-driven execution now have physical evidence. If EXT IO UART or
  reset behavior differs from the schematic, stop and recheck continuity or
  vendor documentation before changing package pins.
- Vivado currently warns that asynchronously reset control registers feed data
  BRAM address/control logic (`REQP-1839`). Reset deassertion is synchronized,
  but repeated button-reset robustness is not yet physical evidence; reprogram
  or power-cycle if a reset test behaves inconsistently and investigate the
  internal synchronous-reset cleanup before a production design.
