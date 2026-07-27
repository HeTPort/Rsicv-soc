#ifndef RSICV_SOC_RVTEST_CONFIG_H
#define RSICV_SOC_RVTEST_CONFIG_H

/*
 * ACT4 DUT capability declarations.
 *
 * The current core does not implement Physical Memory Protection.  Keep the
 * header deliberately minimal so ACT4 cannot select unsupported features from
 * adapter-side preprocessor defines.
 */
#define RVMODEL_PMP_GRAIN 0
#define RVMODEL_NUM_PMPS 0

#endif
