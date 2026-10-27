# How it works

Notes from getting a deformable glass button to render correctly inside `NSGlassEffectContainerView`
on macOS 26. Everything below was found by dumping the live layer tree and by experiment, not from
documentation. Treat it as observations of one macOS 26 build.

## 1. What AppKit gives you

Public: `NSGlassEffectView` (`cornerRadius`, `tintColor`, `style`, `contentView`) and
`NSGlassEffectContainerView` (`spacing`, `contentView`). Nothing about interaction, shape or morphing.

Private selectors visible with `class_copyMethodList` on `NSGlassEffectView`:

```
_setPath:                 (CGPath)   custom silhouette
_path
_interactionState / set_interactionState:   (Int)
_variant, _subvariant, _adaptiveAppearance, _contentLensing, _scrimState, _subduedState,
_useReducedShadowRadius, _groupIdentifier, …
```

QuartzCore ships the SDF engine behind the glass: `CASDFLayer` (`smoothness`, `mergeElements`,
`gaussianRadius`, `effect`), `CASDFElementLayer` (`operation`, `mode`, `gradientOvalization`,
`hitTestsAsFill`) and effects `CASDFGlassDisplacementEffect`, `CASDFGlassHighlightEffect`,
`CASDFKeyFillHighlightEffect`, `CASDFShadowEffect`, `CASDFFillEffect`, `CASDFGradientEffect`.

## 2. The layer tree of a glass container

Walk `window.contentView.superview.layer` and print every layer under the container. For a container with
three buttons:

```
SDFLayer                                  (frame = container bounds)
├─ CALayer (0×0)
│   ├─ CALayer  bg + filter   (frame of button 1)       ← per-button fill
│   ├─ CAPortalLayer          (sourceLayer = button 1's content)
│   ├─ … same for button 2, 3
├─ CALayer  (frame = bounding box of the buttons in one merge group)
│   ├─ CABackdropLayer        ← the blur / material, clipped to that box
│   │   └─ CASDFLayer  (effect: CASDFOutputEffect, smoothness = container.spacing)
│   │        └─ CALayer → CASDFElementLayer ×3      ← one silhouette per button
│   ├─ SDFPortalLayer
│   └─ CASDFLayer (effect: CASDFKeyFillHighlightEffect)   ← rim light
```

Key facts: the glass view's own layer carries only its **content** (your icons); the glass shape is a
`CASDFElementLayer` in the container's coordinates; `CASDFLayer.smoothness` equals the container's `spacing`.

## 3. Dead end: transforming the SDF layers

The obvious approach — find the button's `CASDFElementLayer` and its fill layer and give them a
`CATransform3D` — deforms the silhouette. But the `CABackdropLayer` canvas is sized to the **undeformed**
bounding box and the container resets it on every layout (even if you overwrite it each frame, the reset
wins before commit). Result: a lighter rectangle where the blur exists and a dark, unblurred cap where the
stretched shape sticks out.

## 4. What works: oversize the glass, drive `_setPath:`

- Make each `NSGlassEffectView` **larger than the button** (a 90 pt margin on all sides). The container's canvas
  is now big enough for any plausible deformation.
- Set the silhouette with `_setPath:` every frame: the resting capsule, scaled about its centre and shifted.
- A container only re-reads silhouettes during layout, so mark the glass and its ancestors up to the container
  `needsLayout = true` every frame.
- Put the icons in the glass's `contentView` and animate that layer with its own spring.

The container still merges neighbouring silhouettes (it works on shapes, not on view frames).

## 5. Lifted ("on top") vs merged

`_interactionState = 1` puts a glass in the *interacting* state: it is lifted out of the container group and
drawn on top of its neighbours with a highlight; it does not merge until it is set back to 0.
Without it the pressed glass stays in the group and melts into neighbours with a neck.

Do not set it by accident: it is what the system uses for the pressed look, and it silently turns off
merging. (This cost us a round of "why does it only merge after I let go".)

## 6. Merge physics

`CASDFLayer.smoothness` is the container's `spacing`. With a polynomial smooth-min:

- a bridge between two shapes exists when the gap is below `spacing / 2`;
- shapes lean toward each other (pointed tips) already below `spacing`.

So for a clean resting state use a resting gap ≥ `spacing`, and expect contact when the pull closes the
difference. The demo uses `spacing = 14` and a resting gap of 14 pt.

## 7. Colour on press

The public `tintColor` on the glass view is enough: white with alpha up to 0.16, eased in over ~70 ms and out
over ~180 ms. In a merge group this gives a light-to-dark gradient across the neck between a pressed and an
unpressed button.

## 8. Reproduce the layer dump

```swift
func dump(_ layer: CALayer, _ depth: Int = 0) {
    let pad = String(repeating: "  ", count: depth)
    print("\(pad)\(type(of: layer)) frame=\(layer.frame) bounds=\(layer.bounds) anchor=\(layer.anchorPoint)")
    layer.sublayers?.forEach { dump($0, depth + 1) }
}
dump(window.contentView!.superview!.layer!)
```

Private properties can be read through KVC, e.g. `layer.value(forKey: "smoothness")` on a `CASDFLayer`,
`layer.value(forKey: "sourceLayer")` on a `CAPortalLayer`.

