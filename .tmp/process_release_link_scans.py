from app.db.session import SessionLocal
from app.services.release_link_discovery import (
    get_release_link_runs_ready_to_scan,
    process_release_link_scan_run,
)


def main() -> None:
    db = SessionLocal()
    processed = 0
    try:
        while processed < 30:
            runs = get_release_link_runs_ready_to_scan(db, limit=1)
            if not runs:
                break
            run = runs[0]
            if process_release_link_scan_run(db, run.id):
                processed += 1
            else:
                break
        print({"processed_runs": processed})
    finally:
        db.close()


if __name__ == "__main__":
    main()
