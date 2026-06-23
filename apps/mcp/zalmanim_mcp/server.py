"""FastMCP server wiring for Zalmanim AI."""

from __future__ import annotations

import logging
import os

from mcp.server.fastmcp import FastMCP

from .client import ZalmanimClient
from .config import Config
from .tools import register_all

logger = logging.getLogger("zalmanim_mcp")

SERVER_NAME = "zalmanim-ai"


def build_server(client: ZalmanimClient | None = None) -> FastMCP:
    """Create a FastMCP server with all Zalmanim tools registered.

    A client may be injected (used by tests); otherwise one is built from the
    environment. The connection is lazy — no network call happens until a tool
    runs — so the server starts cleanly even if the backend is down.
    """
    mcp = FastMCP(SERVER_NAME)
    api_client = client or ZalmanimClient(Config.from_env())
    register_all(mcp, api_client)
    return mcp


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("ZALMANIM_MCP_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    logger.info("Starting Zalmanim AI MCP server (stdio).")
    build_server().run()
