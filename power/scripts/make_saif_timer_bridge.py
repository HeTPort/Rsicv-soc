#!/usr/bin/env python3
"""Map measured timer state-bit activity to routed timer register Q nets."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


DURATION_RE = re.compile(r"\(DURATION\s+(\d+)\)")
NET_RE = re.compile(
    r"^\s*\((mtime_q|mtimecmp_q)\\\[(\d+)\\\]\s+"
    r"\(T0\s+(\d+)\)\s+\(T1\s+(\d+)\)\s+\(TX\s+(\d+)\)\s+"
    r"\(TC\s+(\d+)\)"
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("saif", type=Path)
    parser.add_argument("output_tcl", type=Path)
    parser.add_argument("output_json", type=Path)
    parser.add_argument("--clock-mhz", type=float, default=95.0)
    args = parser.parse_args()

    source = args.saif.read_text(encoding="utf-8", errors="replace")
    duration_match = DURATION_RE.search(source)
    if not duration_match:
        raise SystemExit("SAIF lacks DURATION")
    duration_ps = int(duration_match.group(1))
    rows: dict[str, dict[int, dict[str, float | int]]] = {
        "mtime_q": {}, "mtimecmp_q": {}
    }
    for line in source.splitlines():
        match = NET_RE.match(line)
        if not match:
            continue
        group, bit, t0, t1, tx, tc = match.groups()
        index = int(bit)
        if index in rows[group]:
            raise SystemExit(f"duplicate {group}[{index}] in SAIF")
        if int(t0) + int(t1) + int(tx) != duration_ps:
            raise SystemExit(f"incomplete duration for {group}[{index}]")
        signal_rate_mhz = int(tc) * 1_000_000.0 / duration_ps
        raw_toggle_percent = 100.0 * signal_rate_mhz / args.clock_mhz
        # ModelSim rounds the 95 MHz half-period to picoseconds. For a bit
        # toggling on every edge, the SAIF duration can therefore imply a
        # value a few thousandths above Vivado's legal 100% upper bound.
        if raw_toggle_percent > 100.1:
            raise SystemExit(
                f"implausible timer toggle rate {group}[{index}]: "
                f"{raw_toggle_percent:.6f}%"
            )
        toggle_percent = min(100.0, raw_toggle_percent)
        raw_static_probability = int(t1) / duration_ps
        probability_low = toggle_percent / 200.0
        probability_high = 1.0 - probability_low
        if (raw_static_probability < probability_low - 0.0001 or
                raw_static_probability > probability_high + 0.0001):
            raise SystemExit(
                f"implausible timer probability {group}[{index}]: "
                f"{raw_static_probability:.9f} for {toggle_percent:.6f}% toggles"
            )
        rows[group][index] = {
            "t0_ps": int(t0),
            "t1_ps": int(t1),
            "tx_ps": int(tx),
            "transitions": int(tc),
            "static_probability_raw": raw_static_probability,
            "static_probability": min(
                probability_high, max(probability_low, raw_static_probability)
            ),
            "toggle_rate_percent_raw": raw_toggle_percent,
            "toggle_rate_percent": toggle_percent,
        }
    for group, bits in rows.items():
        if set(bits) != set(range(64)):
            raise SystemExit(f"expected exactly bits 0..63 for {group}; got {len(bits)}")

    result = {
        "schema_version": 1,
        "method": "per-bit RTL-SAIF timer register state mapped to routed register Q nets",
        "saif": str(args.saif.resolve()),
        "duration_ps": duration_ps,
        "clock_mhz": args.clock_mhz,
        "clamped_100_percent_bits": [
            f"{group}[{bit}]"
            for group, bits in rows.items()
            for bit, row in bits.items()
            if row["toggle_rate_percent_raw"] > 100.0
        ],
        "clamped_probability_bits": [
            f"{group}[{bit}]"
            for group, bits in rows.items()
            for bit, row in bits.items()
            if row["static_probability_raw"] != row["static_probability"]
        ],
        "groups": {
            group: {
                "signals": 64,
                "total_transitions": sum(row["transitions"] for row in bits.values()),
                "active_bits": sum(row["transitions"] > 0 for row in bits.values()),
                "bits": bits,
            }
            for group, bits in rows.items()
        },
        "limitations": [
            "Register Q activity is measured; optimized timer combinational logic is propagated.",
            "RTL functional SAIF does not model routed glitches.",
        ],
    }
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

    tcl = [
        f"# Generated from {args.saif.resolve().as_posix()}",
        "# Per-bit timer state bridge; fail if the implemented timer cannot be resolved.",
    ]
    for group, bits in rows.items():
        for bit, row in sorted(bits.items()):
            tcl.append(
                f"set p0_timer_activity({group},{bit}) "
                f"{{{row['static_probability']:.12f} {row['toggle_rate_percent']:.12f}}}"
            )
    tcl.extend([
        "set p0_timer_cells [get_cells -hierarchical -filter {NAME =~ *u_timer_target* && REF_NAME =~ FD*}]",
        "set p0_timer_mapped(mtime_q) 0",
        "set p0_timer_mapped(mtimecmp_q) 0",
        "set p0_timer_active(mtime_q) 0",
        "set p0_timer_active(mtimecmp_q) 0",
        "foreach p0_cell $p0_timer_cells {",
        "  if {![regexp {/(mtime_q|mtimecmp_q)_reg\\[([0-9]+)\\]$} $p0_cell -> p0_group p0_bit]} {continue}",
        "  if {![info exists p0_timer_activity($p0_group,$p0_bit)]} {continue}",
        "  set p0_q [get_pins -quiet -of_objects $p0_cell -filter {REF_PIN_NAME == Q}]",
        "  set p0_nets [get_nets -quiet -of_objects $p0_q]",
        "  if {[llength $p0_nets] != 1} {error \"Timer register $p0_cell has no unique Q net\"}",
        "  lassign $p0_timer_activity($p0_group,$p0_bit) p0_static p0_toggle",
        "  set_switching_activity -static_probability $p0_static -toggle_rate $p0_toggle $p0_nets",
        "  incr p0_timer_mapped($p0_group)",
        "  if {$p0_toggle > 0} {incr p0_timer_active($p0_group)}",
        "}",
        "if {$p0_timer_mapped(mtime_q) < 32 || $p0_timer_mapped(mtimecmp_q) < 16} {",
        "  error \"Insufficient routed timer register coverage: mtime=$p0_timer_mapped(mtime_q) mtimecmp=$p0_timer_mapped(mtimecmp_q)\"",
        "}",
        "puts \"P0_TIMER_BRIDGE_MTIME_NETS=$p0_timer_mapped(mtime_q)\"",
        "puts \"P0_TIMER_BRIDGE_MTIMECMP_NETS=$p0_timer_mapped(mtimecmp_q)\"",
        "puts \"P0_TIMER_BRIDGE_MTIME_ACTIVE=$p0_timer_active(mtime_q)\"",
        "puts \"P0_TIMER_BRIDGE_MTIMECMP_ACTIVE=$p0_timer_active(mtimecmp_q)\"",
        "puts \"P0_TIMER_BRIDGE: PASS\"",
    ])
    args.output_tcl.write_text("\n".join(tcl) + "\n", encoding="utf-8")
    print(json.dumps({
        "duration_ps": duration_ps,
        "group_counts": {group: len(bits) for group, bits in rows.items()},
        "active_bits": {group: result["groups"][group]["active_bits"] for group in rows},
    }, indent=2))
    print("P0_TIMER_BRIDGE_GENERATION: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
