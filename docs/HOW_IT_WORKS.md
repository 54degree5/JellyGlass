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

Setting `BlurRadius = 0`, `FaceOpacity ≈ 0.15`, the fill alpha to 0, `RefractionOpacity = 1` and a stronger inner
refraction gives glass you can see through: the grid behind it stays sharp and bends around the rim.

Two traps:

- **Edit a copy.** Mutating the live filter object changes nothing on screen. Copy it (`filter.copy()`), set the inputs
  on the copy and assign `layer.filters = [copy]`.
- **AppKit puts the original back** whenever it rebuilds the layers: on press, on release, on layout. Re-applying in
  the button's `layout()` is not enough (it misses the rebuild after the spring settles). `JellyGlass` re-applies in a
  run-loop observer that fires last, just before the thread sleeps, and flushes the transaction if it changed anything.
  An idle app does no work.
