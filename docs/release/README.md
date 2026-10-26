# Release runbook

How a build gets from `main` to App Store review. Written from the 1.1.14 (57) run on 2026-10-26,
with the measured numbers from that run rather than estimates.

Status: **1.1.14 (57) submitted 2026-10-26T16:41Z**, `WAITING_FOR_REVIEW`. Last released:
1.1.13 (56).

---

## 0. What a release touches

| Surface | Where | Count |
| --- | --- | --- |
| `MARKETING_VERSION` | `TaptionEncoder.xcodeproj/project.pbxproj` | 8 |
| `CURRENT_PROJECT_VERSION` | same file | 8 |
| `CFBundleShortVersionString` / `CFBundleVersion` | 3 × `Info.plist`, all indirected | 0 edits |

The eight are the project-level Debug/Release pair plus Debug/Release for each of the three targets.
The `Info.plist` files read `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`, so they are never
edited by hand — but that also means a partial bump silently produces an archive whose extensions
disagree with the app. Bump all sixteen lines or none.

```bash
grep -c "MARKETING_VERSION = 1.1.13;"   TaptionEncoder.xcodeproj/project.pbxproj   # expect 8
grep -c "CURRENT_PROJECT_VERSION = 56;" TaptionEncoder.xcodeproj/project.pbxproj   # expect 8
```

## 1. Check App Store Connect before bumping

A version record may already exist. **1.1.14 was created on 2026-10-24 and sat in
`PREPARE_FOR_SUBMISSION` with no build attached, no `whatsNew`, and review notes still naming
1.1.13 (56).** If a record exists, `CFBundleShortVersionString` has to equal that string exactly or
the upload will not attach to it — the version in the project is not free to choose.

Query it before editing anything:

```bash
python3 scripts/upload-appstore-screenshots.py --dir design/appstore/duo --dry-run   # validates the ASC key
```

then `GET /v1/apps/6780777838/appStoreVersions?fields[appStoreVersions]=versionString,appStoreState`
through the same helpers (`scripts/upload-appstore-screenshots.py` already exposes `token()`,
`call()`, `find_app()` and `editable_version()` — import it instead of rewriting the JWT signing).

## 2. Bump, gate, merge

A version bump is **T3** — two constants, nothing reachable at runtime — so it takes CI and no
24-hour cooldown (`docs/code-review/README.md` §2). Keep it as its own PR so that stays true; adding
assets or code to the same PR changes the tier.

Measured on 1.1.14:

| Step | Result |
| --- | --- |
| `./scripts/verify.sh` (pre-push hook) | 487 tests, 5 skipped, 0 failures, **619 s** |
| CI (`build-and-test`) | green, 6 m 48 s |
| Merge | squash, `c65cd80` |

619 s against a 300 s baseline is the machine, not the change: a parallel session was running a
benchmark suite with load average 271. The discriminator is the one in
`docs/code-review/README.md` — total time over 5× baseline with zero assertion failures is
environmental. Check `uptime` before believing a timing failure.

## 3. Archive and export

**Pin `-derivedDataPath`.** `prepare_relink_materials.sh` needs the release object files, the
`LinkFileList`, the dependency info and the `xcactivitylog`, and those only exist under a
DerivedData tree you can name afterwards:

```
<dd>/Build/Intermediates.noindex/ArchiveIntermediates/<project>/IntermediateBuildFilesPath/
    <target>.build/Release-iphoneos/<target>.build/Objects-normal/arm64/
```

```bash
xcodebuild archive \
  -project TaptionEncoder.xcodeproj \
  -scheme TaptionEncoder \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath  build/release/1.1.14/TaptionEncoder.xcarchive \
  -derivedDataPath /tmp/taption-release/1.1.14/dd \
  -allowProvisioningUpdates \
  -skipPackagePluginValidation \
  COMPILER_INDEX_STORE_ENABLE=NO \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'

xcodebuild -exportArchive \
  -archivePath build/release/1.1.14/TaptionEncoder.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/release/1.1.14/export \
  -allowProvisioningUpdates
```

`ExportOptions.plist` is not in the repository. The one that worked:

```xml
<key>method</key>                       <string>app-store-connect</string>
<key>destination</key>                  <string>export</string>
<key>signingStyle</key>                 <string>automatic</string>
<key>teamID</key>                       <string>4FWG8XXYM7</string>
<key>uploadSymbols</key>                <true/>
<key>manageAppVersionAndBuildNumber</key> <false/>
```

`manageAppVersionAndBuildNumber` must be **false**. With it true, Xcode is free to renumber the
build, and the archive you validated is no longer the build you shipped.

Measured: archive + export 7 m 40 s. The export directory contains `Taption Encoder.ipa`,
`DistributionSummary.plist`, `ExportOptions.plist` and `Packaging.log`.

### The thinning report is gone

**`-exportArchive` on Xcode 27.1 does not produce `App Thinning Size Report.txt`.** The export above
wrote four files and no report. The report now exists only in Xcode Organizer for an uploaded build.
This matters because `Vendor/OpenSourceCompliance/verify_public_distribution_gate.sh` requires it —
see §7.

## 4. Verify the IPA before uploading

