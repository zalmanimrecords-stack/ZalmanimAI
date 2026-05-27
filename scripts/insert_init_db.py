"""One-off: insert init_db from git HEAD into routes.py before auth login."""
from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROUTES = ROOT / "apps/server/app/api/routes.py"
AUTH_MARKER = '@router.post("/auth/login"'


def main() -> None:
    raw = subprocess.check_output(
        ["git", "show", "HEAD:apps/server/app/api/routes.py"],
        text=True,
        cwd=ROOT,
    )
    head_lines = raw.splitlines()
    start = next(i for i, line in enumerate(head_lines) if line.startswith("def init_db"))
    end = next(i for i, line in enumerate(head_lines) if line.startswith(AUTH_MARKER))
    block = head_lines[start:end]

    routes_lines = ROUTES.read_text(encoding="utf-8").splitlines()
    ins = next(i for i, line in enumerate(routes_lines) if line.startswith(AUTH_MARKER))
    if any(line.startswith("def init_db") for line in routes_lines):
        print("init_db already present")
        return
    routes_lines = routes_lines[:ins] + block + [""] + routes_lines[ins:]
    ROUTES.write_text("\n".join(routes_lines) + "\n", encoding="utf-8")
    print(f"inserted init_db ({len(block)} lines) at line {ins + 1}")


if __name__ == "__main__":
    main()
