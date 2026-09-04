#!/usr/bin/env python3
"""Assemble src/<module>/*.lua into a single loadable script.

Roblox executors run one chunk from one HTTP request, so the shipped file has
to be self-contained. Keeping the sources split and concatenating here is what
lets the project stay readable without giving that up.

Usage:
    python build.py                # build every module in src/
    python build.py mm2            # build just src/mm2 -> mm2.lua
    python build.py --check        # build, then syntax-check with node check.js
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
SHARED = "_shared"

BANNER = """\
-- ============================================================================
--
--   ██╗  ██╗██╗████████╗████████╗██╗   ██╗    ██╗  ██╗██╗   ██╗██████╗
--   ██║ ██╔╝██║╚══██╔══╝╚══██╔══╝╚██╗ ██╔╝    ██║  ██║██║   ██║██╔══██╗
--   █████╔╝ ██║   ██║      ██║    ╚████╔╝     ███████║██║   ██║██████╔╝
--   ██╔═██╗ ██║   ██║      ██║     ╚██╔╝      ██╔══██║██║   ██║██╔══██╗
--   ██║  ██╗██║   ██║      ██║      ██║       ██║  ██║╚██████╔╝██████╔╝
--   ╚═╝  ╚═╝╚═╝   ╚═╝      ╚═╝      ╚═╝       ╚═╝  ╚═╝ ╚═════╝ ╚═════╝
--
--   {title}
--   build {build}  ·  {stamp}
--
--   GENERATED FILE — do not edit directly.
--   Sources live in src/{module}/ ; rebuild with `python build.py`.
--
-- ============================================================================

"""

TITLES = {
    "mm2": "Murder Mystery 2 Script",
    "jailbreak": "Jailbreak Script",
    "generic": "Universal fallback module",
}


def version_of(files: list[Path]) -> str:
    """Read the Version field out of the prelude so the banner cannot drift."""
    for path in files:
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped.startswith("Version") and "=" in stripped:
                return stripped.split("=", 1)[1].strip().strip('",')
    return "0.0.0"


def sources_for(name: str) -> list[Path]:
    """Shared sources plus the module own ones, ordered by numeric prefix.

    The two directories interleave: a game defaults file has to land before
    the shared config store reads it, and its Game table before the shared
    movement and visuals look for one.
    """
    module_dir = SRC / name
    if not module_dir.is_dir():
        raise SystemExit(f"no such module directory: {module_dir}")
    files = list(module_dir.glob("*.lua")) + list((SRC / SHARED).glob("*.lua"))
    files.sort(key=lambda p: p.name)
    return files


def build_module(name: str) -> Path:
    files = sources_for(name)
    if not files:
        raise SystemExit(f"no .lua sources for module {name}")

    body_parts: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8").rstrip()
        label = f"{path.parent.name}/{path.name}"
        body_parts.append(
            f"-- ─── src/{label} "
            + "─" * max(0, 58 - len(label))
            + f"\n\n{text}\n"
        )
    body = "\n".join(body_parts)

    digest = hashlib.sha256(body.encode("utf-8")).hexdigest()[:8]
    header = BANNER.format(
        title=TITLES.get(name, name),
        build=f"{version_of(files)}+{digest}",
        stamp=datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        module=name,
    )

    out = ROOT / f"{name}.lua"
    out.write_text(header + body, encoding="utf-8")

    lines = (header + body).count("\n") + 1
    print(f"  {out.name:<14} {len(files)} sources -> {lines} lines, {out.stat().st_size:,} bytes  [{digest}]")
    return out


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    check = "--check" in sys.argv

    if not SRC.is_dir():
        raise SystemExit("no src/ directory next to build.py")

    modules = args or sorted(
        p.name for p in SRC.iterdir() if p.is_dir() and p.name != SHARED
    )
    print(f"building {len(modules)} module(s):")

    outputs = [build_module(name) for name in modules]

    if check:
        checker = ROOT / "check.js"
        if not checker.exists():
            print("  (skipping syntax check — check.js not found)")
            return 0
        result = subprocess.run(
            ["node", str(checker), *(str(p) for p in outputs)],
            capture_output=True,
            text=True,
        )
        print(result.stdout.strip())
        if result.returncode != 0:
            print(result.stderr.strip())
            return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
