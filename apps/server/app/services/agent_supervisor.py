from __future__ import annotations

import re
from dataclasses import dataclass


HEBREW_AND = "\u05d5\u05d2\u05dd"
HEBREW_THEN = "\u05d5\u05d0\u05d6"
HEBREW_AFTER = "\u05d0\u05d7\u05e8 \u05db\u05da"
HEBREW_ADDITIONAL = "\u05d1\u05e0\u05d5\u05e1\u05e3"
HEBREW_AS_WELL = "\u05d5\u05db\u05df"


@dataclass(frozen=True)
class AgentDefinition:
    key: str
    title: str
    role: str
    description: str
    capabilities: tuple[str, ...]
    keywords: tuple[str, ...]
    handoff_triggers: tuple[str, ...]
    priority: int = 0


SUPERVISOR_KEYWORDS = (
    "plan", "workflow", "route", "delegate", "orchestrate", "agent", "agents",
    "\u05e1\u05d5\u05db\u05df", "\u05e1\u05d5\u05db\u05e0\u05d9\u05dd", "\u05d7\u05dc\u05d5\u05e7\u05d4", "\u05d4\u05e7\u05e6\u05d4", "\u05de\u05e9\u05d9\u05de\u05d5\u05ea",
)
ARTIST_KEYWORDS = (
    "artist", "artists", "profile", "onboard", "roster",
    "\u05d0\u05de\u05df", "\u05d0\u05de\u05e0\u05d9\u05dd", "\u05d9\u05d5\u05e6\u05e8", "\u05d9\u05d5\u05e6\u05e8\u05d9\u05dd", "\u05de\u05d9\u05d6\u05d5\u05d2", "\u05e4\u05e8\u05d5\u05e4\u05d9\u05dc",
)
RELEASE_KEYWORDS = (
    "release", "track", "catalog", "upload", "upc", "isrc", "metadata", "sync",
    "\u05e8\u05d9\u05dc\u05d9\u05e1", "\u05e9\u05d9\u05e8", "\u05e7\u05d8\u05dc\u05d5\u05d2", "\u05d4\u05e2\u05dc\u05d0\u05d4", "\u05de\u05d8\u05d0\u05d3\u05d0\u05d8\u05d4", "\u05e1\u05e0\u05db\u05e8\u05d5\u05df", "\u05d8\u05e8\u05d0\u05e7",
)
CAMPAIGN_KEYWORDS = (
    "campaign", "post", "publish", "schedule", "social", "wordpress", "content",
    "\u05e7\u05de\u05e4\u05d9\u05d9\u05df", "\u05e4\u05d5\u05e1\u05d8", "\u05e4\u05e8\u05e1\u05d5\u05dd", "\u05dc\u05ea\u05d6\u05de\u05df", "\u05e1\u05d5\u05e9\u05d9\u05d0\u05dc", "\u05ea\u05d5\u05db\u05df", "\u05d5\u05d5\u05e8\u05d3\u05e4\u05e8\u05e1",
)
AUDIENCE_KEYWORDS = (
    "audience", "subscriber", "mailchimp", "email", "newsletter", "list", "segment",
    "\u05e7\u05d4\u05dc", "\u05e0\u05de\u05e2\u05e0\u05d9\u05dd", "\u05e8\u05e9\u05d9\u05de\u05d4", "\u05d0\u05d9\u05de\u05d9\u05d9\u05dc", "\u05de\u05d9\u05d9\u05dc", "\u05e0\u05d9\u05d5\u05d6\u05dc\u05d8\u05e8", "\u05e1\u05d2\u05de\u05e0\u05d8",
)
ANALYTICS_KEYWORDS = (
    "report", "reports", "analytics", "dashboard", "health", "monitor", "inactivity", "summary",
    "\u05d3\u05d5\u05d7", "\u05d3\u05d5\u05d7\u05d5\u05ea", "\u05d0\u05e0\u05dc\u05d9\u05d8\u05d9\u05e7\u05d4", "\u05d3\u05e9\u05d1\u05d5\u05e8\u05d3", "\u05d1\u05e8\u05d9\u05d0\u05d5\u05ea", "\u05e0\u05d9\u05d8\u05d5\u05e8", "\u05d7\u05d5\u05e1\u05e8 \u05e4\u05e2\u05d9\u05dc\u05d5\u05ea", "\u05e1\u05d9\u05db\u05d5\u05dd",
)
ADMIN_KEYWORDS = (
    "admin", "settings", "oauth", "connector", "permission", "auth", "smtp", "system",
    "\u05d0\u05d3\u05de\u05d9\u05df", "\u05d4\u05d2\u05d3\u05e8\u05d5\u05ea", "\u05de\u05d7\u05d1\u05e8", "\u05d4\u05e8\u05e9\u05d0\u05d5\u05ea", "\u05d0\u05d9\u05de\u05d5\u05ea", "\u05de\u05e2\u05e8\u05db\u05ea",
)


