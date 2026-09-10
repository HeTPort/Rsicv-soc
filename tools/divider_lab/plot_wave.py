"""Render a compact teaching figure from the simulator's recorded JSONL trace."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace", type=Path,
                        default=ROOT / "build/divider_lab/sim/green/trace.jsonl")
    parser.add_argument("--out", type=Path,
                        default=ROOT / "doc/plans/divider-design-lab/evidence/divider_wave.png")
    args = parser.parse_args()
    rows = [json.loads(line) for line in args.trace.read_text(encoding="utf-8").splitlines()]
    rows = [row for row in rows if row["case"] == 1]
    if len(rows) != 34 or rows[-2]["quotient"] != 14 or rows[-2]["remainder"] != 2:
        raise SystemExit("unexpected trace; rerun the simulation lab")

    width, height = 1500, 680
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default()
    left, right = 150, 1450
    dx = (right - left) / 34

    draw.text((left, 20), "Actual ModelSim samples: unsigned 100 / 7 @ 25 MHz", fill="#111", font=font)
    draw.text((left, 40), "Each marker is sampled 1 ns after a rising edge (after NBA updates).", fill="#555", font=font)
    signal_rows = [("start", 105, "#7950f2"), ("busy", 175, "#1971c2"),
                   ("complete", 245, "#e03131")]
    for key, y, color in signal_rows:
        draw.text((35, y - 8), key, fill="#111", font=font)
        draw.line((left, y + 20, right, y + 20), fill="#ddd", width=1)
        values = [row[key] for row in rows]
        for index, value in enumerate(values):
            x0 = left + index * dx
            x1 = left + (index + 1) * dx
            yy = y if value else y + 35
            draw.line((x0, yy, x1, yy), fill=color, width=4)
            if index + 1 < len(values) and values[index + 1] != value:
                draw.line((x1, y, x1, y + 35), fill=color, width=3)

    y_iter = 345
    draw.text((35, y_iter - 8), "iteration", fill="#111", font=font)
    for index, row in enumerate(rows):
        x = left + (index + 0.5) * dx
        draw.text((x - 6, y_iter), str(row["iteration"]), fill="#2b8a3e", font=font)
    draw.line((left, y_iter + 22, right, y_iter + 22), fill="#ddd")

    draw.text((35, 420), "last steps", fill="#111", font=font)
    draw.text((left, 405), "step        work_q (hex)   work_r   compare/subtract result", fill="#555", font=font)
    tail = [row for row in rows if 25 <= row["step"] <= 32]
    for index, row in enumerate(tail):
        label = (f"{row['step']:>2}          0x{row['work_q']:08x}"
                 f"       {row['work_r']:>2}       "
                 f"{'final q=14 r=2' if row['phase'] == 'complete' else 'RUN'}")
        draw.text((left, 430 + 26 * index), label,
                  fill="#c92a2a" if row["phase"] == "complete" else "#222", font=font)

    for step in (0, 8, 16, 24, 32, 33):
        x = left + (step + 0.5) * dx
        draw.line((x, 75, x, 390), fill="#eee", width=1)
        draw.text((x - 7, 375), str(step), fill="#555", font=font)
    draw.text((left, 650), "Expected protocol: start sampled -> 32 RUN edges -> one COMPLETE sample -> IDLE.",
              fill="#111", font=font)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.out)
    print(args.out)


if __name__ == "__main__":
    main()
