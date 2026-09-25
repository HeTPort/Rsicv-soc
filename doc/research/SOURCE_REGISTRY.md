# Research Source Registry

**Document type:** bibliographic provenance and reading queue

**Status:** starter source set registered; no source below has passed local
audit or reproduction

**Last updated:** 2026-09-25

This file answers four questions: what the source is, where the original comes
from, why it is in the queue, and whether local review has started. It does not
prove a paper's claims and does not authorize copying its full text.

## 1. State and evidence rules

- `Candidate`: identity and canonical source are registered; detailed audit
  has not started.
- `Screening`: the original is being checked for relevance, equations, data,
  code, baselines, and reproducibility.
- `Audited`, `Reproduced`, `Adopted`, `Adapted`, `Rejected`, `Deferred`, and
  `Superseded` have the meanings defined in the
  [research plan](../RESEARCH_PROGRAM_PLAN.md).
- `Queued` below is reading order, not scientific acceptance.
- `Local original: none` means no PDF or other full-text copy was added to this
  repository. It says nothing about whether the researcher has a lawful
  personal copy elsewhere.

## 2. First reading queue

| Order | ID | Source role | State | Intended local output |
| ---: | --- | --- | --- | --- |
| 1 | `EMS-001` | Hybrid-electric aircraft architecture, conceptual design, EMS, and safety overview | Candidate / queued | Vocabulary and system-boundary notes for W0/M0 |
| 2 | `EMS-002` | Recent aircraft EMS taxonomy across rule, optimization, and learning methods | Candidate / queued | Algorithm-family comparison and research-gap list |
| 3 | `EMS-003` | Battery/supercapacitor EMS methods and comparison dimensions | Candidate / queued | Candidate baselines, constraints, metrics, and failure concerns |
| 4 | `EMS-004` | Battery/supercapacitor topology, converters, control, and applications | Candidate / queued | System topology and interface assumptions for the surrogate plant |
| 5 | `MODEL-001` | Low-order Thevenin battery-model implementation reference | Candidate / queued | M0 model boundary and parameter list; not yet an adopted implementation |
| 6 | `CTRL-001` | Aircraft TEEM MPC compared with a PI baseline | Candidate / queued | MPC/PI comparison questions and control metrics |
| 7 | `EMS-005` | Battery/supercapacitor rule, quadratic-MPC, and regularized-MPC comparison | Candidate / queued for reproducibility screening | Go/no-go decision for the first bounded paper reproduction |
| — | `PROP-001` | Classical compressor surge/rotating-stall system model | Deferred | Revisit only after the simple M0 motor/compressor boundary is stable |

The sequence is deliberate: learn the system and classification first, define
a small local model second, and only then spend time reconstructing an MPC
paper. `PROP-001` is relevant to the long-term propulsion model but is not the
first battery–bus–motor/compressor model.

## 3. Source records

### EMS-001 — hybrid-electric aircraft overview