def _normalize_text(value: str) -> str:
    normalized = (value or "").strip().lower()
    return re.sub(r"\s+", " ", normalized)


def _split_work_items(text: str) -> list[str]:
    normalized = _normalize_text(text)
    if not normalized:
        return []
    separator_pattern = rf"(?:\n+|;|,|\.(?:\s|$)|\band\b|\bthen\b|\balso\b| {re.escape(HEBREW_AND)} | {re.escape(HEBREW_THEN)} | {re.escape(HEBREW_AFTER)} | {re.escape(HEBREW_ADDITIONAL)} | {re.escape(HEBREW_AS_WELL)} )"
    parts = re.split(separator_pattern, normalized)
    items: list[str] = []
    for part in parts:
        cleaned = re.sub(r"\s+", " ", part).strip(" -")
        if len(cleaned) >= 3:
            items.append(cleaned)
    return items or [normalized]


def get_agent_registry() -> list[AgentDefinition]:
    return [
        AgentDefinition(
            key="supervisor",
            title="Supervisor",
            role="Top-level orchestrator",
            description="Breaks incoming requests into work items and delegates each item to the most relevant specialist agent.",
            capabilities=("Intent detection", "Task decomposition", "Priority assignment", "Cross-agent coordination"),
            keywords=SUPERVISOR_KEYWORDS,
            handoff_triggers=("Multi-domain request", "Ambiguous ownership", "Request contains more than one task"),
            priority=100,
        ),
        AgentDefinition(
            key="artist_ops",
            title="Artist Ops Agent",
            role="Artist lifecycle owner",
            description="Handles artist setup, profile maintenance, merges, status changes, and artist-facing support flows.",
            capabilities=("Artist onboarding", "Profile edits", "Artist merges", "Artist status review"),
            keywords=ARTIST_KEYWORDS,
            handoff_triggers=("Artist identity or lifecycle request", "Artist merge or activation change"),
            priority=80,
        ),
        AgentDefinition(
            key="release_ops",
            title="Release Ops Agent",
            role="Release and catalog owner",
            description="Handles music uploads, catalog sync, release matching, metadata cleanup, and assignment of artists to releases.",
            capabilities=("Release ingestion", "Catalog reconciliation", "Metadata cleanup", "Artist-release assignment"),
            keywords=RELEASE_KEYWORDS,
            handoff_triggers=("Release ingestion or sync request", "Catalog mismatch or metadata update"),
            priority=70,
        ),
        AgentDefinition(
            key="campaign_ops",
            title="Campaign Agent",
            role="Campaign and publishing owner",
            description="Handles campaign planning, scheduling, social publishing, WordPress posting, and cross-channel delivery.",
            capabilities=("Campaign planning", "Scheduling", "Social publishing", "WordPress delivery"),
            keywords=CAMPAIGN_KEYWORDS,
            handoff_triggers=("Publishing or campaign request", "Scheduled send or distribution task"),
            priority=75,
        ),
        AgentDefinition(
            key="audience_ops",
            title="Audience Agent",
            role="Audience and email owner",
            description="Handles audience lists, subscribers, email sends, segmentation, consent state, and outreach preparation.",
            capabilities=("Audience management", "Subscriber operations", "Email preparation", "Consent tracking"),
            keywords=AUDIENCE_KEYWORDS,
            handoff_triggers=("Audience or mailing request", "Subscriber lifecycle or email outreach"),
            priority=65,
        ),
        AgentDefinition(
            key="analytics_ops",
            title="Analytics Agent",
            role="Reporting and monitoring owner",
            description="Handles reports, health checks, inactivity analysis, dashboards, and recommendation summaries.",
            capabilities=("Operational reporting", "Trend analysis", "Health monitoring", "Exception surfacing"),
            keywords=ANALYTICS_KEYWORDS,
            handoff_triggers=("Reporting or monitoring request", "Need for summary or anomaly detection"),
            priority=60,
        ),
        AgentDefinition(
            key="admin_ops",
            title="Admin Ops Agent",
            role="System configuration owner",
            description="Handles auth, settings, connector setup, system policies, and admin-level operational tasks.",
            capabilities=("System settings", "Connector configuration", "Auth and access", "Operational controls"),
            keywords=ADMIN_KEYWORDS,
            handoff_triggers=("Admin-only system change", "Connector or auth configuration"),
            priority=55,
        ),
    ]


