# BOKKI Encoder — New UI Design

Prototype: `design/prototype.html` — open it in a browser and click through the five states
(deep links: `#empty`, `#ready`, `#quality`, `#encoding`, `#done`).
Baseline: `main d1d02d5` plus this session's encoder changes. Scope: `Features/Home/*`.

---

## 1. Diagnosis — why the current screen is hard

The home screen stacks nine layers with unrelated purposes: header · star badge · top banner ·
three import buttons · queue title · file cards (ten information rows each) · Output summary ·
encode button · bottom banner · Exit.

The problem is not "it is busy". The problem is that **the decisions are scattered**. Add a video,
choose the output, and run it are three separate steps, all visible at once, so the screen never
says what to do *now*. On top of that, engine internals — `Path HW`, `Readiness`, `Audio Copy`,
`Probe` — sit where user language belongs.

Three sentences:

1. **Decision points are spread out** — one screen asks three questions.
2. **Parameters instead of outcomes** — people don't want `1920×1080`, they want `6.1 MB`.
3. **Different gestures for decisions of the same rank** — resolution is a menu, size is a popover
   with a slider, format is another menu.

---

## 2. Design principles

| # | Principle | How the screen expresses it |
| --- | --- | --- |
| 1 | **One decision per state** | Empty → Queue → Encoding → Done. Exactly one primary button each |
| 2 | **Show the outcome first** | Every control carries the size it produces |
| 3 | **Thumb zone** | Primary action is a 56pt dock at the bottom; the ad sits **below** it |
| 4 | **Standard iOS gestures only** | Sheets, swipe-to-delete, long-press for detail, share sheet |
| 5 | **Fold the engine vocabulary away** | Diagnostics live under `⋯ > Diagnostics` |

Principle 4 is the core of "aligns with user habits". The moment you teach a new gesture, the user
has to learn a tool — and while they are learning the tool they are not experiencing the app's
value, which is compressing a video quickly.

---

## 3. Screen-by-screen

### 3.1 Empty — one door

```
BOKKI                          ★ 12  ⋯
Compress video
Smaller files, same picture. Everything happens on this device.

┌────────────────────────────────┐
│            ( + )               │  ← the whole card is the tap target (156pt)
│        Add videos              │
│   Up to 4K · HEVC hardware     │
└────────────────────────────────┘

[ Files ]   [ Photos ]   [ Folder ]

RECENT
[thumb]  IMG_4821.MOV              1080p
         12.4 MB ▓▓▓▓▓░░ 6.1 MB

──────────────────────────────────
              AD
```

- Nothing is configurable yet, so nothing is asked. There is one primary target: the card.
- The three secondary paths carry equal weight. **Photos is not hidden behind a menu** — it is in
  practice the most-used route.
- `RECENT` is a one-tap shortcut for returning users. For a first-time user it sits below the fold,
  so it never competes with the primary action.
- The current screen shows a queue title, an Output summary and a disabled button even with zero
  videos loaded.

### 3.2 Queue — the before/after *is* the interface

```
3 videos                       ★ 12  ⋯
34.2 MB → 18.3 MB              47% smaller

[thumb] IMG_4821.MOV              1080p
        4K · 60fps · 0:38
        12.4 MB ▓▓▓▓▓░░░░ 6.1 MB
[thumb] Screen Recording.mov      1080p
        ...
[thumb] IMG_4830.MOV              1080p
        ...

OUTPUT
┌──────────────────────────────────┐
│ QUALITY                          │
│ 1080p · Auto       18.3 MB  ›    │
│                    1920×1080·MP4 │
└──────────────────────────────────┘

[       Compress 3 videos        ]   ← 56pt
              AD
```

A single row answers everything about one file.

| Position | Content | Why |
| --- | --- | --- |
| Row 1 left | File name | Identity |
| Row 1 right | `1080p` (accent) | The resulting resolution only |
| Row 2 | `4K · 60fps · 0:38` | Source summary |
| Row 3 | `12.4 MB ▓▓▓ 6.1 MB` | **The only element that makes the saving visible** |

- The screen title is `34.2 MB → 18.3 MB`. The reason the user came is in the title.
- Output is shown as a **value**, not a gear icon. A gear says "operate the machine"; a value says
  "confirm the choice".
- Swipe a row to delete (the iOS habit). Don't make people hunt for an edit mode.
- Long-press a row → info sheet: codec, path, readiness. This reuses the detail rows already in
  `LoadedFilesPanelView`.

### 3.3 Quality sheet — turn options into outcomes

```
Quality                        Done
( ) Original        3840×2160 · 34.2 MB
(•) 1080p · Auto    1920×1080 · 18.3 MB   ← selected
( ) 1080p · Small   1920×1080 ·  7.4 MB
( ) 720p  · Auto    1280× 720 ·  8.7 MB
( ) Custom size            15 MB · estimate
    ├────●───────────────
    2 MB                34 MB

FILL MODE
[ letterbox ]  [ fill ]  [ stretch ]      ← only when the shapes differ

Advanced  ›
Format · Audio · Frame rate · Profile
```

- Resolution and target size become **one row in one list**. The old job — toggling between two
  controls and imagining the combination — disappears.
- `Custom size` expands its slider **inside its own row**, so the slider has an owner.
- fit/fill/stretch are shown as **shapes**, not words. Those three terms are exactly the ones that
  drift between languages and between mental models.
- Advanced is collapsed by default. Format, audio, frame rate and profile are almost always left
  at their defaults.

