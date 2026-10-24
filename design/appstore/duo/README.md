# iPhone Duo screenshots

Images at the exact pixel sizes App Store Connect requires for `APP_IPHONE_DUO`.

| File | Pose | Pixels | Points | Display | Source |
| --- | --- | --- | --- | --- | --- |
| `duo-outer-1398x2034.png` | folded | 1398 × 2034 | 466 × 678 | 5.4", 460 ppi | rendered `HomeView` |
| `duo-inner-2007x2853.png` | unfolded | 2007 × 2853 | 669 × 951 | 7.6", 430 ppi | rendered `HomeView` |
| `duo-outer-1398x2034-simulator.png` | folded | 1398 × 2034 | 466 × 678 | 5.4", 460 ppi | **real capture**, Duo simulator |

## Which one to submit

The **render** is the listing candidate. The **real capture** is evidence: it proves the app really
lays out as a scaled-down phone screen on the folded panel, from the actual simulator rather than
from a test host.

The real capture is not the better image, and that is the finding worth recording: on a booted
simulator there is no reliable moment when the screen is presentable.

- the folder-access sheet ("Allow folder access" / "Connect folder") is gated by an in-memory flag,
  so it appears on **every** launch, and it fires anywhere between 2 s and 15 s;
- the ad slot fills with a real AdMob **test banner** ("Nice job!", "Test mode", "test ad.") within
  about 3 s. Before that it reads "Advertisement", which is also not shippable.

So the clean frame that the capture below happens to have is a matter of luck, not of parameters.
Getting a genuinely presentable frame needs a human in the Simulator, or a product change (a
screenshot launch argument that seeds fixtures and hides the ad slots) — see below.

## Status of the toolchain

Xcode **27.1** is installed and the iOS 27.1 runtime is downloaded, so the Duo device type exists
and the folded pose captures headlessly:

```bash
xcrun simctl list devicetypes | grep -i duo
scripts/capture-duo-screenshots.sh --pose outer
```

The device **boots folded**, and `simctl` has no fold control — there is no such subcommand, and
neither the `simctl` binary nor `CoreSimulator` exports any fold/pose symbol. The unfolded panel is
present in `simctl io enumerate` (it reports a 2007 × 2853 display) but it is **black** while the
device is folded. So the inner pose still needs one unfold in the Simulator window:

```bash
scripts/capture-duo-screenshots.sh --pose inner
```

## What the capture script had to work around

Five things made this fail in ways that were not obvious:

1. **Device selection by name.** It matched devices called `iPhone Duo` and so ignored a Duo the
   developer had renamed, silently creating a second one. It now matches the device *type* through
   `simctl list devices --json`.
2. **Display selection.** The Duo exposes both panels and `simctl io screenshot` without `--display`
   picks whichever it likes — the same device answered `LCD` on one boot and `LCD-1` on the next. The
   script picks the display whose native size matches the pose.
3. **A stale display UUID.** The UUID is not stable across a boot and a cold boot registers the
   display late, so it is re-read on every retry rather than once.
4. **The sandbox.** `simctl` runs as its own process and is refused write access to the checkout
   (`NSCocoaErrorDomain 513 … You don't have permission`). The shot lands in `$TMPDIR` and the shell
   moves it into place.
5. **Alpha.** The default mask policy writes the panel's rounded corners as premultiplied alpha, and
   App Store Connect rejects a PNG with an alpha channel. `--mask=black` keeps it opaque and
   lossless, so no JPEG round trip is needed.

A device whose data container reports `Data Migration Failed` answers `simctl io` intermittently and
then fails outright; the script erases and reboots it.

## Upload

```bash
python3 scripts/upload-appstore-screenshots.py --dir design/appstore/duo --dry-run
python3 scripts/upload-appstore-screenshots.py --dir design/appstore/duo --version 1.1.14
```

The upload needs a version in `PREPARE_FOR_SUBMISSION`; a released version is read-only, which is
why the command names the next version to create. A set containing only the outer pose validates —
the missing inner pose is a warning, not an error.

## If a repeatable pipeline matters

The app has no URL scheme and no launch argument that seeds the queue (`CFBundleURLSchemes` and
`ProcessInfo.arguments` are both unused), and `simctl` has no tap command. A pipeline would need a
product change, roughly:

- a launch argument (`-TaptionScreenshotSeed <path>`) that loads fixture clips into the queue on
  start;
- a way to suppress the ad slots and the folder-access sheet in that mode.

Until then, a populated listing image has to be made by hand: import a few clips, dismiss the sheet,
then `xcrun simctl io <udid> screenshot --mask=black <file>`.

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