```bash
unzip -q "export/Taption Encoder.ipa" -d /tmp/ipacheck
/usr/libexec/PlistBuddy -c "Print:CFBundleShortVersionString" "/tmp/ipacheck/Payload/Taption Encoder.app/Info.plist"
/usr/libexec/PlistBuddy -c "Print:CFBundleVersion"            "/tmp/ipacheck/Payload/Taption Encoder.app/Info.plist"
```

Expect the marketing version, the build number, and `com.taption.encoder`. `DistributionSummary.plist`
is the second opinion: it names the signing certificate and the embedded extension builds, so a
mismatched extension shows up there rather than in review.

## 5. Upload

```bash
xcrun altool --upload-app -f "export/Taption Encoder.ipa" -t ios \
  --apiKey "$ASC_API_KEY" --apiIssuer "$ASC_API_ISSUER"
```

`altool` lives at `/Applications/Xcode.app/Contents/Developer/usr/bin/altool`; `xcrun --find altool`
resolves it, a bare `altool` does not. The key must be at
`~/.appstoreconnect/private_keys/AuthKey_<ASC_API_KEY>.p8`. Success prints a delivery UUID — that
UUID **is** the build id in the API, so keep it.

Measured: 28.6 MB, 5.9 s transfer, then **3 m 45 s** to `processingState = VALID`. Poll
`GET /v1/builds?filter[app]=…&filter[version]=<build>&fields[builds]=version,processingState`
rather than guessing.

## 6. Fill the record

Four edits, in this order. Screenshot sets are **per localization** — a set uploaded to `en-US` does
not appear in `ko`, and 1.1.14 shipped with the Duo set only in `en-US` until it was mirrored.

| Edit | Call | Note |
| --- | --- | --- |
| Attach the build | `PATCH /v1/appStoreVersions/{id}/relationships/build` | body `{"data":{"type":"builds","id":…}}` |
| What's New | `PATCH /v1/appStoreVersionLocalizations/{id}` | one call per locale |
| Review notes | `PATCH /v1/appStoreReviewDetails/{id}` | keep the previous release line, prepend the new one |
| Screenshots | `POST /v1/appScreenshotSets` then the reserve/upload/commit flow in `scripts/upload-appstore-screenshots.py` | pass `--locale` |

**A relationship `PATCH` answers `204 No Content`.** It is a success. Checking only for 200/201 makes
a build that did attach look like it failed, which is exactly what happened on the first 1.1.14 run.

## 7. Submit

`POST /v1/appStoreVersionSubmissions` is retired — it answers
`403 FORBIDDEN_ERROR … does not allow 'GET'`. The current flow is three calls:

```text
POST  /v1/reviewSubmissions            {platform: IOS, app: <app id>}
POST  /v1/reviewSubmissionItems        {reviewSubmission: …, appStoreVersion: …}
PATCH /v1/reviewSubmissions/{id}       {submitted: true}      → WAITING_FOR_REVIEW
```

Reuse an open submission in `READY_FOR_REVIEW` or `IN_PROGRESS` instead of creating a second one.
`releaseType` is `AFTER_APPROVAL`, so the version goes live on approval with no further action.

## 8. The open-source distribution gate

`Vendor/OpenSourceCompliance/verify_public_distribution_gate.sh` wants five inputs: the xcarchive,
the distribution IPA, the corresponding-source bundle, the relinking bundle and the App Thinning
Size Report. On 1.1.14 **only three could be produced.**

- **Relinking bundle — produced.** `prepare_relink_materials.sh` with the §3 paths gave
  `RelinkMaterials.tar.xz`, 88 objects, 4.4 MB, containing all seven required members. It has to be
  captured before the DerivedData tree is deleted; the objects are not reproducible afterwards
  without a full rebuild.
- **Corresponding-source bundle — cannot be produced here.** The script needs
  `--contrib-tarballs-dir` holding all 56 archives named in
  `libvlc-ios-contrib-manifest.tsv`. None are on disk, and the manifest records filenames and
  sha512 digests only — **no upstream URLs** — so there is no fetch path either. A Spotlight search
  finds exactly one of them, `dav1d-1.5.2.tar.xz`, inside an unrelated project.
- **App Thinning Size Report — cannot be produced here.** See §3.

The gate is fail-closed on both, so it currently cannot pass from a command line. This is not a
regression in 1.1.14: 1.1.13 (56) shipped in the same state. Closing it means adding upstream URLs
to the manifest and generating the size report from Organizer.

Under the owner's 2026-10-06 instruction, an external legal approval record is not a prerequisite for
upload or submission (`Vendor/OpenSourceCompliance/README.md`), so `--legal-approval` is omitted;
that changes nothing about the license obligations.

## 9. Artifacts

`build/release/<version>/` is gitignored and is where the run above left its evidence:

| File | Size |
| --- | --- |
| `TaptionEncoder.xcarchive` | 74 MB |
| `export/Taption Encoder.ipa` | 27 MB |
| `export/DistributionSummary.plist` | — |
| `RelinkMaterials.tar.xz` | 4.4 MB |

The DerivedData tree used for the archive is disposable once the relinking bundle exists.

## 10. After it goes live

The submission state is the source of truth, not the App Store listing page. A rejection arrives as
an `appStoreVersions` state change plus a resolution centre message; the review notes in §6 are what
a reviewer reads first, so keep them describing the build that was actually uploaded.
