# License and Intellectual-Property Strategy

**Status:** Adopted repository policy on 2026-09-07

**Public rights-holder identifier:** `HeTPort`

**Commercial licensing contact:** `Hetport@outlook.com`

**Important:** this is practical repository governance, not legal advice.
Before fundraising, patent filing, tape-out, hardware sales, safety-critical
deployment, or the first commercial license, obtain advice for the relevant
jurisdictions.

## 1. Adopted public-repository policy

The original RTL, firmware, scripts, tests, configuration, and documentation
are covered by the root
[`HeTPort Noncommercial Source-Available License 1.0`](../LICENSE).

The license permits personal learning, noncommercial teaching, and
noncommercial academic research, including simulation, synthesis, modification,
and limited prototypes under its conditions. Commercial use requires a
separate written agreement. The repository must therefore be described as
**source-available**, not open source.

The public notice may use the pseudonym or project identity `HeTPort`; it does
not need to expose a legal name. A legal person or company must nevertheless
own and sign later contracts, patent filings, assignments, and enforcement
actions.

## 2. Why Apache-2.0 and CERN-OHL were not selected

Apache-2.0, CERN-OHL-P/W/S, MIT, MPL, and GPL are genuine open-source or
open-hardware choices. Their details differ, but they permit commercial use
when downstream users follow the applicable conditions. That conflicts with
the chosen rule that commercial users must first contact HeTPort.

The policy can later change for future versions. A version already distributed
under broader terms generally keeps those terms, so a permissive/open-hardware
release should never be made merely for visibility. Conversely, changing a
future release to Apache or CERN would require a deliberate review of
ownership, contributors, patents, and third-party inputs.

## 3. Scope boundaries

| Boundary | Repository policy | Rationale |
| --- | --- | --- |
| Original public RV32IM SoC, verification, firmware, and learning material | Root noncommercial source-available license | Public portfolio and learning value while reserving commercial negotiation |
| Commercial enhanced controller/SoC | Separate private or access-controlled repository and written commercial/proprietary terms | Keeps customer, support, patent, and field-of-use terms negotiable |
| Propulsion geometry, compressor maps, power-stage topology, control tuning, experiments, and manufacturing details | Private; all rights reserved until patent/trade-secret/publication decision | Public source visibility is not confidentiality |
| `third_party/FreeRTOS-Kernel/` | Upstream MIT License | It is third-party code and cannot be relicensed as HeTPort-only material |
| Future external contributions | No substantial acceptance before written contribution terms | Commercial relicensing requires clear ownership/permissions |

Detailed exceptions and dependencies are in
[`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

## 4. Enforcement and practical limits

Publishing source does not waive copyright. The license creates permission
only within stated conditions; uses outside the grant may require enforcement
through the rights holder. However:

- a public repository is not a trade secret;
- copyright protects expression, not every underlying architecture idea;
- manufacturing-control rights may depend on contract, patent, mask-work, or
  other local law in addition to copyright;
- a custom license has less precedent than Apache, MIT, or CERN-OHL; and
- enforcement requires evidence of ownership, provenance, the distributed
  version, the applicable terms, and the alleged use.

Therefore retain release tags/hashes, authorship history, design records,
third-party provenance, and copies of the license attached to each release.

## 5. Contribution policy

Issues, failing cases, and small factual corrections can be discussed
publicly. Code, RTL, firmware, tests, or substantial documentation should not
be accepted until a written contributor agreement or assignment provides the
rights needed for both the public noncommercial license and optional commercial
licensing. A Developer Certificate of Origin alone records provenance but does
not necessarily provide those relicensing rights.

See [`../CONTRIBUTING.md`](../CONTRIBUTING.md).

## 6. Adoption and release checklist

- [x] Add a root license and describe it as source-available/noncommercial.
- [x] Publish the commercial contact `Hetport@outlook.com`.
- [x] State that FreeRTOS retains its upstream MIT license.
- [x] Add third-party/provenance and contribution notices.
- [ ] Gradually add per-file copyright/SPDX-style scope markers after deciding
      on a stable custom identifier; do not use a fabricated SPDX identifier.
- [ ] Run a provenance scan before the first tagged licensed release.
- [ ] Obtain professional review before commercial reliance or fundraising.
- [ ] Keep product-specific propulsion, power, manufacturing, and calibrated
      experimental data out of this public repository until IP review.

## 7. If the policy changes later

Three coherent future choices are possible:

1. retain this noncommercial source-available policy and negotiate commercial
   licenses individually;
2. publish future original releases under Apache-2.0 for broad commercial
   adoption, optionally with paid support; or
3. use a CERN-OHL variant for hardware-source reciprocity while accepting that
   compliant commercial use no longer requires prior contact.

Do not combine these labels ambiguously. Record the effective version/tag,
file scope, exceptions, and contributor authority for every transition.

References are collected in [`REFERENCE_INDEX.md`](REFERENCE_INDEX.md).
