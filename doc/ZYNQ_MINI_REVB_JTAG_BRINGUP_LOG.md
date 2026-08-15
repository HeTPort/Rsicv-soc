# ZYNQ MINI REVB JTAG Bring-Up and Physical Verification Log

**Date:** 2026-08-15
**Board:** Bo Chen Jing Xin ZYNQ MINI `20240221/REVB`
**Device:** XC7Z010-CLG400, speed grade not yet independently identified
**Host tool:** Vivado 2019.2 on Windows
**Outcome:** JTAG access recovered; `timer_gpio` and `timer_irq` passed on hardware

## Final status

| Item | Result | Evidence |
|---|---|---|
| USB transport to onboard FT232HL | PASS | Windows enumerated `VID_0403:PID_6014` |
| Vivado JTAG cable discovery | PASS after driver/runtime repair | Board could be programmed from Hardware Manager |
| XC7Z010 configuration | PASS | Both LED-visible bitstreams were loaded and executed |
| `timer_gpio` | PASS | Expected one-second PL LED sequence observed |
| `timer_irq` | PASS | Expected ten interrupt-driven binary LED counts observed |
| `hello` UART | OPEN | Requires external 3.3 V USB-TTL on U15/W15 |
| Repeated PL K2 reset | OPEN | `REQP-1839` follow-up remains |
| Device speed grade | OPEN | Package marking still does not prove it |

The original OLED is not a result indicator for these bitstreams. It is driven
by PL signals used by the vendor image, while this repository's `top.sv` does
not instantiate or constrain the OLED interface. A blank OLED in JTAG mode or
after loading these bitstreams is therefore expected.

## Failure symptom

Vivado Hardware Manager connected to the local servers but displayed:

```text
localhost (0)
```

The Tcl console showed successful `hw_server`/`cs_server` connections. This is
an important boundary: the server process was alive, but it advertised zero
hardware targets. The failure was therefore before FPGA IDCODE scan,
bitstream selection, or application execution.

## Layered diagnostic model

The investigation treated the programming path as separate layers:

```text
Vivado IDE
  -> hw_server
  -> Digilent cable plugin/Adept runtime
  -> Windows FTDI driver
  -> onboard FT232HL USB-to-JTAG bridge
  -> TCK/TMS/TDI/TDO
  -> XC7Z010 TAP/IDCODE
  -> bitstream configuration
  -> RISC-V firmware behavior
```

This prevents an empty cable list from being misdiagnosed as a BOOT-switch,
XDC, or firmware problem. BOOT mode matters after the cable can be opened; it
cannot make an otherwise supported USB cable appear in `get_hw_targets`.

## Evidence collection

### 1. Confirm the Windows USB layer

The first PowerShell PnP query was not informative, so the investigation moved
to the native `pnputil` inventory:

```powershell
pnputil /enum-devices /connected /class USB
pnputil /enum-devices /instanceid `
  "USB\VID_0403&PID_6014\210251A08870" /properties /drivers
```

The connected device reported:

```text
Instance ID: USB\VID_0403&PID_6014\210251A08870
Device:      USB Serial Converter
Vendor:      FTDI
Status:      Started
Bus name:    Digilent USB Device
Driver:      generic FTDI ftdibus.inf, version 2.12.36.20
```

This established that board power, the Type-C data conductors, USB
enumeration, and the FT232HL itself were working. It did not yet prove that
Vivado had the runtime needed to claim the device as a JTAG cable.

### 2. Check authoritative FTDI/Vivado requirements

AMD UG908 documents FT232H/FT2232H/FT4232H support when the FTDI EEPROM has a
Vivado-compatible identity:

- <https://docs.amd.com/r/2022.1-English/ug908-vivado-programming-debugging/Programming-FTDI-Devices-for-Vivado-Hardware-Manager-Support>

AMD UG973 documents the Windows cable-driver installation wrapper under
`data/xicom/cable_drivers/nt64`:

- <https://docs.amd.com/r/2022.2-English/ug973-vivado-release-notes-install-license/Install-Cable-Drivers>

Local inspection found that Vivado 2019.2 did not contain the newer
`program_ftdi` utility, but did contain:

```text
D:\vivado\Vivado\2019.2\data\xicom\cable_drivers\nt64\
  install_drivers_wrapper.bat
  digilent\install_digilent.exe
