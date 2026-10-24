# Taption Encoder design system

The contract for colour, type, spacing, shape and motion in the app. It exists so a change to one
value is a one-line edit instead of a search for every place that value was retyped.

Status: **token layer shipped, adoption in progress.** `TaptionTheme` already had the palette; this
document and `Shared/DesignSystem/TaptionDesignSystem.swift` give it structure. Existing screens
keep working unchanged — the token values are byte-identical to what shipped.

---

## 0. Where things live

| What | Where |
| --- | --- |
| Primitives, semantic colours, type, spacing, radius, motion, elevation, device classes | `TaptionEncoder/Shared/DesignSystem/TaptionDesignSystem.swift` |
| Card container | `TaptionEncoder/Shared/UI/ProgressCard.swift` |
| Primary button | `TaptionEncoder/Shared/UI/PrimaryActionButton.swift` |
| Status banner | `TaptionEncoder/Shared/UI/StatusBanner.swift` |
| Layout scale factors | `TaptionEncoder/Features/Home/HomeLayoutMetrics.swift` |

Two layers, and the rule is one-directional:

```
TaptionColor (primitives)  →  TaptionTheme (semantic)  →  views
        never referenced directly            never a raw hex
```

A view may only name a **role** (`TaptionTheme.border`), never a **value** (`#2F4650`). That is what
makes a palette change safe.

---

## 1. Device matrix

One binary serves four shapes. The foldable changes class while it is running, so the class is
derived from geometry, not from `UIUserInterfaceIdiom` — an unfolded Duo still reports `.phone`.

| Class | Device | Points | Short side | Scale | Layout |
| --- | --- | --- | --- | --- | --- |
| `phone` | iPhone 18 Pro Max | 440 × 956 | 440 | 3× | compact |
| `phone` | iPhone 18 Pro | 402 × 874 | 402 | 3× | compact |
| `foldableOuter` | **iPhone Duo, folded** | **466 × 678** | 466 | 3× | compact, scaled to 0.74 |
| `foldableInner` | **iPhone Duo, unfolded** | **626 × 890** | 626 | 3× | **wide — the iPad arrangement** |
| `pad` | iPad mini | 744 × 1133 | 744 | 2× | wide |

Sources: Apple's iPhone Duo technical specifications (inner 1878 × 2670 px @ 430 ppi, outer
1398 × 2034 px @ 460 ppi) divided by the 3× scale.

**The threshold is 600 pt** (`HomeLayoutMetrics.wideLayoutMinimumShortSide`). It sits in the gap
between 466 and 626, so:

- the folded Duo keeps the phone layout — the requirement is that it looks like today's app, only
  fitted to a shorter, wider panel;
- the unfolded Duo cannot miss the wide layout;
- no iPhone reaches it, landscape included, where the short side tops out at 440.

Rotation follows the same predicate (`AppOrientationController.homeOrientations`), so a screen laid
out like an iPad also rotates like one. The folded Duo stays portrait-only.

### What "scaled to fit" means on the outer display

The outer panel is 466 × 678 pt. The layout does not stretch to 466 wide; it keeps the phone
content column (capped at 430 pt) and shrinks the type to fit the shorter height:

```
heightScale = 678 / 844 = 0.803   →  contentScale 0.739 (0.72 floor)
canvasWidth = min(466, 430) = 430 →  ~18 pt gutters
```

That is deliberate. A 466 pt-wide column would reflow every row for a screen that is only used for
glances; shrinking keeps the same information in the same order.

---

## 2. Principles

1. **Dark by construction, not by preference.** The palette is a single teal-slate ramp. Light mode
   is out of scope; the app is a video tool and the dark surface keeps attention on the footage.
2. **Role names, never appearance names.** `elevatedSurface`, not `darkBlue2`.
3. **One radius.** 8 pt carries 81 call sites. A second radius has to justify itself.
4. **Type scales, it does not truncate.** Dense layouts drop one Dynamic Type step
   (`TaptionType.header(compact:)`) rather than clipping.
5. **Contrast is measured, not eyeballed.** Every text/background pair below has a computed WCAG
   ratio; §3.4 lists the two pairs that fail and what to do about them.

---

## 3. Colour

### 3.1 Primitives

Raw values. Only `TaptionDesignSystem.swift` may reference these.

