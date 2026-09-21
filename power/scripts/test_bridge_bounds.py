#!/usr/bin/env python3
"""Small fail-closed checks for measured DSP activity translation."""

import unittest

from make_saif_dsp_bridge import vivado_legal_probability


class VivadoBridgeBoundsTest(unittest.TestCase):
    def test_legal_pair_is_unchanged(self) -> None:
        self.assertEqual(
            vivado_legal_probability({
                "static_probability_mean": 0.25,
                "toggle_rate_percent_mean": 20.0,
            }),
            0.25,
        )

    def test_small_quantization_gap_is_bounded(self) -> None:
        self.assertAlmostEqual(
            vivado_legal_probability({
                "static_probability_mean": 0.099998,
                "toggle_rate_percent_mean": 20.0,
            }),
            0.100001,
        )

    def test_material_inconsistency_fails(self) -> None:
        with self.assertRaisesRegex(ValueError, "exceeds 0.0001"):
            vivado_legal_probability({
                "static_probability_mean": 0.09,
                "toggle_rate_percent_mean": 20.0,
            })

    def test_impossible_toggle_fails(self) -> None:
        with self.assertRaisesRegex(ValueError, "exceeds 100%"):
            vivado_legal_probability({
                "static_probability_mean": 0.5,
                "toggle_rate_percent_mean": 101.0,
            })


if __name__ == "__main__":
    unittest.main()
