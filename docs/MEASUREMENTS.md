# Measurements

How the model in `JellyGlassButton` was derived, and how far to trust it.

## Source

One screen recording (macOS, 60 fps, retina) of a chat app's Liquid Glass redesign, in which a few round and
pill-shaped glass buttons were pressed, dragged around and released. The mic button in the input row gives the
cleanest data.

## Method

1. **Cursor tracking.** The arrow cursor (black fill, white outline) was found in every frame by masked
   template matching (`TM_SQDIFF_NORMED` with a mask that keeps only the cursor's own pixels), searching a
   window around the last position and falling back to a half-resolution full-frame search. Hotspot = the
   arrow's tip.
2. **Button tracking.** The white glyph of the button (`min(R,G,B) > 205` and nearly neutral) was thresholded
   inside a small region, the cursor masked out, and the largest connected blob's bounding box taken. Because
   the glyph deforms together with the glass, its box gives the button's scale and centre directly.
3. **Rest pose.** Glyph 37 × 53 px at (2686.5, 2186) in video pixels (2 px = 1 pt).
4. **Pairing.** For frames where both cursor and button were found: `d` = cursor distance from the button's rest
   centre (press point), `t` = distance of the button centre from rest, and the stretch along the pull
   `s = √((w/37) / (h/53))` (volume-preserving, so one number covers both axes).

The plot: [measurements.png](media/measurements.png) — left: cursor path (dots) and button travel (×10, crosses) with
the press point at the origin; middle: button travel vs cursor distance; right: stretch vs travel.

## Data points (settled holds, lag removed)

| cursor distance d | body travel t | stretch along the pull |
|---|---|---|
| 38 pt | 6 pt | ×1.03 |
| 55 pt | 7 pt | ×1.06 |
| 80 pt | 8.5 pt | ×1.06 |
| 163 pt | 13 pt | ×1.17 |
| 185 pt | 13.8 pt | ×1.18 |
| ≈ 800 pt | 15 pt | ×1.27 |

## Fit

```
t(d) = 6.5 · ln(1 + d / 28)
e(d) = 0.105 · ln(1 + d / 50) · d² / (d² + 40²)        (stretch = 1 + e)
```

An earlier fit used `tanh` and saturated at 15 pt / ×1.27 because the vertical hold in the recording plateaus
there. Using the app by hand showed it does not stop: it keeps stretching, more and more slowly. The
logarithmic form has no ceiling and matches the settled points below ~200 pt.

## Dynamics

- Following the cursor: first-order lag, τ ≈ 50 ms (a critically damped spring, ω ≈ 45 rad/s).
- Release in the recording: the glass is back in ~60 ms with no visible overshoot; the glyph overshoots rest by
  ~5 % of its size (35 px against 37 px) before settling.
- The shipped default (`jelly`) is deliberately looser than the recording — it was judged to feel better.
  `snappy` reproduces the measurement.

## Caveats

- One recording, one button. The horizontal hold (mic dragged into the neighbouring pill) went further
  (23 pt, ×1.41) but the cursor was outside the frame there, so it is not in the fit; it inspired the `wide` preset.
- The cursor is hidden or off-screen for stretches of the recording, so the `d` range above ≈ 200 pt rests on
  a single vertical flick.
- Diagonal pulls were not in the recording; "grow instead of elongate" comes from hands-on comparison.
