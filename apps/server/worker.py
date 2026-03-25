"""Worker: poll for scheduled campaigns and run send (social, Mailchimp, WordPress)."""

import os
import sys
import time
from pathlib import Path
from datetime import datetime, timezone

# Ensure app root is on path and env is loaded (e.g. DATABASE_URL in docker).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sqlalchemy.exc import OperationalError

from app.db.session import SessionLocal, engine
from app.services.campaign_send import get_campaigns_ready_to_send, run_campaign_send

POLL_INTERVAL_SEC = 60
HEARTBEAT_PATH = Path(os.environ.get("WORKER_HEARTBEAT_PATH", "/tmp/worker-heartbeat.txt"))


def _touch_heartbeat() -> None:
    HEARTBEAT_PATH.write_text(datetime.now(timezone.utc).isoformat(), encoding="utf-8")


def main() -> None:
    while True:
        try:
            _touch_heartbeat()
            db = SessionLocal()
            try:
                campaigns = get_campaigns_ready_to_send(db, limit=5)
                for campaign in campaigns:
                    run_campaign_send(db, campaign.id)
                    _touch_heartbeat()
            finally:
                db.close()
        except OperationalError as e:
            print(f"worker error: {e}", flush=True)
            engine.dispose()
        except Exception as e:
            print(f"worker error: {e}", flush=True)
        finally:
            try:
                _touch_heartbeat()
            except Exception:
                pass
        time.sleep(POLL_INTERVAL_SEC)


if __name__ == "__main__":
    main()
