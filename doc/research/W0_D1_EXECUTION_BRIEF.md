# W0-D1 Execution Brief — First Surrogate Boundary

**Status:** Planned / `NOT RUN`

**Decision:** determine whether a bounded battery–DC-bus–motor/compressor
surrogate can support deterministic rule-based control in a high-level model
and bounded C without inventing the unknown propulsion system.

**Linked claims:** `RES-H1` enabling evidence; `PROD-H1` remains unvalidated.
This brief does not test accelerator benefit (`RES-H2`) or propulsion
feasibility (`PROP-H1`).

## 1. What the researcher does

Complete these activities in order:

1. Extract only system-boundary facts and open questions from the first source
   set; create a paper audit when close reading actually starts.
2. Choose the smallest energy-source, bus, load, control, and safety boundary
   that still makes power allocation meaningful.
3. Write signal, state, parameter, timing, fault, and safe-state tables. Every
   number is marked `sourced`, `assumed range`, `measured`, or `unknown`.
4. Specify one mandatory rule baseline and a PI extension only if the selected
   model exposes a meaningful controlled state.
5. Specify deterministic scenarios and correctness/control oracles without
   implementing them yet.
6. Review anticipated information classification using
   [`INFORMATION_CLASSIFICATION_AND_HANDLING.md`](../INFORMATION_CLASSIFICATION_AND_HANDLING.md).
7. issue one `GO`, `PIVOT`, `DEFER`, or `NO-GO` decision with reasons.

## 2. Bounded source review

Use exact identities and lifecycle states from the
[source registry](SOURCE_REGISTRY.md). Reading a source is not adoption.

### Pass A — required boundary sources

| Source | Questions to answer | Do not take from it |
| --- | --- | --- |
| `EMS-001` | Which architecture blocks and energy paths recur? Which safety, mission, and aircraft-specific constraints prevent direct EV assumptions? | Claimed architecture benefits as proof for this project; final aircraft sizing |
| `EMS-004` | Which battery/supercapacitor topologies require zero, one, or two controlled converters? Where do BMS, converter control, EMS, and protection boundaries lie? | A topology merely because the survey calls it advanced; component ratings without context |
| `MODEL-001` | What states, inputs, outputs, parameters, sign conventions, and validity limits are required by a one-RC Thevenin battery boundary? | PyBaMM code or parameter sets before revision/license/provenance review; electrochemical fidelity not required by W0 |

### Pass B — required baseline and metric source

| Source | Questions to answer | Gate |
| --- | --- | --- |
| `EMS-003` | Which rule/frequency-split/PI/optimization baselines are compared, under what objectives and constraints, and with which battery-stress, bus, energy, and computation metrics? | Select only a baseline expressible with bounded state, fixed memory, and deterministic scenarios |

### Pass C — later comparison/reproduction screening

| Source | Questions to answer | Why it is not first |
| --- | --- | --- |
| `CTRL-002` | How are PI and MPC given comparable plant information, constraints, operating points, and transient metrics? Which aircraft-specific metrics cannot transfer to the surrogate? | It depends on an already defined plant and baseline |
| `EMS-005` | Are equations, parameters, drive-cycle inputs, tuning, code/data, and baseline definitions sufficient for a fair local rule/QMPC/RMPC comparison? | It is the candidate reproduction, not the source of the local problem definition |

Use `EMS-002` later to check taxonomy freshness. Keep `PROP-001` deferred until
the simple load boundary proves that compressor pressure/flow dynamics are
necessary; W0-D1 must not reproduce Greitzer surge dynamics.

## 3. Candidate system boundary to evaluate

This is a candidate to accept, narrow, or reject—not an adopted architecture:

```text
battery one-RC model ---- controlled/limited power path ---+
                                                        DC bus --- aggregate inverter/motor/compressor load
optional supercapacitor -- controlled/limited power path ---+
                              | protection, safe-state, and load-curtailment supervisor
```

| Element | Minimum candidate representation | Why it exists now | Explicitly deferred |
| --- | --- | --- | --- |
| Battery | OCV, series resistance, one RC polarization state, SOC and current/voltage limits | Slow energy source and constrained state | cell electrochemistry, ageing identification, detailed thermal field |
| Auxiliary source | Optional supercapacitor as capacitance plus ESR, or a generic bounded auxiliary power port | Makes power split observable; may be disabled to test whether load curtailment alone is enough | detailed converter switching and device layout |
| DC bus | capacitor/energy state, voltage limits, aggregate losses | exposes power imbalance and a PI-controlled quantity | EMI and switching ripple |
| Power paths | command, saturation, efficiency/loss assumption, optional first-order lag | separates EMS from inner converter control | PWM and transistor models |
| Load | demanded electrical/mechanical power with optional first-order speed/torque response | deterministic motor/compressor surrogate | blade geometry, ionization, pressure-field CFD, surge/stall model |
| Supervisor | mode, limits, validity/fault flags, safe fallback and load curtailment | defines bounded safety behavior | certification claim or flight controller |

