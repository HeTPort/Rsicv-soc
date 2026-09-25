#!/usr/bin/env python3
"""Create an explicit RTL-SAIF to routed-DSP activity bridge."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


DURATION_RE = re.compile(r"\(DURATION\s+(\d+)\)")
NET_RE = re.compile(
    r"^\s*\((lhs_ext|rhs_ext|product_ext|req_q\\\.lhs|req_q\\\.rhs|"
    r"pp_ll_q|pp_lh_q|pp_hl_q|pp_hh_q)\\\[(\d+)\\\]\s+"
    r"\(T0\s+(\d+)\)\s+\(T1\s+(\d+)\)\s+\(TX\s+(\d+)\)\s+"
    r"\(TC\s+(\d+)\)"
)


def summarize(rows: list[dict[str, int]], duration_ps: int, clock_mhz: float) -> dict:
    count = len(rows)
    if count == 0:
        raise ValueError("SAIF group has no signals")
    total_t1 = sum(row["t1"] for row in rows)
    total_tc = sum(row["tc"] for row in rows)
    static_probability = total_t1 / (duration_ps * count)
    signal_rate_mhz = total_tc * 1_000_000.0 / (duration_ps * count)
    toggle_rate_percent = 100.0 * signal_rate_mhz / clock_mhz
    return {
        "signals": count,
        "total_transitions": total_tc,
        "static_probability_mean": static_probability,
        "signal_rate_mhz_mean": signal_rate_mhz,
        "toggle_rate_percent_mean": toggle_rate_percent,
    }


def vivado_legal_probability(summary: dict) -> float:
    """Bound only a tiny SAIF-window quantization discrepancy for Vivado."""
    measured = summary["static_probability_mean"]
    half_toggle = summary["toggle_rate_percent_mean"] / 200.0
    if half_toggle > 0.5:
        raise ValueError("measured mean toggle rate exceeds 100% of the clock")
    lower = half_toggle
    upper = 1.0 - half_toggle
    adjustment = max(lower - measured, measured - upper, 0.0)
    if adjustment > 0.0001:
        raise ValueError(
            "measured probability/toggle inconsistency exceeds 0.0001; "
            f"gap={adjustment:.9g}"
        )
    if measured < lower:
        return lower + 0.000001
    if measured > upper:
        return upper - 0.000001
    return measured


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("saif", type=Path)
    parser.add_argument("output_tcl", type=Path)
    parser.add_argument("output_json", type=Path)
    parser.add_argument("--clock-mhz", type=float, default=95.0)
    parser.add_argument(
        "--cell-pattern",
        default="*u_rv32m_mul_reg*",
        help="Vivado hierarchical multiplier instance glob",
    )
    args = parser.parse_args()

    text = args.saif.read_text(encoding="utf-8", errors="replace")
    duration_match = DURATION_RE.search(text)
    if not duration_match:
        raise SystemExit("SAIF lacks DURATION")
    duration_ps = int(duration_match.group(1))
    groups: dict[str, list[dict[str, int]]] = {
        name: [] for name in (
            "lhs_ext", "rhs_ext", "product_ext",
            r"req_q\.lhs", r"req_q\.rhs",
            "pp_ll_q", "pp_lh_q", "pp_hl_q", "pp_hh_q",
        )
    }
    for line in text.splitlines():
        match = NET_RE.match(line)
        if match:
            groups[match.group(1)].append({
                "bit": int(match.group(2)),
                "t0": int(match.group(3)),
                "t1": int(match.group(4)),
                "tx": int(match.group(5)),
                "tc": int(match.group(6)),
            })

    summaries = {
        name: summarize(rows, duration_ps, args.clock_mhz)
        for name, rows in groups.items() if rows
    }
    if groups["lhs_ext"] and groups["rhs_ext"] and groups["product_ext"]:
        operand_sources = ["lhs_ext", "rhs_ext"]
        product_sources = ["product_ext"]
    else:
        operand_sources = [r"req_q\.lhs", r"req_q\.rhs"]
        product_sources = ["pp_ll_q", "pp_lh_q", "pp_hl_q", "pp_hh_q"]
    operand_rows = [row for name in operand_sources for row in groups[name]]
    product_rows = [row for name in product_sources for row in groups[name]]
    operand = summarize(operand_rows, duration_ps, args.clock_mhz)
    product = summarize(product_rows, duration_ps, args.clock_mhz)
    operand_probability = vivado_legal_probability(operand)
    product_probability = vivado_legal_probability(product)
    operand["vivado_static_probability"] = operand_probability
    operand["probability_adjustment"] = operand_probability - operand["static_probability_mean"]
    product["vivado_static_probability"] = product_probability
    product["probability_adjustment"] = product_probability - product["static_probability_mean"]

    result = {
        "schema_version": 1,
        "method": "mean measured RTL-SAIF activity applied to nonconstant routed DSP48 operand/output nets",
        "saif": str(args.saif.resolve()),
        "duration_ps": duration_ps,
        "clock_mhz": args.clock_mhz,
        "cell_pattern": args.cell_pattern,
        "operand_sources": operand_sources,
        "product_sources": product_sources,
        "groups": summaries,
        "bridge_values": {"operand": operand, "product": product},
        "limitations": [
            "This is a reviewed block bridge, not direct whole-design net mapping.",
            "Mean per-bit activity preserves measured workload intensity but not bit-to-pin correlation.",
            "RTL functional SAIF does not model routed glitches.",
            "Only a <=0.0001 absolute probability/toggle discrepancy from the SAIF window may be adjusted to Vivado's legal bound; both measured and applied values are retained.",
        ],
    }
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

    tcl = f"""# Generated from {args.saif.resolve().as_posix()}
