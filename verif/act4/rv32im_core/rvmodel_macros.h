#ifndef RVMODEL_MACROS_H
#define RVMODEL_MACROS_H

/*
 * ACT4 DUT adaptation for the Rsicv-soc simulation environment.
 * The final valid RAM word, 0x0000_3ffc, is reserved for tohost. The
 * testbench sees the store through commit_o, so this macro is independent of
 * LSU hierarchy.
 */

#define RVMODEL_DATA_SECTION

#define RVMODEL_HALT_PASS  \
  li x1, 1                ;\
  li t0, 0x00003ffc       ;\
  sw x1, 0(t0)            ;\
1:                        ;\
  j 1b                    ;

#define RVMODEL_HALT_FAIL  \
  li x1, 2                ;\
  li t0, 0x00003ffc       ;\
  sw x1, 0(t0)            ;\
1:                        ;\
  j 1b                    ;

/* No console or interrupt source is implemented in the current core. */
#define RVMODEL_IO_INIT(_R1, _R2, _R3)
#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR)

#endif