Candidate relationships to audit, with a declared sign convention, include:

- battery terminal voltage from OCV, ohmic drop, and one RC polarization state;
- SOC derivative from battery current and usable capacity;
- bus-energy balance using `d(0.5*C_dc*V_dc^2)/dt =
  P_batt + P_aux - P_load - P_loss`;
- auxiliary energy/voltage evolution when the optional port is enabled;
- aggregate load lag only if an algebraic demanded-power sink cannot exercise
  the controller timing and constraints.

No numeric value becomes a requirement merely because it appears in a paper.

## 4. Tables to produce

### Signal and state table

At minimum review these candidates:

- inputs: demanded load power or torque/speed pair, measured bus voltage,
  battery current/voltage/SOC/temperature estimates, auxiliary voltage/energy,
  availability and validity/fault flags;
- internal states: battery RC polarization, SOC, DC-bus energy/voltage,
  optional auxiliary energy, controller integrator, and supervisor mode;
- commands: battery power/current reference, auxiliary power/current reference,
  motor/load power or torque limit, mode, and safe-state request;
- parameters: capacitance/resistance/efficiency/current/voltage/energy limits,
  sample period, deadline, rate limits, and uncertainty bounds.

For every row record direction, unit, sign convention, numeric representation,
range, sample/update period, source, and `sourced/assumed/measured/unknown`.

### Timing table

Separate plant integration step, sensor update, supervisory control period,
actuator update, task deadline, and fault-response deadline. Ranges are allowed;
unsupported point values are not.

### Safety table

For loss/invalidity of each required signal, state whether the response is hold,
clamp, substitute, derate, isolate the auxiliary path, or shed the load. Define
the safe state as bounded commands and state transitions, not simply “shutdown”.

## 5. Baseline contracts

### `BASE-0` mandatory rule baseline

- allocate the low-frequency/bounded portion of demand to the battery;
- allocate the residual transient demand to the available auxiliary path;
- clamp both paths by current, voltage, energy/SOC, rate, and availability;
- curtail the load when feasible supply is insufficient;
- enter a deterministic fallback when a required input or source becomes
  invalid.

The exact split rule may be a fixed bounded filter or state table. It must use
fixed-size state and no dynamic allocation.

### `BASE-1` conditional PI extension

Add PI with anti-windup only if Pass A establishes a meaningful controlled
state, such as auxiliary voltage/energy restoration or DC-bus voltage. Record
the controlled variable, error sign, saturation order, integrator bounds,
reset/fault behavior, and tuning provenance. Do not add PI merely to make the
project look more sophisticated.

## 6. Deterministic scenarios and oracles

| Scenario class | Minimum case | Required observation |
| --- | --- | --- |
| Nominal demand change | steady, ramp, and pulse/step demand | power balance, bounded bus/state response, deterministic split |
| Limit/overload | battery or auxiliary limit followed by infeasible total demand | saturation priority, load curtailment, no state/command overflow |
| Fault | stale/invalid sensor and unavailable power path | detection, bounded fallback, declared recovery/latch behavior |

The oracle checks at least:

- conservation/power-balance residual within a declared numerical tolerance;
- all state, command, rate, and energy limits;
- deterministic mode/fault transitions and bounded recovery;
- identical scenario identity and sign/units in high-level and bounded-C runs;
- high-level/C output agreement within declared absolute/relative/fixed-point
  tolerances.

## 7. Decision record

`GO` requires a bounded boundary, meaningful allocation problem, traceable
parameter ranges, implementable baseline, deterministic scenarios/oracles, and
an approved data-handling classification. It opens the real W0 phase package.

`PIVOT` selects a simpler generic electrical/mechanical load, removes the
optional source, or changes the controlled variable while preserving the
question and existing evidence.

`DEFER` names the exact missing source, parameter family, tool, or expert review
and its re-entry condition.

`NO-GO` records why no bounded control-relevant surrogate can be defined
without fabricating requirements. It is a valid result and does not delete the
source audits or boundary analysis.