| Field | Record |
| --- | --- |
| Exact citation | Ye Xie, Al Savvaris, Antonios Tsourdos, Dan Zhang, and Jason Gu, “Review of hybrid electric powered aircraft, its conceptual design and energy management methodologies,” *Chinese Journal of Aeronautics*, 34(4), 432–450, 2021 |
| DOI / publisher | [10.1016/j.cja.2020.07.017](https://doi.org/10.1016/j.cja.2020.07.017) / [ScienceDirect landing page](https://www.sciencedirect.com/science/article/pii/S1000936120303368) |
| Additional lawful-access lead | [Cranfield institutional copy](https://dspace.lib.cranfield.ac.uk/bitstream/1826/16465/1/Review_of_hybrid_electric_powered_aircraft-2020.pdf); repository metadata identifies CC BY-NC-ND 4.0, to be rechecked against the file before reuse |
| Access checked | 2026-09-25 |
| Intended use | Establish architecture, terminology, EMS categories, safety concerns, and unknowns; do not treat review conclusions as design proof |
| State / audit | Candidate / queued; detailed audit not created |
| Local original | None in Git; hash not applicable |

### EMS-002 — recent aircraft EMS taxonomy

| Field | Record |
| --- | --- |
| Exact citation | Jiecheng Fu, Fengying Zheng, Jingyang Zhang, Weidong Chen, and Xingjian Jin, “A review of energy optimization management strategy for hybrid-electric propulsion aircraft,” *Aerospace Science and Technology*, 171, 111644, 2026 |
| DOI / publisher | [10.1016/j.ast.2026.111644](https://doi.org/10.1016/j.ast.2026.111644) / [ScienceDirect landing page](https://www.sciencedirect.com/science/article/pii/S1270963826000258) |
| Access checked | 2026-09-25; publisher metadata found, full-text access and redistribution terms not yet established |
| Intended use | Update the rule/optimization/learning taxonomy and identify validation, integration, and implementation questions |
| State / audit | Candidate / queued; detailed audit not created |
| Local original | None in Git; hash not applicable |

### EMS-003 — battery/supercapacitor EMS systematic review

| Field | Record |
| --- | --- |
| Exact citation | Aree Wangsupphaphol, Sotdhipong Phichaisawat, Nik Rumzi Nik Idris, Awang Jusoh, Nik Din Muhamad, and Raweewan Lengkayan, “A Systematic Review of Energy Management Systems for Battery/Supercapacitor Electric Vehicle Applications,” *Sustainability*, 15(14), 11200, 2023 |
| DOI / publisher | [10.3390/su151411200](https://doi.org/10.3390/su151411200) / [MDPI article page](https://www.mdpi.com/2071-1050/15/14/11200) |
| Access checked | 2026-09-25; open publisher page identified; capture the article's exact license in the audit before copying or adapting content |
| Intended use | Compare EMS categories, objectives, constraints, converters, metrics, and claimed tradeoffs for a bounded battery/supercapacitor case |
| State / audit | Candidate / queued; detailed audit not created |
| Local original | None in Git; hash not applicable |

### EMS-004 — battery/supercapacitor system and topology survey

| Field | Record |
| --- | --- |
| Exact citation | Zheng Dong, Zhenbin Zhang, Zhen Li, Xuming Li, Jiawang Qin, and Ruiqi Wang, “A Survey of Battery–Supercapacitor Hybrid Energy Storage Systems: Concept, Topology, Control and Application,” *Symmetry*, 14(6), 1085, 2022 |
| DOI / publisher | [10.3390/sym14061085](https://doi.org/10.3390/sym14061085) / [MDPI article page](https://www.mdpi.com/2073-8994/14/6/1085) |
| Access checked | 2026-09-25; open publisher page identified; capture the article's exact license in the audit before copying or adapting content |
| Intended use | Separate storage topology, power-converter control, BMS, and supervisory EMS responsibilities in M0 |
| State / audit | Candidate / queued; detailed audit not created |
| Local original | None in Git; hash not applicable |

### MODEL-001 — PyBaMM Thevenin model documentation

| Field | Record |
| --- | --- |
| Source | PyBaMM project, “Thevenin Model,” official equivalent-circuit model documentation |
| Canonical project page | [Equivalent Circuit Models](https://docs.pybamm.org/en/latest/source/api/models/equivalent_circuit/index.html); [versioned v25.10.1 Thevenin page](https://docs.pybamm.org/en/v25.10.1/source/api/models/equivalent_circuit/thevenin.html) |
| Access checked | 2026-09-25; current documentation moves with releases, so M0 must pin an exact PyBaMM release/revision and its license before importing code or parameters |
| Intended use | Learn a low-order OCV–resistor–RC battery boundary and thermal coupling; define local equations and parameters independently before implementation |
| State / audit | Candidate / queued; documentation reference, not a reproduced paper |
| Local original | None in Git; hash not applicable |

### CTRL-001 — NASA TEEM MPC presentation

| Field | Record |
| --- | --- |
| Exact citation | Elyse D. Hill, “Turbine Electrified Energy Management with Model Predictive Control,” NASA Technical Reports Server document 20230012119, presentation for the 2023 EDGE Symposium, 2023 |
| Official source | [NASA NTRS 20230012119](https://ntrs.nasa.gov/citations/20230012119) |
| Access checked | 2026-09-25; NTRS labels distribution “Public” and copyright “Public Use Permitted” |
| Intended use | Study how an MPC and PI baseline are compared on a nonlinear turbofan model and which transient-operability metrics are used |
| State / audit | Candidate / queued; detailed audit not created |
| Local original | None in Git; hash not applicable |

### EMS-005 — regularized MPC reproduction candidate

| Field | Record |
| --- | --- |
| Exact citation | Théo Amy, He Kong, Daniel J. Auger, and Stefano Longo, “Regularized MPC for Power Management of Hybrid Energy Storage Systems with Applications in Electric Vehicles,” *IFAC-PapersOnLine*, 49(11), 265–270, 2016 |
| DOI / publisher | [10.1016/j.ifacol.2016.08.040](https://doi.org/10.1016/j.ifacol.2016.08.040) / [ScienceDirect landing page](https://www.sciencedirect.com/science/article/pii/S2405896316313611) |
| Access checked | 2026-09-25; publisher currently identifies complimentary access, but redistribution terms and code/data availability still require audit |
| Intended use | Determine whether the rule/QMPC/RMPC comparison is specified well enough for one bounded local reproduction against the project's own rule or PI baseline |
| State / audit | Candidate / queued for screening; selection for reading is not adoption |
| Local original | None in Git; hash not applicable |

### PROP-001 — classical compressor-system dynamics

| Field | Record |
| --- | --- |
| Exact citation | Edward M. Greitzer, “Surge and Rotating Stall in Axial Flow Compressors—Part I: Theoretical Compression System Model,” *Journal of Engineering for Power*, 98(2), 190–198, 1976 |
| DOI / publisher | [10.1115/1.3446138](https://doi.org/10.1115/1.3446138) / ASME Digital Collection through the DOI |
| Access checked | 2026-09-25; publisher access/rights apply and no reusable local copy is recorded |
| Intended use | Later compressor surge and rotating-stall model study after M0 establishes a simpler motor/compressor/flow interface and required fidelity |
| State / audit | Deferred; activation condition is a stable M0 boundary that needs compressor-dynamic fidelity |
| Local original | None in Git; hash not applicable |

## 4. Next update rule

When the first source is opened for close review, create its audit from
[`PAPER_AUDIT_TEMPLATE.md`](PAPER_AUDIT_TEMPLATE.md), replace “AI summary” with
section/page-level evidence from the original, and update only that source's
state. Do not create eight mostly empty audit files now.
