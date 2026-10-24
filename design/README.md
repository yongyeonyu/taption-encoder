# Design notes

Working design material for the home screen. None of this is shipped UI — it is the reasoning
behind it, kept because the reasons matter more than the mockup.

| File | What it is |
| --- | --- |
| `ui-redesign.md` | The English design write-up: diagnosis of the current home screen, principles, the five states, and what was deliberately left out. |
| `ui-proposal.md` | An earlier Korean proposal that simplifies the same screen. Kept because its layer-by-layer inventory is still the clearest description of what is on screen today. |
| `prototype.html` | Clickable prototype, single file, no build step. Open it in a browser. Deep links: `#empty`, `#ready`, `#quality`, `#encoding`, `#done`. |
| `duo-unfolded-744x1133.png` | Screenshot of the app at 744×1133 pt — the unfolded foldable case. Rendered on an iPad mini A17 Pro simulator, because Xcode 27.0 has no Duo device type. |

## Status

The prototype is a proposal, not a spec. The foldable half of it is implemented (see the layout
section in `docs/code-review/README.md` and `HomeLayoutMetrics`); the rest is not scheduled.
