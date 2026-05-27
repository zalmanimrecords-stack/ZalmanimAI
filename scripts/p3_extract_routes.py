"""Apply P3 extraction: wire routers and remove duplicated route blocks from routes.py."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROUTES_PATH = ROOT / "apps/server/app/api/routes.py"


def find_line(lines: list[str], prefix: str) -> int:
    for i, line in enumerate(lines):
        if line.startswith(prefix):
            return i
    raise SystemExit(f"marker not found: {prefix!r}")


lines = ROUTES_PATH.read_text(encoding="utf-8").splitlines()

pr_start = find_line(lines, '@router.get("/admin/pending-releases"')
pr_end = find_line(lines, '@router.get("/public/demo-confirm-form"')
rel_start = find_line(lines, '@router.get("/admin/releases"')
rel_end = find_line(lines, '@router.post("/admin/tasks/run-inactivity-check"')
set_start = rel_end
cat_start = find_line(lines, "# Catalog metadata (Proton CSV schema)")
cat_end = find_line(lines, "# ---- Social and Connectors routes removed")
bak_start = find_line(lines, "# --- Backup / Restore (admin only) ---")

remove_ranges = sorted(
    [
        (cat_start, cat_end),
        (set_start, cat_start),
        (bak_start, cat_end),  # backup is between catalog and social in file - handled by cat_start:cat_end if backup after catalog
        (rel_start, rel_end),
        (pr_start, pr_end),
    ],
    key=lambda r: r[0],
    reverse=True,
)

# backup is inside [cat_start, cat_end) typically after catalog - single cut set_start:cat_end covers inactivity+backup+catalog
remove_ranges = sorted(
    [
        (cat_start, cat_end),
        (set_start, cat_start),
        (rel_start, rel_end),
        (pr_start, pr_end),
    ],
    key=lambda r: r[0],
    reverse=True,
)

for start, end in remove_ranges:
    lines = lines[:start] + lines[end:]

# Remove orphaned helpers
filtered: list[str] = []
i = 0
while i < len(lines):
    line = lines[i]
    if line.startswith("def _db_row_to_dict"):
        i += 1
        while i < len(lines) and not lines[i].startswith("@router.get(\"/admin/agents"):
            i += 1
        continue
    if line.startswith("MAX_CATALOG_IMPORT_BYTES") or line.startswith("MAX_RESTORE_BYTES"):
        i += 1
        continue
    if line.startswith("def _format_byte_limit"):
        i += 1
        while i < len(lines) and not (lines[i].startswith("@router") or lines[i].startswith("def _create_pending_release")):
            i += 1
        continue
    filtered.append(line)
    i += 1

text = "\n".join(filtered) + "\n"
if "pending_release_router" not in text:
    text = text.replace(
        "from app.api.inbox_routes import _create_pending_release_inbox_message, router as inbox_router\n",
        "from app.api.inbox_routes import _create_pending_release_inbox_message, router as inbox_router\n"
        "from app.api.pending_release_routes import router as pending_release_router\n"
        "from app.api.release_routes import router as release_router\n"
        "from app.api.catalog_routes import router as catalog_router\n"
        "from app.api.settings_routes import router as settings_router\n",
        1,
    )
if "router.include_router(settings_router)" not in text:
    text = text.replace(
        "router.include_router(inbox_router)\n",
        "router.include_router(inbox_router)\n"
        "router.include_router(pending_release_router)\n"
        "router.include_router(release_router)\n"
        "router.include_router(catalog_router)\n"
        "router.include_router(settings_router)\n",
        1,
    )

ROUTES_PATH.write_text(text, encoding="utf-8")
print("P3 applied:", len(text.splitlines()), "lines")
