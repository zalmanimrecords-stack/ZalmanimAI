"""Tests for env/.env configuration loading."""

from __future__ import annotations

from zalmanim_mcp import config as config_module
from zalmanim_mcp.config import Config


def test_env_file_does_not_override_existing_env(tmp_path, monkeypatch):
    env_file = tmp_path / ".env"
    env_file.write_text('ZALMANIM_ADMIN_EMAIL="file@example.com"\nZALMANIM_API_BASE_URL=http://from-file\n')
    monkeypatch.setattr(config_module, "_ENV_FILE", env_file)
    monkeypatch.setenv("ZALMANIM_ADMIN_EMAIL", "env@example.com")
    monkeypatch.delenv("ZALMANIM_API_BASE_URL", raising=False)

    cfg = Config.from_env()

    assert cfg.email == "env@example.com"  # shell env wins
    assert cfg.base_url == "http://from-file"  # file fills the gap


def test_defaults_when_unset(tmp_path, monkeypatch):
    monkeypatch.setattr(config_module, "_ENV_FILE", tmp_path / "missing.env")
    for key in ("ZALMANIM_ADMIN_EMAIL", "ZALMANIM_ADMIN_PASSWORD", "ZALMANIM_API_BASE_URL", "ZALMANIM_API_TIMEOUT"):
        monkeypatch.delenv(key, raising=False)

    cfg = Config.from_env()

    assert cfg.base_url == config_module.DEFAULT_BASE_URL
    assert cfg.has_credentials() is False
