# ZYNQ MINI REVB UART, FreeRTOS, and K2 Reset Evidence — 2026-08-23

## Scope

This directory preserves the physical-board observation supplied on
2026-08-23 for the Bo Chen Jing Xin ZYNQ MINI `20240221/REVB`. It closes the
external UART TX, production FreeRTOS UART/GPIO, and repeated PL K2 reset
observation gates. It does not identify the unreadable XC7Z010 speed grade.

## Setup

- External CH340-compatible 3.3 V USB-TTL adapter on Windows COM5.
- Board `uart_tx_o` W15 connected to adapter RXD, board `uart_rx_i` U15
  connected to adapter TXD, and a common ground; adapter VCC was not used.
- PuTTY configured for 115200 baud, 8 data bits, no parity, one stop bit, and
  no flow control.
- Exact bitstream filenames/hashes, elapsed wall time, and a counted number of
  K2 presses were not retained and are therefore not claimed here.

## Observation

- The bare-metal image repeatedly produced the exact `Hello, UART!` text after
  deliberate K2 resets.
- The production FreeRTOS image produced `FreeRTOS RV32IM`, continued emitting
  `heartbeat`, and visibly toggled PL D1. The user reports all requested board
  tests passed.
- Recurring non-heartbeat banners were explained by deliberate K2 presses, not
  spontaneous resets. A few malformed bytes coincide with manual reset
  activity, when reset can interrupt a UART character; clean messages remain
  directly countable in the retained transcript.
- The closed PuTTY transcript contains 74 exact `Hello, UART!` matches, 17
  exact `FreeRTOS RV32IM` matches, and 537 exact `heartbeat` matches.
- The PuTTY header starts at 21:12:54 and the closed file was last written at
  21:35:46 local time, an approximately 22-minute-52-second captured session.
  Deliberate resets divide that span, so no single uninterrupted-run duration
  is claimed.

The sustained heartbeat stream plus D1 activity demonstrates timer-driven
preemption and concurrent UART/GPIO tasks on the custom RV32IM core. The
production application also continuously exercises its queue producer and
receiver; the retained terminal evidence is observational rather than a
direct hardware probe of the internal queue counter. The separate ModelSim
soak remains the direct 1,000-receive/context-sentinel proof.

## Preserved artifacts

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `zynq_uart_test.log` | 7,330 | `620050E9D6515419BEEF0B2ED5F1B7336DA4A5F120BE62C998DBCE7700A3DC2B` |
| `putty_hello_resets.png` | 7,786 | `961955F61627B138A61B23CE1378F2D34A8D64AB533C2FE8005CB7009B244EDA` |
| `putty_hello_to_freertos.png` | 8,970 | `DA8D05D13984C4F2C6A19832A156A3A90A8878A05CC648A9FDD2F4E7DB4E6932` |
| `putty_freertos_heartbeats.png` | 9,614 | `C07524DACB4FDAAB30EEAF202049D8E3BAEB47F332AAC07FEA43F9F7F565D122` |

The original external transcript path was `D:\putty\zynq_uart_test.log`.
The repository copy has the same byte count and SHA-256.

## Result and remaining risk

The external 115200 8N1 board-to-host UART path, production FreeRTOS
heartbeat/D1 behavior, and deliberate K2 restart behavior are physically
observed and PASS. Vivado warning `REQP-1839` remains documented rather than
suppressed; today’s repeated-reset result reduces the immediate board risk but
does not make the asynchronous-reset structure ideal. The package speed grade
also remains unidentified, so routed builds continue to conservatively target
`xc7z010clg400-1`.
