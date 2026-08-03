#ifndef RVMODEL_MACROS_H
#define RVMODEL_MACROS_H

/*
 * ACT4 DUT adaptation for the Rsicv-soc simulation environment.
 * The final word of the ACT4-only 256 KiB simulation memory, 0x0003_fffc, is
 * reserved for tohost. The testbench sees the store through commit_o, so this
 * macro is independent of LSU hierarchy.
 *
 * Interrupt injection macros are currently no-ops because the testbench and
 * the CPU have no external interrupt source. ACT4 tests that require interrupt
 * injection will fail and must be classified as Unsupported/not applicable in
 * the baseline pass. They must not be treated as CPU defects.
 */

#define RVMODEL_DATA_SECTION

#define RVMODEL_HALT_PASS  \
  li x1, 1                ;\
  li t0, 0x0003fffc       ;\
  sw x1, 0(t0)            ;\
1:                        ;\
  j 1b                    ;

#define RVMODEL_HALT_FAIL  \
  li x1, 2                ;\
  li t0, 0x0003fffc       ;\
  sw x1, 0(t0)            ;\
1:                        ;\
  j 1b                    ;

/* No console or interrupt source is implemented in the current core. */
#define RVMODEL_IO_INIT(_R1, _R2, _R3)
#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR)

/*
 * Mandatory ACT4 interrupt macros. Defined as no-ops because this baseline
 * target has no interrupt injection mechanism. Do not advertise
 * RVMODEL_MTIME_ADDRESS; the timer is not part of this adapter contract.
 */
#define RVMODEL_INTERRUPT_LATENCY      10
#define RVMODEL_TIMER_INT_SOON_DELAY   100

#define RVMODEL_SET_MEXT_INT(_R1, _R2)
#define RVMODEL_CLR_MEXT_INT(_R1, _R2)
#define RVMODEL_SET_MSW_INT(_R1, _R2)
#define RVMODEL_CLR_MSW_INT(_R1, _R2)
#define RVMODEL_SET_SEXT_INT(_R1, _R2)
#define RVMODEL_CLR_SEXT_INT(_R1, _R2)
#define RVMODEL_SET_SSW_INT(_R1, _R2)
#define RVMODEL_CLR_SSW_INT(_R1, _R2)

#endif