## 9. Making the glass clear: the `glassBackground` filter

System glass, even `style = .clear`, looks milky: whatever is behind it is blurred and washed with white. The reason is a
private `CAFilter` named `glassBackground` on the `CABackdropLayer` that the container builds for each glass group
(dump the tree and print `layer.filters`; each filter lists its `inputKeys`). On macOS 26 it has, among others:

```
inputBlurRadius = 1            inputBlurOpacity0…4, inputBlurDistance0…4   frost, by distance from the edge
inputFaceOpacity = 1           inputFaceColorMatrixFillColor = white α 0.31  the milky body
inputRefractionOpacity = 0     inputInnerRefractionAmount = -42, …Height = 15.12
                               inputOuterRefractionAmount = 8.4,  …Height = 5.25   the lens at the rim
```

`BlurRadius = 0`, `FaceOpacity ≈ 0.15`, the fill alpha 0 and `RefractionOpacity = 1` give glass you can see through: the
grid behind it stays sharp and bends around the rim. Traps, in the order they bit:

- **Edit a copy.** Mutating the live filter object changes nothing on screen. Copy it (`filter.copy()`), set the inputs
  on the copy and assign `layer.filters = [copy]`.
- **Do not fight AppKit afterwards.** It rewrites the filter on every frame while the glass moves, after any layout
  hook, and a run-loop observer that patches it back runs after the commit. The result was the clear and the milky
  filter alternating frame by frame: the whole row appeared to shake. What works is to give each backdrop layer a
  dynamic subclass (`objc_allocateClassPair` + `object_setClass`, as KVO does) whose `setFilters:` clears the filter on
  the way in. Nothing wrong ever reaches the screen. An observer still finds *new* layers, at the end of a run-loop
  turn, so an idle app does no work.
- **The pressed glass has a second body.** A lifted button adds a `CASDFLayer` with a `CASDFGradientEffect` (white) on
  top, and resets its opacity to 1 every frame. Same remedy: a subclass whose `setOpacity:` caps it at 0.2.
- **Black crescents at the rim.** With a stronger inner refraction (`-70`) the lens samples outside the backdrop's
  rectangle, which ends exactly at the group's outer edges, and reads black there; the crescents also blinked.
  `bleedAmount` and `marginWidth` on the backdrop layer (40) give it room, and AppKit's own refraction strength is kept.
  `scale` (0.5) is raised to 1 so that the capture grid does not shimmer when one button moves.

## 10. The lens, measured

The rim of the system glass bends what is behind it in a way that is easy to see and hard to guess. The web version
does not guess it; it copies a profile measured from the real thing.

**How it was measured.** A `NSGlassEffectView` is laid over a backdrop in which the colour encodes the screen
coordinate: R and G are `cos` and `sin` of `2π·x/160`, B is a coarse ramp that resolves the 160 pt ambiguity. The
backdrop must be drawn in the screen's colour space (`window.screen.colorSpace`), otherwise the display profile bends the
phase. The window sits at desktop level, is ordered back and never activated, and `screencapture -l <window id>` takes
the picture. Decoding the phase of each pixel gives the coordinate it shows, so `shown − actual` is the displacement
at every point, to about 0.03 pt. The same is done along y.

**What it found.** A point at depth `d` inside the rim shows what lies `A · F(d / H)` further inside, along the normal:

```
A = min(shorter side, 60)          H = min(0.36 × shorter side, 20)         (points)

t     0     .05   .10   .15   .20   .25   .30   .35   .40   .45   .50
F   .840  .674  .562  .4645 .392  .328  .2751 .2282 .1877 .1517 .1203
t    .55   .60   .65   .70   .75   .80   .85   .90   .95   1.0
F   .0935 .0690 .0463 .0296 .0142 .0040  0     0     0     0
```

- The outer two thirds of the band show the inside of the glass **upside down**: the very edge looks up to 50 pt deeper,
  and the further in, the less. Then there is a short magnifying zone. Past `0.85 · H` the glass is 1:1.
- The direction is the outward normal of the same shape with its corners rounded 1.5× more
  (`R' = min(1.5 · R, half-size)`). For a capsule that is the same normal; for a rounded rectangle the lens pulls
  diagonally at the corners. The corner radius itself does not change the strength.
- The model reproduces the measurement to 0.1–1 pt.

**In the shader.** `LENS[21]` holds `F` in steps of 0.05 and `lensF(t)` interpolates it; the fragment samples the scene
at `p − n · A · lensF(din / H)`. The web version uses the shape's own normal. Dispersion is kept to ±1.5 % of the
displacement so white stays white, and the highlight is a thin contour (about one pixel wide, tinted by what lies under
it) instead of a broad specular band, as on the system glass.

**Trap: an inactive window blurs eight times more.** The same glass in a window that is not key is a different material:
the blur is `σ ≈ 1.75 · BlurRadius` (up to 17 pt) and the fill is milky. What a user sees is the active look
(`BlurRadius` 1, `σ` about 2 pt in the middle and half that at the rim). To measure that, the probe window must be a
`NSWindow` subclass that returns `true` from `isKeyWindow` and `_hasActiveAppearance`.
