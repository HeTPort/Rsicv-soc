# Common Workload Contracts

This directory owns shared contracts used by every power workload. It must not
contain workload-specific algorithms.

Implemented common pieces are:

- the stable `tb_power/u_soc` simulation hierarchy;
- observation of committed START/END stores at each workload's ELF-resolved
  volatile RAM marker, without adding MMIO to the SoC;
- [`capture_window.do`](capture_window.do) for marker-bounded ModelSim SAIF
  and optional VCD capture;
- a separate committed `tohost` PASS/failure oracle and exact-work checks;
- per-run simulator log, run metadata, and artifact hashes.

The marker variable is workload-owned data RAM; the testbench is told its
resolved address, not an assumed fixed address. Capture starts after reset and
warmup at START, ends at END after fixed work, and never includes the final
`tohost` store. A missing/reordered marker or failed oracle rejects the run.
The routed design hierarchy is `top/u_soc`; SAIF import strips `tb_power`.
Generated waveforms remain under ignored `build/power/`.