| Token | Hex | Luminance | Note |
| --- | --- | --- | --- |
| `ink1000` | `#0B1B21` | 0.0067 | darkest, text on accent |
| `ink900` | `#0F191E` | 0.0089 | app background |
| `ink800` | `#182931` | 0.0200 | card surface |
| `ink700` | `#1D333D` | 0.0297 | raised surface |
| `ink600` | `#203E48` | 0.0422 | selected row |
| `ink500` | `#2F4650` | 0.0556 | hairline border |
| `ink400` | `#526E7A` | 0.1435 | strong border, inactive glyph |
| `ink300` | `#78909B` | — | disabled text |
| `ink200` | `#9AAFBA` | — | secondary text |
| `ink100` | `#E8F3F7` | — | primary text |
| `cyan500` | `#6DD0E5` | — | accent |
| `coral500` | `#EBA58B` | — | warning / destructive |
| `mint500` | `#91CBB6` | — | success |
| `amber500` | `#E5C184` | — | reward / stars |

### 3.2 Semantic

| Token | Primitive | Used for |
| --- | --- | --- |
| `appBackground` | `ink900` | window background |
| `surface` | `ink800` | cards, panels |
| `elevatedSurface` | `ink700` | controls inside a card, sheets |
| `selectedSurface` | `ink600` | selected queue row |
| `border` | `ink500` | card hairline |
| `strongBorder` | `ink400` | dividers that must be seen, disabled glyphs |
| `primaryText` | `ink100` | body, titles |
| `mutedText` | `ink200` | secondary labels, metadata |
| `disabledText` | `ink300` | **disabled controls only** |
| `accent` | `cyan500` | primary action, selection, progress |
| `accentButtonText` | `ink1000` | label on an accent fill |
| `coral` | `coral500` | failure, destructive |
| `success` | `mint500` | completion |
| `reward` | `amber500` | star balance |

### 3.3 Measured contrast

WCAG 2.1 contrast ratios, computed from the sRGB values above.

| Foreground | on `appBackground` | on `surface` | on `elevatedSurface` | Verdict |
| --- | --- | --- | --- | --- |
| `primaryText` | 15.78 | 13.28 | 11.67 | AAA |
| `mutedText` | 7.82 | 6.58 | 5.78 | AAA on bg, AA elsewhere |
| `disabledText` | 5.31 | 4.47 | **3.93** | see §3.4 |
| `accent` | 10.02 | 8.43 | 7.41 | AAA |
| `coral` | 8.73 | 7.35 | 6.46 | AAA |
| `success` | 9.70 | 8.16 | 7.17 | AAA |
| `reward` | 10.43 | 8.78 | 7.72 | AAA |
| `accentButtonText` on `accent` | — | 9.89 | — | AAA |

Non-text pairs:

| Pair | Ratio | Requirement |
| --- | --- | --- |
| `border` on `surface` | 1.51 | 3.0 for meaningful boundaries |
| `strongBorder` on `surface` | 2.76 | 3.0 |
| `surface` on `appBackground` | 1.19 | 3.0 if the edge is the only affordance |
| `elevatedSurface` on `surface` | 1.14 | — |
| `selectedSurface` on `surface` | 1.32 | — |

### 3.4 The two pairs that fail, and what to do

**F1 — surface edges are below 3:1.** A card is separated from the background by 1.19:1 of fill
plus a 1.51:1 hairline. Neither reaches the 3:1 that WCAG 1.4.11 asks of a control boundary. The
card still reads correctly for a sighted user (the eye uses the hairline plus layout), but a
low-vision user gets no reliable edge.

Recommended fix, additive and non-breaking: keep `border` as decoration, and introduce a
`focusBorder` for anything interactive or focused.

| Candidate | vs `surface` | vs `elevatedSurface` | vs `appBackground` |
| --- | --- | --- | --- |
| `#5A7A87` | 3.26 | 2.87 | 3.88 |
| **`#628391`** | **3.70** | **3.25** | **4.39** |
| `#6B8E9C` | 4.27 | 3.75 | 5.07 |

`#628391` is the smallest step that clears 3:1 on every surface. Not applied yet — it changes the
look of every card, so it needs a screenshot pass of its own.

**F2 — `disabledText` is 3.93:1 on `elevatedSurface`.** Below 4.5:1 for body text. WCAG exempts
disabled controls, so this is compliant, but it is close enough that the token must not be reused
for live text. Audited: all 13 call sites gate on a disabled/interactable flag. Keep it that way.

**F3 — ad-hoc white.** 32 call sites use `Color.white.opacity(0.88…0.92)` for enabled labels
instead of `primaryText`. On the dark surfaces the result is visually near-identical but it is a
separate value that will not follow a palette change and does not participate in Increase
Contrast. Migrate to `primaryText` as files are touched.

---

## 4. Typography

Expressed as Dynamic Type styles, never fixed sizes — the app must survive a text-size change.

