# PAPER-000 — Paper Audit and Reproduction Record

Copy this file to `doc/research/papers/<paper-id>-<short-name>.md` only when a
paper is selected for active review. Replace every placeholder. Expected or
proposed results must never be presented as executed evidence.

## 1. Identity and provenance

| Field | Value |
| --- | --- |
| Paper ID | `EMS-000`, `EST-000`, `CTRL-000`, `ACC-000`, `DS-000`, `MODEL-000`, `PROP-000`, or `SAFE-000` |
| Exact title | TODO |
| Authors | TODO |
| Venue / year / version | TODO |
| DOI / stable URL | TODO |
| Access date | TODO |
| Publisher / preprint relationship | TODO |
| Paper access and redistribution terms | TODO |
| Dataset/code/model URL and revision | TODO or none |
| Third-party license and notice status | TODO or not imported |
| Local source hash | TODO if a lawful local copy is used; do not commit it by default |
| Audit owner / date | TODO |
| Lifecycle state | Candidate / Screened / Audited / Reproduced / Adopted / Adapted / Rejected / Deferred / Superseded |

Backlinks:

- [Central research plan](../RESEARCH_PROGRAM_PLAN.md)
- [Research source registry](SOURCE_REGISTRY.md)
- [`TODO.md`](../../TODO.md)
- Related phase requirement/result: TODO

## 2. Decision question

**Claim under test:** TODO — one falsifiable sentence.

**Why it matters here:** TODO — identify the workload, model, safety rule,
software data type, or hardware candidate it could change.

**Decision alternatives:** TODO — adopt, adapt, reject, defer, plus the current
baseline that the paper must beat.

**Success and rejection criteria:** TODO — quantitative where possible.

## 3. Paper reconstruction

### 3.1 System boundary

- Inputs and outputs: TODO
- State and parameters: TODO
- Units, signs, coordinate frames, and sample time: TODO
- Operating envelope and excluded conditions: TODO
- Initial and boundary conditions: TODO
- Hardware/software platform: TODO

### 3.2 Method

- Equations/algorithm/pseudocode with exact paper section references: TODO
- Numeric representation, solver, tolerances, stopping criteria: TODO
- Data structures and access patterns: TODO
- Training, calibration, or parameter-identification process: TODO
- Randomness and seed policy: TODO

### 3.3 Claims and evidence in the paper

| Claim | Figure/table/section | Metric | Baseline | Reported result | Audit concern |
| --- | --- | --- | --- | --- | --- |
| TODO | TODO | TODO | TODO | TODO | TODO |

## 4. Assumption and credibility audit

Record `PASS`, `PARTIAL`, `FAIL`, or `UNKNOWN`, with reasons.

| Check | Verdict | Evidence / concern |
| --- | --- | --- |
| Dimensional/unit consistency | TODO | TODO |
| Energy, mass, momentum, charge, or information balance as applicable | TODO | TODO |
| Model and boundary-condition validity | TODO | TODO |
| Algorithm derivation and convergence/stability claim | TODO | TODO |
| Dataset provenance, leakage, and representativeness | TODO | TODO |
| Baseline fairness and hyperparameter/precision parity | TODO | TODO |
| Statistical method, uncertainty, and sample count | TODO | TODO |
| Hardware clock, process/FPGA, memory, precision, and tool disclosure | TODO | TODO |
| End-to-end data movement and software overhead included | TODO | TODO |
| Real-time/WCET, fault, and out-of-distribution behavior | TODO | TODO |
| Source/data availability and license reproducibility | TODO | TODO |

List contradictions, missing information, and claims that cannot be inferred
from the published evidence: TODO.

## 5. Reproduction plan

### 5.1 Scope

- Exact experiment to reproduce: TODO
- Deliberately excluded claims: TODO
- Faithful reproduction versus local adaptation: TODO
- Functional/control oracle: TODO
- Performance/accuracy tolerance: TODO
- Negative or falsification test: TODO

### 5.2 Environment and inputs

| Item | Exact value |
| --- | --- |
| OS / host | TODO |
| Tool/compiler/simulator versions | TODO |
| Target hardware and clock | TODO |
| Build flags/configuration | TODO |
| Input dataset/vector and hash | TODO |
| Seed(s) | TODO |
| Commands | TODO |
| Output directory / retention policy | TODO |

### 5.3 Expected outputs before execution

Write the acceptance oracle before the run, but label it `EXPECTED, NOT RUN`.
Never copy these values into the result section as proof.

- Expected functional outcome: TODO
- Expected metric range: TODO
- Expected failure signature: TODO

## 6. Actual reproduction results

**Execution status:** `NOT RUN` / `PARTIAL` / `REPRODUCED` / `NOT REPRODUCED`

| Run ID | Date | Command/config hash | Actual result | Oracle verdict | Retained evidence |
| --- | --- | --- | --- | --- | --- |
| TODO | TODO | TODO | TODO | TODO | TODO |

Record actual logs, plots, compact reports, hashes, failing seeds, and tool
versions. Link large external data without pretending it is retained in Git.

### Difference from paper

- Result delta and uncertainty: TODO
- Environment or implementation differences: TODO
- Sensitivity analysis: TODO
- Plausible explanation: TODO
- Remaining ambiguity: TODO

## 7. Local workload and hardware implications

| Question | Finding |
| --- | --- |
| Which W0/M0/C0 workload or requirement changes? | TODO |
| Which common data types/access patterns appear? | TODO |
| Which kernels dominate measured cycles/energy? | TODO or not measured |
| Are bounds and WCET/fault behavior suitable for control? | TODO |
| Can software/layout/compiler changes remove the hotspot? | TODO |
| What transfer, memory, MMIO, driver, and recovery cost would hardware add? | TODO |
| What numeric precision/tolerance is required? | TODO |
| What area, timing, and power risks follow? | TODO |

## 8. Decision and traceability

**Decision:** Adopt / Adapt / Reject / Defer / Supersede

**Reason:** TODO — tie the reason to actual evidence and limitations.

**Exactly adopted:** TODO — equation, parameter range, test vector, software
kernel, data type, requirement, or nothing. Do not say “use the paper” broadly.

**Not adopted:** TODO.

**Consequences and risks:** TODO.

**Required repository updates:**

- [ ] Update the source-registry state and, when the decision affects program direction, the central decision row.
- [ ] Add or update stable requirement IDs in the active phase package.
- [ ] Link reproduction evidence and actual result status.
- [ ] Update `TODO.md` only if the execution ledger changed.
- [ ] Update architecture/AR documents only if a design decision changed.
- [ ] Update `THIRD_PARTY_NOTICES.md` before importing third-party material.

## 9. Independent review

- Reviewer and date: TODO
- Commands/results independently checked: TODO
- Unit/baseline/license concerns resolved: TODO
- Final lifecycle state: TODO
