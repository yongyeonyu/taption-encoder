# iPhone Duo screenshots

Two images, at the exact pixel sizes App Store Connect requires for `APP_IPHONE_DUO`.

| File | Pose | Pixels | Points | Display |
| --- | --- | --- | --- | --- |
| `duo-outer-1398x2034.png` | folded | 1398 × 2034 | 466 × 678 | 5.4", 460 ppi |
| `duo-inner-2007x2853.png` | unfolded | 2007 × 2853 | 669 × 951 | 7.6", 430 ppi |

## Status: rendered, not captured

Xcode 27.0 — the only version installed on the build Mac — ships no iPhone Duo simulator device
type, and the iOS 27.0 runtime has no geometry for the panel. Xcode 27.1 is the first release with
one. So there is nothing to boot and `simctl io screenshot` cannot produce these.

What is here instead is the real `HomeView` hosted at the two point sizes and rasterised on a
simulator (`scripts/render-duo-screenshots.sh`, test
`DuoAppStoreScreenshotTests.testRenderDuoScreenshotsWhenRequested`). The layout, type scale,
colours and copy are the app's own. What is missing is everything the system draws around it:

- no status bar, no Dynamic Island
- no device bezel
- the ad slots read "Advertisement" because the SDK has no inventory in a test process
- the queue is empty, so the screen shows the empty state rather than real files

**Do not upload these as the final listing images.** They are a layout reference and a size check.
Replace them with real captures before submitting:

```bash
# requires Xcode 27.1
xcrun simctl list devicetypes | grep -i duo
scripts/capture-duo-screenshots.sh --pose both
```

Then upload:

```bash
python3 scripts/upload-appstore-screenshots.py --dir design/appstore/duo --dry-run
python3 scripts/upload-appstore-screenshots.py --dir design/appstore/duo --version 1.1.14
```

The upload needs a version in `PREPARE_FOR_SUBMISSION`; a released version is read-only, which is
why the command above names the next version to create.

## Why these sizes

Apple's screenshot specification table lists the Duo display type as accepting both poses in a
single set:

- outer 1398 × 2034 (portrait), 2034 × 1398 (landscape)
- inner 2007 × 2853 (portrait), 2853 × 2007 (landscape)

Portrait only here — the app's home screen is portrait on the folded pose, and the unfolded
portrait is the shape the store shows first.

Note the inner screenshot canvas (2007 × 2853) is 6.9 % larger than the panel's native pixel count
(1878 × 2670). That is Apple's number, not a rounding error on our side; the layout is therefore
rendered at 669 × 951 pt rather than 626 × 890 pt.