# Do not edit: regenerate with make_saif_dsp_bridge.py.
set p0_dsp_cells [get_cells -hierarchical -filter {{REF_NAME == DSP48E1 && NAME =~ {args.cell_pattern}}}]
if {{[llength $p0_dsp_cells] != 4}} {{
  error "Expected four routed multiplier DSP48E1 cells, got [llength $p0_dsp_cells]"
}}
set p0_dsp_operand_nets [list]
set p0_dsp_product_nets [list]
foreach p0_cell $p0_dsp_cells {{
  foreach p0_pin [get_pins -quiet -of_objects $p0_cell] {{
    set p0_ref_pin [get_property REF_PIN_NAME $p0_pin]
    set p0_nets [get_nets -quiet -of_objects $p0_pin]
    foreach p0_net $p0_nets {{
      if {{[string match "*<const*" $p0_net] || [string match "*GND*" $p0_net] || [string match "*VCC*" $p0_net]}} {{
        continue
      }}
      if {{[regexp {{^[AB]\\[[0-9]+\\]$}} $p0_ref_pin]}} {{
        lappend p0_dsp_operand_nets $p0_net
      }} elseif {{[regexp {{^(P|PCOUT)\\[[0-9]+\\]$}} $p0_ref_pin]}} {{
        lappend p0_dsp_product_nets $p0_net
      }}
    }}
  }}
}}
set p0_dsp_operand_nets [lsort -unique $p0_dsp_operand_nets]
set p0_dsp_product_nets [lsort -unique $p0_dsp_product_nets]
if {{[llength $p0_dsp_operand_nets] == 0 || [llength $p0_dsp_product_nets] == 0}} {{
  error "DSP activity bridge resolved no nonconstant operand or product nets"
}}
set_switching_activity -static_probability {operand_probability:.9f} -toggle_rate {operand['toggle_rate_percent_mean']:.9f} $p0_dsp_operand_nets
set_switching_activity -static_probability {product_probability:.9f} -toggle_rate {product['toggle_rate_percent_mean']:.9f} $p0_dsp_product_nets
puts "P0_DSP_BRIDGE_CELLS=[llength $p0_dsp_cells]"
puts "P0_DSP_BRIDGE_OPERAND_NETS=[llength $p0_dsp_operand_nets]"
puts "P0_DSP_BRIDGE_PRODUCT_NETS=[llength $p0_dsp_product_nets]"
puts "P0_DSP_BRIDGE: PASS"
"""
    args.output_tcl.write_text(tcl, encoding="utf-8")
    print(json.dumps(result, indent=2))
    print("P0_DSP_BRIDGE_GENERATION: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
