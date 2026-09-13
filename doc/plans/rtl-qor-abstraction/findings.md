# 100 MHz RTL Cleanup Findings

- Physical `data_ram` reset port is already removed; adapter reset remains
  architectural because it resets its request/response FSM.
- `csr_mtvec`, `csr_mstatus`, `csr_mie`, and `csr_mip` at core level are unused
  observation outputs. `csr_mepc` is live for MRET forwarding.
- `retire_irq_taken` is unused at the core integration boundary.
- `wb_mret_event` is an assertion-only alias of `csr_retire_cmd.mret`.
- `retire_redirect` is live; its lint waiver is obsolete and overly broad.
- x3/x10/x11 register-file debug ports are used only for diagnostic displays,
  not pass/fail checks. Commit/trap interfaces are the architectural oracle.
- The board wrapper is now explicitly selectable between 25 and 100 MHz. The
  100 MHz profile changes the MMCM divide from 40 to 10 and scales UART/timer
  parameters while retaining the physical 50 MHz input constraint.
- The 100 MHz route fails with WNS -0.387 ns and TNS -3.637 ns across 30 setup
  endpoints. The worst data path is 10.183 ns and 15 levels: 2 DSP48E1,
  11 CARRY4, 1 LUT2, and 1 LUT6 between ID/EX operand and EX/WB result.
- The facade is a useful abstraction because a registered backend can replace
  the implementation without changing decode or execute contracts. The
  combinational backend is simpler in latency but does not meet 100 MHz.
