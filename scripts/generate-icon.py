#!/usr/bin/env python3
"""Generate the Codex+国产模型免登 macOS app icon from logo.svg."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

try:
    import cairosvg
    HAS_CAIRO = True
except ImportError:
    HAS_CAIRO = False

ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets"
SVG_FILE = ASSET_DIR / "logo.svg"
ICONSET = ASSET_DIR / "app-icon.iconset"
ICNS = ASSET_DIR / "app-icon.icns"


def svg_to_png(svg_path: Path, png_path: Path, size: int) -> None:
    """Convert SVG to PNG at the given size."""
    if HAS_CAIRO:
        cairosvg.svg2png(
            url=str(svg_path),
            write_to=str(png_path),
            output_width=size,
            output_height=size,
        )
    elif shutil.which("rsvg-convert"):
        subprocess.run(
            ["rsvg-convert", "-w", str(size), "-h", str(size), str(svg_path), "-o", str(png_path)],
            check=True,
        )
    elif shutil.which("inkscape"):
        subprocess.run(
            ["inkscape", str(svg_path), "--export-filename", str(png_path),
             f"--export-width={size}", f"--export-height={size}"],
            check=True,
        )
    elif shutil.which("qlmanage"):
        # macOS fallback: use Quick Look to render SVG
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            subprocess.run(
                ["qlmanage", "-t", "-s", str(size), "-o", tmpdir, str(svg_path)],
                check=True, capture_output=True,
            )
            # qlmanage outputs as filename.svg.png
            rendered = Path(tmpdir) / f"{svg_path.name}.png"
            if rendered.exists():
                shutil.copy2(rendered, png_path)
            else:
                raise RuntimeError(f"qlmanage did not produce expected output at {rendered}")
    else:
        print("需要安装 cairosvg (pip install cairosvg) 或 rsvg-convert 或 inkscape", file=sys.stderr)
        sys.exit(1)


def save_iconset() -> None:
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir(parents=True)

    outputs = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for filename, size in outputs:
        svg_to_png(SVG_FILE, ICONSET / filename, size)


def main() -> int:
    if not SVG_FILE.exists():
        print(f"SVG not found: {SVG_FILE}", file=sys.stderr)
        return 1

    save_iconset()

    if not shutil.which("iconutil"):
        print("iconutil is required on macOS", file=sys.stderr)
        return 2

    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    print(ICNS)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
