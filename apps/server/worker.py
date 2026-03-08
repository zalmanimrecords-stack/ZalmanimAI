"""Worker: poll for scheduled campaigns and run send (social, Mailchimp, WordPress)."""

import os
import sys
import time

# Ensure app root is on path and env is loaded (e.g. DATABASE_URL in docker).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.db.session import SessionLocal
from app.services.campaign_send import get_campaigns_ready_to_send, run_campaign_send

POLL_INTERVAL_SEC = 60


def main() -> None:
    while True:
        try:
            db = SessionLocal()
            try:
                campaigns = get_campaigns_ready_to_send(db, limit=5)
                for campaign in campaigns:
                    run_campaign_send(db, campaign.id)
            finally:
                db.close()
        except Exception as e:
            print(f"worker error: {e}", flush=True)
        time.sleep(POLL_INTERVAL_SEC)


if __name__ == "__main__":
    main()
