# Taption Encoder

An iOS video encoder. It re-encodes video to H.265/HEVC — on the device's hardware encoder when the
route allows it, and through a software fallback (VLC / FFmpeg) when it does not — and keeps the
result playable, correctly sized, and within the bitrate you asked for.

Published on the App Store as **BOKKI Encoder**.

## Requirements

| | |
|---|---|
| Xcode | **27.1 or newer** |
| iOS deployment target | 18.0 |
| Machine | Apple silicon Mac |

Xcode 27 is not optional. The project uses iOS 27 SDK APIs that do not exist in Xcode 26, and CI
enforces the version with a hard check rather than failing later with an obscure compiler error.

## Build and test

```bash
./scripts/verify.sh          # build + the full unit test suite
./scripts/verify.sh --build  # build only, much faster
```

CI runs the same script, so "verified" has exactly one definition. Two things about this machine
setup are worth knowing before you hit an unexpected wall:

- **`OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'` is required.** `swift-plugin-server` is
  blocked by `sandbox-exec` here, which breaks Observation macro expansion. The flag is already in
  `verify.sh`; add it to any manual `xcodebuild` invocation.
- **Pass `-parallel-testing-enabled NO`.** Parallel test clones occasionally stall this suite.

To gate your own pushes:

```bash
git config core.hooksPath .githooks
```

After that, `git push` runs the build and the tests first and refuses to push on failure. Docs-only
pushes skip automatically. `SKIP_VERIFY=1 git push` bypasses it — say why in the PR if you use it.

## Layout

```
TaptionEncoder/                 app target
  Core/                         codecs, encoding, video core, media inspection
  Features/                     Home, Preview, Encoding, and the rest of the UI
  Shared/                       design system and shared views
TaptionEncoderLiveActivityExtension/
TaptionEncoderThumbnailExtension/
TaptionEncoderTests/            unit tests and media fixtures
Vendor/                         third-party binaries and frameworks
design/                         design system spec and App Store assets
docs/                           code review standard, design system notes
scripts/                        verification and App Store pipelines
```

## Documentation

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — branch, PR and review workflow
- [`docs/code-review/`](docs/code-review/) — the review standard, risk tiers, and checklist
- [`docs/design-system/`](docs/design-system/) — design tokens and usage rules
- [`design/appstore/`](design/appstore/) — screenshot pipeline, including the iPhone Duo sizes

## Notes

- The repository is public and single-maintainer. Review is a 24-hour self-review plus an AI pass
  rather than a second human; see `docs/code-review/README.md` for how that is enforced.
- App Store screenshots are generated and uploaded by the scripts in `scripts/`; the pixel sizes and
  the reason the Duo set has two poses are documented in `design/appstore/duo/README.md`.
