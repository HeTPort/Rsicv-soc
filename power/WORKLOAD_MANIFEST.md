# Workload Manifest Contract

Each workload owns a `workload.json`. The manifest is a structured handoff
between documentation, firmware build, ModelSim capture, Vivado analysis, and
result reporting. Human rationale stays in `design.md`; exact identities and
gates belong here.

## Required top-level fields

| Field | Meaning |
|---|---|
| `schema_version` | Manifest format version; currently `1`. |
| `name` | Stable lowercase workload identifier matching its directory. |
| `version` | Workload-contract version, independent of Git revision. |
| `state` | `design`, `implemented`, `verified`, `accepted`, or `superseded`. |
| `purpose` | One-sentence measurement question. |
| `design_document` | Local design Markdown filename. |
| `source` | Provenance kind plus source paths. |
| `target` | Part, clock, top, DUT instance, and memory profile. |
| `measurement` | Warmup, markers, fixed work, and repeatability contract. |
| `expected_blocks` | Blocks expected active, idle, or not applicable. |
| `oracle` | Functional PASS mechanism and failure behavior. |
| `kpis` | Stable KPI IDs, units, gates, and current evidence state. |

## Evidence values

Use `"NOT RUN"` for measurements that have not executed. Do not enter expected
power, checksum, mapping, timing, or performance values as observed evidence.

## Identity rule

The resolved run manifest must additionally record Git tree identity, compiler
and flags, image hashes, Vivado/ModelSim versions, routed-checkpoint hash,
environment assumptions, exact marker addresses/values, and commands. That
resolved manifest belongs under `build/power/<workload>/<run-id>/`; its compact
reviewed summary may later be retained under `power/evidence/`.
