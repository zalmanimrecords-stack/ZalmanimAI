"""Extract init_db into routes.py from archived monolith snapshot."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROUTES = ROOT / "apps/server/app/api/routes.py"
AUTH_MARKER = '@router.post("/auth/login"'

SOURCES = [
    Path(r"C:\Users\simonr\AppData\Local\Temp\routes_head.py"),
    ROOT / "apps/server/app/api/routes.py.bak",
]


def read_lines(path: Path) -> list[str]:
    for encoding in ("utf-8", "utf-16", "utf-16-le", "cp1252", "latin-1"):
        try:
            return path.read_text(encoding=encoding).splitlines()
        except (UnicodeDecodeError, OSError):
            continue
    raise SystemExit(f"Could not read {path}")


def find_init_block(lines: list[str]) -> list[str]:
    start = next(i for i, line in enumerate(lines) if line.startswith("def init_db"))
    end = next(i for i, line in enumerate(lines) if line.startswith(AUTH_MARKER))
    return lines[start:end]


def main() -> None:
    block: list[str] | None = None
    for source in SOURCES:
        if not source.is_file():
            continue
        lines = read_lines(source)
        if any(line.startswith("def init_db") for line in lines):
            block = find_init_block(lines)
            print(f"init_db from {source}")
            break
    if not block:
        raise SystemExit("init_db source not found")

    routes_lines = ROUTES.read_text(encoding="utf-8").splitlines()
    if any(line.startswith("def init_db") for line in routes_lines):
        print("init_db already in routes.py")
        return
    ins = next(i for i, line in enumerate(routes_lines) if line.startswith(AUTH_MARKER))
    routes_lines = routes_lines[:ins] + block + [""] + routes_lines[ins:]
    ROUTES.write_text("\n".join(routes_lines) + "\n", encoding="utf-8")
    print(f"inserted init_db ({len(block)} lines)")


if __name__ == "__main__":
    main()
