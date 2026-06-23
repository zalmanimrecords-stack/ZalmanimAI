"""Runtime configuration for the Zalmanim MCP server.

Secrets (admin email/password) are read from the process environment, with a
fallback to a gitignored ``apps/mcp/.env`` file so they never have to live in a
committed MCP client config. No third-party dotenv dependency is used.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

DEFAULT_BASE_URL = "http://localhost:8000"
DEFAULT_TIMEOUT_SECONDS = 30.0

# apps/mcp/.env  (one level up from this package directory)
_ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


def _load_env_file(path: Path) -> None:
    """Populate os.environ from a simple KEY=VALUE .env file.

    Existing environment variables always win, so a value set by the MCP client
    config or the shell overrides the file. Malformed lines are skipped rather
    than raising, because a broken .env should not crash the whole server.
    """
    if not path.is_file():
        return
    try:
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value
    except OSError:
        # A missing/unreadable .env is non-fatal: env vars may still be set.
        return


@dataclass(frozen=True)
class Config:
    """Connection settings for the Zalmanim AI backend."""

    base_url: str
    email: str
    password: str
    timeout: float = DEFAULT_TIMEOUT_SECONDS

    @classmethod
    def from_env(cls) -> "Config":
        _load_env_file(_ENV_FILE)
        base_url = os.environ.get("ZALMANIM_API_BASE_URL", DEFAULT_BASE_URL).rstrip("/")
        email = os.environ.get("ZALMANIM_ADMIN_EMAIL", "").strip()
        password = os.environ.get("ZALMANIM_ADMIN_PASSWORD", "")
        try:
            timeout = float(os.environ.get("ZALMANIM_API_TIMEOUT", DEFAULT_TIMEOUT_SECONDS))
        except ValueError:
            timeout = DEFAULT_TIMEOUT_SECONDS
        return cls(base_url=base_url or DEFAULT_BASE_URL, email=email, password=password, timeout=timeout)

    def has_credentials(self) -> bool:
        return bool(self.email and self.password)
