---
status: inbox
created: 2026-09-25
tags: [ai, product, engineering-tools, energy-management]
related_phase: none
---

# Possible AI product directions

## Problem or opportunity

AI software may permit a faster product/revenue experiment than custom silicon
or propulsion hardware, while the project's RTL, verification, control, and
research discipline could provide a more defensible vertical specialization
than a general chatbot.

## Current ideas

1. **RTL and embedded evidence assistant**
   - route an engineering task to the minimum relevant context;
   - trace specification, requirement, RTL, test, and observed result;
   - summarize regressions and propose focused failure hypotheses;
   - detect stale documentation and unsupported implementation claims.
2. **Energy-management benchmark platform**
   - compare rule/PI, estimation, MPC, and optional small-ML approaches on the
     same plant, scenarios, constraints, execution-time, and energy metrics;
   - generate portable test vectors and bounded C reference code;
   - keep physical/model assumptions and reproducibility evidence visible.
3. **Paper audit and reproduction assistant**
   - record provenance, equations, units, assumptions, baselines, commands,
     actual outputs, and adopt/adapt/reject decisions;
   - serve engineering teams or laboratories rather than act as an unverified
     paper summarizer.
4. **Later on-device AI**
   - fault classification, anomaly detection, state/parameter estimation, or
     load prediction only after M0/W0 produce justified signals and datasets;
   - TinyML/NPU/custom acceleration only after CPU, accuracy, safety, movement,
     and power evidence passes the A0 gate.

## Unknowns and risks

- Which customer has a painful, repeatable workflow and willingness to pay?
- What data can be used legally and kept private?
- Can a narrow workflow show measurable time, quality, or cost improvement?
- How much human review is required for safety- or evidence-relevant output?
- Would the product live in a separate repository and license boundary?

## Possible relationship

- The current SoC can be a real evaluation case, not the only supported target.
- W0/M0 could later supply domain workloads and models.
- This note does not authorize an AI feature, product repository, model,
  accelerator, or change to the current roadmap.

## Smallest next check

If the idea is activated later, interview several embedded/FPGA engineers about
one workflow before building a product. Define a measurable manual baseline and
one narrow AI-assisted outcome.
