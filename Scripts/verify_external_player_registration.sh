#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_PLIST="$ROOT_DIR/TaptionEncoder/Info.plist"
APP_PATH="${TAPTION_ENCODER_APP_PATH:-}"

plist_args=("$SOURCE_PLIST")

if [[ -z "$APP_PATH" ]]; then
  APP_PATH="$(ls -d "$HOME/Library/Developer/Xcode/DerivedData"/TaptionEncoder-*/Build/Products/Debug-iphonesimulator/Taption\ Encoder.app 2>/dev/null | tail -n 1 || true)"
fi

if [[ -n "$APP_PATH" && -d "$APP_PATH" && -f "$APP_PATH/Info.plist" ]]; then
  plist_args+=("$APP_PATH/Info.plist")
fi

python3 - "${plist_args[@]}" <<'PY'
import plistlib
import sys
from pathlib import Path

required_document_types = {
    "com.taption.legacy-video",
    "public.audiovisual-content",
    "public.movie",
    "public.video",
    "public.mpeg-4",
    "com.apple.quicktime-movie",
    "public.avi",
    "org.webmproject.webm",
    "public.mpeg",
    "public.mpeg-2-video",
    "public.mpeg-2-transport-stream",
    "public.avchd-mpeg-2-transport-stream",
}
required_legacy_extensions = {
    "avi",
    "webm",
    "mkv",
    "ts",
    "mts",
    "m2ts",
    "m2t",
    "tp",
    "trp",
    "tod",
    "lrf",
    "nut",
    "h261",
    "h263",
    "h264",
    "h265",
    "hevc",
    "av1",
    "mpg",
    "mpeg",
    "m1v",
    "m2v",
    "vc1",
}

def fail(path: Path, message: str) -> None:
    print(f"error: {path}: {message}", file=sys.stderr)
    raise SystemExit(1)

for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    with path.open("rb") as handle:
        plist = plistlib.load(handle)

    document_types = plist.get("CFBundleDocumentTypes")
    if not isinstance(document_types, list) or not document_types:
        fail(path, "CFBundleDocumentTypes is missing or empty")

    content_types = set()
    handler_ranks = set()
    roles = set()
    for document_type in document_types:
        content_types.update(document_type.get("LSItemContentTypes") or [])
        handler_ranks.add(document_type.get("LSHandlerRank"))
        roles.add(document_type.get("CFBundleTypeRole"))

    missing_content_types = required_document_types.difference(content_types)
    if missing_content_types:
        fail(path, f"missing video document content types: {sorted(missing_content_types)}")
    if handler_ranks != {"Owner"}:
        fail(path, f"document handler ranks must all be Owner, got {sorted(handler_ranks)}")
    if roles != {"Viewer"}:
        fail(path, f"document type roles must all be Viewer, got {sorted(roles)}")

    for key in (
        "LSSupportsOpeningDocumentsInPlace",
        "UIFileSharingEnabled",
        "UISupportsDocumentBrowser",
    ):
        if plist.get(key) is not True:
            fail(path, f"{key} must be true")

    exported = plist.get("UTExportedTypeDeclarations") or []
    legacy = next(
        (
            declaration
            for declaration in exported
            if declaration.get("UTTypeIdentifier") == "com.taption.legacy-video"
        ),
        None,
    )
    if legacy is None:
        fail(path, "missing com.taption.legacy-video exported UTI")

    conformance = set(legacy.get("UTTypeConformsTo") or [])
    if not {"public.movie", "public.video"}.issubset(conformance):
        fail(path, "legacy video UTI must conform to public.movie and public.video")

    tag_spec = legacy.get("UTTypeTagSpecification") or {}
    extensions = set(tag_spec.get("public.filename-extension") or [])
    missing_extensions = required_legacy_extensions.difference(extensions)
    if missing_extensions:
        fail(path, f"missing legacy video filename extensions: {sorted(missing_extensions)}")
    dotted_extensions = sorted(extension for extension in extensions if extension.startswith("."))
    if dotted_extensions:
        fail(path, f"filename extensions must not start with dots: {dotted_extensions}")

    print(f"external player registration verified: {path}")
PY
