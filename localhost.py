#!/usr/bin/env python3
"""Local dev server for Kitty Hub.

Serves the built .lua files to your executor, and rebuilds them from src/ on
demand so the edit -> re-execute loop is just "save, run again in Roblox".

    python localhost.py                 # http://127.0.0.1:8000
    python localhost.py 8080            # different port
    python localhost.py --lan           # also reachable from your phone
    python localhost.py --no-build      # serve files as-is, never rebuild
"""

from __future__ import annotations

import datetime
import http.server
import socket
import socketserver
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
BUILD = ROOT / "build.py"

RESET, DIM, GREEN, YELLOW, RED, CYAN = (
    "\033[0m", "\033[2m", "\033[32m", "\033[33m", "\033[31m", "\033[36m",
)


def stale_module(name: str) -> bool:
    """True when src/<name>/ or src/_shared/ changed since <name>.lua was built."""
    module_dir = SRC / name
    built = ROOT / f"{name}.lua"
    if not module_dir.is_dir():
        return False
    if not built.exists():
        return True
    sources = list(module_dir.glob("*.lua")) + list((SRC / "_shared").glob("*.lua"))
    newest = max((p.stat().st_mtime for p in sources), default=0)
    return newest > built.stat().st_mtime


def rebuild(name: str) -> tuple[bool, str]:
    result = subprocess.run(
        [sys.executable, str(BUILD), name],
        capture_output=True, text=True, cwd=ROOT,
    )
    output = (result.stdout + result.stderr).strip()
    return result.returncode == 0, output


def lan_ip() -> str:
    """Best-effort local address, for pointing a phone at this server."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def make_handler(auto_build: bool):
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(ROOT), **kwargs)

        # Executors cache aggressively, and so do some proxies. The loader adds
        # a cache-buster too; between the two, a stale script is very unlikely.
        def end_headers(self):
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
            self.send_header("Access-Control-Allow-Origin", "*")
            super().end_headers()

        def do_GET(self):
            requested = self.path.split("?", 1)[0].lstrip("/")

            if auto_build and requested.endswith(".lua"):
                name = requested[:-4]
                if stale_module(name):
                    self.note(f"{name}: sources changed, rebuilding", YELLOW)
                    ok, output = rebuild(name)
                    for line in output.splitlines():
                        self.note("  " + line.strip(), GREEN if ok else RED)
                    if not ok:
                        self.send_error(500, "build failed")
                        return

            super().do_GET()

        def note(self, message: str, color: str = ""):
            stamp = datetime.datetime.now().strftime("%H:%M:%S")
            print(f"{DIM}[{stamp}]{RESET} {color}{message}{RESET}", file=sys.stderr)

        def log_message(self, fmt, *args):
            message = fmt % args if args else fmt
            color = GREEN if " 200 " in message or '" 200' in message else YELLOW
            if " 404 " in message or " 500 " in message:
                color = RED
            self.note(f"{self.address_string()}  {message}", color)

    return Handler


def main() -> int:
    argv = sys.argv[1:]
    auto_build = "--no-build" not in argv
    lan = "--lan" in argv
    positional = [a for a in argv if not a.startswith("-")]

    port = 8000
    if positional:
        try:
            port = int(positional[0])
        except ValueError:
            print(f"{RED}Error: invalid port {positional[0]!r} — must be an integer{RESET}")
            return 1
        if not 1 <= port <= 65535:
            print(f"{RED}Error: port must be 1-65535, got {port}{RESET}")
            return 1

    host = "0.0.0.0" if lan else "127.0.0.1"

    socketserver.TCPServer.allow_reuse_address = True
    try:
        httpd = socketserver.TCPServer((host, port), make_handler(auto_build))
    except OSError as e:
        print(f"{RED}Error: could not bind {host}:{port} — {e}{RESET}")
        print(f"{DIM}Another server may already be running on this port.{RESET}")
        return 1

    addresses = [f"http://localhost:{port}"]
    if lan:
        addresses.append(f"http://{lan_ip()}:{port}")

    print()
    print(f"  {CYAN}Kitty Hub dev server{RESET}")
    print(f"  {DIM}serving {ROOT}{RESET}")
    print(f"  {DIM}auto-rebuild: {'on' if auto_build else 'off'}{RESET}")
    print()
    for address in addresses:
        print(f'  loadstring(game:HttpGet("{address}/kittyhub.lua"))()')
    print()
    print(f"  {DIM}Ctrl+C to stop{RESET}")
    print()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print(f"\n{DIM}  stopped{RESET}")
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
