"""Verify that an exported APK has a plausible Android package structure."""
import sys
import zipfile
from pathlib import Path
apk = Path(sys.argv[1] if len(sys.argv) > 1 else "build/PerimeterZero-debug.apk")
if not apk.is_file() or apk.stat().st_size < 1_000_000:
    sys.exit(f"Invalid/missing APK or unexpectedly small file: {apk}")
with zipfile.ZipFile(apk) as bundle:
    names = set(bundle.namelist())
    for required in ("AndroidManifest.xml", "classes.dex"):
        if required not in names:
            sys.exit(f"APK is missing {required}")
    if not any(n.startswith("lib/arm64-v8a/") and n.endswith(".so") for n in names):
        sys.exit("APK does not contain arm64 Android native code")
    bad = bundle.testzip()
    if bad:
        sys.exit(f"Corrupt entry in APK: {bad}")
print(f"APK verified: {apk} ({apk.stat().st_size:,} bytes)")