def _score_agent(agent: AgentDefinition, text: str) -> tuple[int, list[str]]:
    matches = [keyword for keyword in agent.keywords if keyword in text]
    return len(matches), matches


def _choose_agent(text: str, registry: list[AgentDefinition]) -> tuple[AgentDefinition, list[str], float]:
    scored: list[tuple[int, int, AgentDefinition, list[str]]] = []
    for agent in registry:
        if agent.key == "supervisor":
            continue
        score, matches = _score_agent(agent, text)
        scored.append((score, agent.priority, agent, matches))
    scored.sort(key=lambda item: (item[0], item[1]), reverse=True)
    best_score, _, best_agent, matches = scored[0]
    if best_score <= 0:
        fallback = next(agent for agent in registry if agent.key == "admin_ops")
        return fallback, [], 0.25
    confidence = min(0.35 + (best_score * 0.15), 0.95)
    return best_agent, matches, confidence


def build_agent_plan(text: str, max_agents: int = 4) -> dict:
    registry = get_agent_registry()
    supervisor = next(agent for agent in registry if agent.key == "supervisor")
    normalized = _normalize_text(text)
    work_items = _split_work_items(normalized) or ([normalized] if normalized else [])

    delegations: list[dict] = []
    used_agent_keys: list[str] = []

    for item in work_items:
        agent, matches, confidence = _choose_agent(item, registry)
        if agent.key not in used_agent_keys and len(used_agent_keys) >= max_agents:
            agent = next(a for a in registry if a.key == used_agent_keys[0])
            matches = []
            confidence = 0.4
        if agent.key not in used_agent_keys:
            used_agent_keys.append(agent.key)
        delegations.append(
            {
                "work_item": item,
                "agent_key": agent.key,
                "agent_title": agent.title,
                "reason": "Matched keywords: " + ", ".join(matches) if matches else "Fallback to operational owner for uncategorized request.",
                "confidence": round(confidence, 2),
            }
        )

    active_agents = [agent for agent in registry if agent.key in used_agent_keys]
    primary_agent = active_agents[0] if active_agents else next(agent for agent in registry if agent.key == "admin_ops")

    if not normalized:
        summary = "Supervisor did not receive text to analyze."
    elif len(delegations) == 1:
        summary = f"Supervisor assigned the request to {primary_agent.title}."
    else:
        summary = f"Supervisor split the request into {len(delegations)} work items across {len(active_agents)} specialist agents."

    return {
        "supervisor": {
            "key": supervisor.key,
            "title": supervisor.title,
            "role": supervisor.role,
            "description": supervisor.description,
        },
        "summary": summary,
        "primary_agent_key": primary_agent.key,
        "primary_agent_title": primary_agent.title,
        "delegations": delegations,
        "agents": [
            {
                "key": agent.key,
                "title": agent.title,
                "role": agent.role,
                "description": agent.description,
                "capabilities": list(agent.capabilities),
                "handoff_triggers": list(agent.handoff_triggers),
            }
            for agent in registry
        ],
    }