### 3.4 Encoding — one number, no controls

```
Cancel                    2 of 3

           68%
      about 24s left
  ████████████░░░░░░

[thumb] Screen Recording.mov      7.6 MB
        ● Encoding 1080p
[thumb] IMG_4830.MOV              4.6 MB   (dim)
        Waiting
```

- The percentage is the largest element on screen. `about 24s left` is more honest than a precise
  second count.
- Settings are hidden while work is happening. Changing them is meaningless, and leaving them
  tappable is worse.
- Cancel is a quiet button in the navigation bar. A red button next to the progress bar invites
  accidents.

### 3.5 Done — hand over the result and get out

```
        ( ✓ )
  Compressed 3 videos
  34.2 MB → 18.3 MB
  47% smaller · 3 saved to Files

  [        Share        ]
  [     Show in Files    ]

  ⓘ 1 file failed · out of storage   Retry
              AD
```

- Hand off, don't celebrate. The saving is stated once, and there are two actions.
- A failed file **stays visible** with its reason and a retry. A silent failure is the worst outcome.
- Share is primary because sending the file is why it was compressed.

---

## 4. Where this meets user habits

| Habit | Evidence | Design |
| --- | --- | --- |
| Bottom primary button | iOS standard (Photos edit, Mail, Notes) | 56pt, docked, above the ad |
| Options in a sheet | iOS Settings and share patterns | Both Quality and info are sheets, using detents |
| Swipe to delete | Universal list grammar | Queue rows |
| Long-press for detail | iOS "more info" | Diagnostics |
| Share sheet | The only standard way to export a file | Done's Share |
| Monospaced digits | Alignment and comparison | Size, progress, ratio all use `monospacedDigit` |

The last row matters more than usual here. Most of this screen is numbers — size, resolution, frame
rate, percentage — and proportional digits change width per glyph, so nothing lines up vertically
and comparison becomes impossible.

---

## 5. Visual language

**Extend** the existing `TaptionTheme`; don't replace it. Brand continuity is itself part of habit.

```
background  #0B1418   (one step deeper than 0F191E, so cards lift)
surface     #14252C   (was 182931)
raised      #1A3038   (was 1D333D)
accent      #5FD3EA   (was 6DD0E5, slightly deeper for contrast)
success     #8FD9BE
coral       #F0A98D   ← narrowed to destructive/warning only
```

- **Reclaim coral from Exit.** Today the largest button on the screen is "quit the app", and it
  happens to wear the warmest colour. When a harmless action looks dangerous, users stop trusting
  colour.
- Radii: card 18 / button 14 / row 12. The existing 8 reads sharper than the surface language iOS 26
  established.
- Surface steps plus 1px hairlines instead of shadows. Large shadows go muddy in a dark UI.
- Motion: state transition 260ms, sheet 340ms, curve `.32,.72,0,1`. Under `Reduce Motion`, transitions
  become cross-fades.

---

## 6. Implementation mapping

| New screen | Existing file | Work |
| --- | --- | --- |
| Empty | `HomeView` (empty branch) | New view, reuse the existing import actions |
| Queue row | `LoadedFilesPanelView` | Collapse to 3 lines; detail moves to the existing sheet |
| Quality sheet | `HomeMenuSheetView` | Rewrite as a list (keep the selection model) |
| Encoding | `EncodingProgressView` | Keep, adjust layout only |
| Done | `OutputSummaryView` | Rewrite |

**The selection model (`selectedOutput`, `resolutionPreset`, `targetSizeMB`) is untouched.** Replacing
views only means the existing tests remain a regression net.

Suggested order:

| Stage | Content | Risk |
| --- | --- | --- |
| P0 | Queue rows down to three pieces of information + Quality as a single list | Low (views only) |
| P0 | Bottom dock (primary button + one ad) | Low |
| P1 | Empty/Done cleanup, Exit moves under `⋯` | Medium (state machine) |
| P1 | Token radii and colour adjustments | Low |
| P2 | New Diagnostics sheet, move the engine vocabulary there | Low |

---

## 7. Accessibility

- Dynamic Type to AX3. Rows grow from 2 lines to 3 and must not clip.
- 44pt minimum tap targets. The `Custom size` slider gets a 44pt-tall track.
- VoiceOver: synthesize the row label as `"IMG_4821, 4K 60 frames, 12.4 megabytes to 6.1 megabytes,
  1080p"`. Read as separate elements, the numbers cannot be compared.
- `47% smaller` is never conveyed by colour alone — the text label always accompanies it.
- `Reduce Motion`: state changes cross-fade, progress updates jump instead of animating.

---

## 8. Anti-goals

- **Don't fold away more settings.** Resolution and size are the product's core value. The thing to
  fold is diagnostics.
- **Don't add more "choose for me".** Auto already does it. What should go is noise, not options.
- **Never put the ad above the primary button.** A mis-tap returns as a deletion, not as revenue.
- **Don't emphasise Exit.** Quitting is not a place where mistakes should happen.

---

## 9. Open decisions

1. **Copy language** — the app ships English strings and `knownRegions` has no `ko`. The prototype
   matches that. A Korean UI requires `Localizable.strings` first, which is a separate piece of work
   from this redesign.
2. **Star reward placement** — the prototype shrinks it to a badge on the right of the navigation bar.
   If rewards need a dedicated surface, an item inside `⋯` keeps home clean.
3. **Recent list** — `RECENT` appears on Empty. If the product policy is not to persist recent
   history, this block is dropped.
