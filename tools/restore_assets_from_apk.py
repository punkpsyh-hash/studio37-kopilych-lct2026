"""Restore Flutter assets from the exact contest APK before a local build.

Usage: python tools/restore_assets_from_apk.py <downloaded-apk>
The APK is published as an asset of release v0.5.4-lct2026.
"""

from hashlib import sha256
from pathlib import Path, PurePosixPath
from sys import argv, exit
from zipfile import ZipFile

EXPECTED = "1969D91D24BD99660808DF21AA804BE75152C776BEE836365B9C8BA32F229C75"
PREFIX = "assets/flutter_assets/assets/"
ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "app/assets"


def main() -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    apk = Path(argv[1]).expanduser().resolve()
    if not apk.is_file():
        print(f"APK not found: {apk}")
        return 2
    digest = sha256(apk.read_bytes()).hexdigest().upper()
    if digest != EXPECTED:
        print(f"Wrong APK SHA-256: {digest}; expected {EXPECTED}")
        return 2
    written = 0
    with ZipFile(apk) as z:
        bad = z.testzip()
        if bad:
            print(f"Corrupt APK ZIP entry: {bad}")
            return 2
        for item in z.infolist():
            if item.is_dir() or not item.filename.startswith(PREFIX):
                continue
            relative = PurePosixPath(item.filename[len(PREFIX):])
            if not relative.parts or relative.is_absolute() or ".." in relative.parts:
                raise ValueError(f"Unsafe asset path: {item.filename}")
            target = DEST.joinpath(*relative.parts)
            if not target.resolve().is_relative_to(DEST.resolve()):
                raise ValueError(f"Unsafe asset target: {item.filename}")
            data = z.read(item)
            if target.exists():
                if target.read_bytes() != data:
                    raise ValueError(f"Existing source differs from APK: {target}")
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            written += 1

    # Every explicit Flutter asset in pubspec must now be present.
    missing = []
    for line in (ROOT / "app/pubspec.yaml").read_text(encoding="utf-8").splitlines():
        asset = line.strip().removeprefix("- ")
        if not asset.startswith("assets/"):
            continue
        if not (ROOT / "app" / asset).exists():
            missing.append(asset)
    if missing:
        print("Missing assets referenced by pubspec:", *missing, sep="\n  ")
        return 2
    print(f"Restored {written} files from verified APK. All pubspec assets exist.")
    return 0


if __name__ == "__main__":
    exit(main())
