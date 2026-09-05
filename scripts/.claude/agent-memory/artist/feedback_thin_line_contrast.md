---
name: thin-line-contrast
description: 1px detail lines (antennas, arms, wires) must not use palette.OUTLINE as fill — verify contrast on a synthetic dark AND light background before calling a sprite done
metadata:
  type: feedback
---

For sprites with thin (1px) protruding details — sensor arms, antennas, wires,
cables — do not fill the shaft with `palette.OUTLINE` (#1a1410, near-black).
It reads fine in an isolated PNG viewer (default/checkerboard background) but
becomes nearly invisible once composited over a dark game background (e.g.
underground cave), because OUTLINE and near-black backgrounds have almost no
luminance difference. The detail visually disappears, leaving only any
brighter accent/joint pixels floating disconnected from the main shape.

**Why:** Caught this on the probe-droid bot redesign (`assets/sprites/gen_bots.py`,
2026-07-17) — first pass used OUTLINE for the sensor-arm shafts; compositing
over a synthetic dark test background showed the arms vanishing into floating
STEEL_HI joint-dots instead of reading as connected legs. Fixed by using
STEEL_MID for shafts (mid-tone, ~40% luminance) with STEEL_HI at joints/bends,
which reads clearly on both dark cave and light sky backgrounds.

**How to apply:** For any 1px-wide protruding detail (can't have a separate
outline+fill ring at that width — no room), pick a mid-tone palette color
(STEEL_MID or equivalent) for the base line, not OUTLINE. Before marking a
sprite with thin details as done, composite it (PIL `Image.alpha_composite`)
over both a synthetic dark (~rgb 18,16,20) and light (~rgb 210,220,230)
background, resize with `Image.NEAREST`, and Read both — not just the raw
transparent PNG or the default preview sheet. See [[project_seed_ship]] for
the probe-droid bot task context.
