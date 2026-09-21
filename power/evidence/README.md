# Retained Power Evidence

This directory retains compact, reviewed evidence only. Large generated VCD,
SAIF, DCP, implementation, and simulator outputs remain under ignored
`build/power/` paths.

An accepted evidence package should contain:

- resolved workload/run identity and source artifact hashes;
- exact commands and tool versions;
- functional PASS summary and fixed-work count;
- routed clock, WNS/TNS, DRC, part, and utilization summary;
- SAIF duration, hierarchy, hash, mapping percentage, and unmatched rationale;
- vectorless/activity power category comparison;
- independent repeatability calculation;
- negative infrastructure-test result;
- limitations and the explicit PASS/PARTIAL/FAIL verdict.

Status: the six accepted P0 workload summaries are retained beside their
manifests under `power/workloads/*/results.md`; the consolidated verdict is in
`doc/plans/p0-power-baseline/results.md`. This directory is reserved for future
compact cross-workload evidence that does not belong in those reviewed records.