```

No installed Digilent/Adept runtime was initially found. Because the FTDI
already reported `Digilent USB Device`, restoring the missing runtime was the
least destructive next step. Rewriting its EEPROM was explicitly rejected as
a first response because it was unnecessary evidence-wise and could destroy
the vendor configuration.

### 3. Install the bundled cable support

`cd /d` is CMD syntax, not PowerShell syntax. The first PowerShell attempt
failed with a `Set-Location` positional-parameter error. The corrected commands
were:

```powershell
Set-Location -LiteralPath `
  'D:\vivado\Vivado\2019.2\data\xicom\cable_drivers\nt64'
.\install_drivers_wrapper.bat
```

The installation log was then read rather than treating the wrapper's single
console line as proof. It recorded:

```text
xpcwinusb.inf was successfully installed
Digilent Adept Runtime 2.18.2
Installation completed successfully
SmartLynq installed successfully
```

The runtime appeared under:

```text
C:\Program Files (x86)\Digilent\Runtime
```

After closing stale Vivado/hardware-server processes and re-enumerating the
USB device, Hardware Manager could access the board and program it.

## Physical application evidence

### `timer_gpio`

The programmed image produced the expected approximately one-second sequence
on PL D1-D4:

```text
0001 -> 0010 -> 0100 -> 1000 -> 0101
```

It then remained at `0101`, matching the firmware's final `0xA5` write as seen
through the four exported low GPIO bits.

### `timer_irq`

The programmed image counted one machine-timer interrupt per approximately one
second on PL D1-D4:

```text
0001, 0010, 0011, 0100, 0101,
0110, 0111, 1000, 1001, 1010
```

It completed at decimal ten (`1010`, D2 and D4 on). This is physical evidence
for BRAM boot, the 25 MHz PL clock, timer progression, interrupt entry, WFI
wake-up, `mret`, GPIO MMIO, and the mapped LED pins. It does not by itself
close the UART or repeated-reset checks.

## Reusable decision tree

1. **`hw_server` does not connect:** repair the local server/process/port.
2. **Server connects but `get_hw_targets` is empty / `localhost (0)`:** inspect
   USB enumeration, cable runtime, driver binding, and process ownership.
3. **A Digilent target exists but XC7Z010 is absent:** then inspect board power,
   JTAG wiring, target frequency, and the TAP chain.
4. **XC7Z010 is visible but programming fails:** inspect part selection,
   configuration status, bitstream compatibility, and detailed program log.
5. **Programming succeeds but behavior is wrong:** only then debug BOOT/reset,
   clock, XDC polarity, BRAM INIT, firmware, UART wiring, and LEDs.

Useful read-only commands:

```tcl
get_hw_targets
get_hw_devices
```

```powershell
pnputil /enum-devices /connected /class USB
```

## Root-cause confidence and lessons

The practical root cause was missing/inactive Digilent cable support in the
current Windows/Vivado environment. A Windows update may have influenced FTDI
driver ranking, but the evidence does not prove that as the sole cause. The
device's first-install record was dated the day of bring-up, and the Digilent
runtime was absent before the wrapper ran.

The reusable lessons are:

- locate the failing layer before changing FPGA RTL, BOOT mode, or EEPROM;
- distinguish a USB device visible to Windows from a JTAG cable claimable by
  Vivado;
- inspect installation logs, not only command exit appearance;
- prefer reversible driver/runtime repair over EEPROM mutation;
- keep physical evidence granular so two LED applications do not accidentally
  mark the still-unobserved UART/reset checks complete.