| Token | Style | Used for |
| --- | --- | --- |
| `screenTitle` | `.title2.bold` | screen titles |
| `sectionTitle` | `.title3.semibold` | section headers |
| `rowTitle` | `.body.semibold` | file names, row leads |
| `body` | `.body` | body copy |
| `secondary` | `.subheadline` | metadata, helper text |
| `caption` | `.caption` | badges, timestamps |
| `button` / `compactButton` | `.body.semibold` / `.caption.semibold` | controls |
| `numeric` / `numericCaption` | body + `monospacedDigit` | progress, sizes, durations |
| `header(compact:)` | `.title3` / `.subheadline` | home header, shrinks on dense layouts |

**Numbers always use `monospacedDigit`.** A percentage that changes width every tick makes the
whole row jitter.

---

## 5. Spacing

A 4 pt grid plus the half-steps the layout actually uses.

| Token | pt | Typical use |
| --- | --- | --- |
| `hairline` | 2 | separator inset |
| `xxs` | 4 | icon-to-label |
| `xs` | 6 | badge padding |
| `s` | 8 | tight stack |
| `sm` | 10 | control inner padding |
| `m` | 12 | card padding (`cardContentPadding`) |
| `ml` | 14 | section gap |
| `l` | 18 | screen gutter |
| `xl` | 24 | group separation |
| `xxl` | 32 | empty-state blocks |
| `xxxl` | 40 | wide-layout gutter floor |

The home screen does **not** use these for its proportional layout — that comes from
`HomeLayoutMetrics`, which derives spacing from a scale factor between 0.72 and 1.18. These
constants are for fixed chrome.

---

## 6. Radius

| Token | pt | Use |
| --- | --- | --- |
| `small` | 4 | chips, badges |
| `medium` (= `card`, `control`) | 8 | cards, buttons, banners — 81 call sites |
| `large` | 18 | sheets, popovers |
| `pill` | 999 | fully rounded |

Always `RoundedRectangle(cornerRadius:style: .continuous)`. `.circular` on an 8 pt radius reads as
a machined corner and clashes with the rest.

---

## 7. Motion

| Token | Value | Use |
| --- | --- | --- |
| `quick` | `.easeOut(0.16)` | highlight, colour change |
| `standard` | `.easeOut(0.22)` | layout change — the default |
| `slow` | `.easeInOut(0.35)` | sheet, full-screen |
| `interactive` | `.spring(0.32, 0.86)` | anything the finger drags |

Respect Reduce Motion: gate transforms on `@Environment(\.accessibilityReduceMotion)` and fall back
to a cross-fade. Not yet enforced anywhere — tracked in §10.

---

## 8. Elevation

The palette is dark, so height is carried by surface lightness first and shadow second.

| Token | Value | Use |
| --- | --- | --- |
| `card` | black 18%, r6, y2 | cards that sit on the background |
| `floating` | black 28%, r16, y6 | mini player, popovers |

```swift
.taptionShadow(TaptionElevation.floating)
```

Shadows on a dark UI are nearly invisible; do not use them as the only signal that something floats.

---

## 9. Components

### Card — `ProgressCard`

```
┌─ surface, radius 8, border 1 ─┐
│ padding 12                    │
│ content, maxWidth .infinity   │
└───────────────────────────────┘
```

### Primary button — `PrimaryActionButton`

| State | Fill | Label |
| --- | --- | --- |
| enabled, prominent | `accent` | `accentButtonText` (9.89:1) |
| enabled, secondary | `elevatedSurface` | `primaryText` |
| disabled | `elevatedSurface` | `disabledText` |
| pressed | `accent` at 65% / 18% | — |

Minimum hit target 44 pt, which `HomeLayoutMetrics.controlHeight` already enforces.

### Status banner — `StatusBanner`

| Kind | Accent | Icon |
| --- | --- | --- |
| info | `accent` | info |
| success | `success` | checkmark |
| warning | `reward` | exclamation |
| failure | `coral` | xmark |

Never signal state by colour alone — the banner always carries text.

---

## 10. Adoption rules

1. A new colour needs a **role**, not a hex. If no role fits, add one to `TaptionTheme` and to the
   table in §3.2 in the same commit.
2. A new radius or spacing value needs a reason. Prefer the nearest existing token.
3. Never reference `TaptionColor` outside `TaptionDesignSystem.swift`.
4. Never write `Color(taptionHex:)` in a view. If you are tempted, you are missing a role.
5. Text uses a `TaptionType` token. Numbers use the `numeric` variants.
6. New surfaces must state which of the four device classes they were checked on (§1).

### Known gaps

- `focusBorder` (§3.4 F1) is measured but not applied.
- 32 `Color.white.opacity(…)` sites still to migrate (§3.4 F3).
- Reduce Motion is not honoured yet (§7).
- `ImportBrowserExplorerStyle` (`LoadedFilesPanelView.swift`) keeps its own private palette and
  should fold into `TaptionTheme`.
- No automated guard yet. A future test can assert that no `Color(taptionHex:` appears outside the
  design system file — that is the cheapest way to keep rule 3 true.
