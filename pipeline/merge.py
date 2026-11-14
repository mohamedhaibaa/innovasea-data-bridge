"""Step 6: merge valid staging rows into the clean tables."""
from db import get_connection
from validate import latest_run_id


def merge(conn, run_id: int) -> list:
    """Insert new and update changed records for one run; return the summary."""
    rows = conn.cursor().execute(
        "EXEC etl.usp_MergeToClean @RunId = ?;", run_id
    ).fetchall()
    conn.commit()
    return rows


def main() -> None:
    with get_connection() as conn:
        run_id = latest_run_id(conn)
        summary = merge(conn, run_id)
        print(f"Merge for run {run_id}:")
        for table, action, count in summary:
            print(f"  {table:<20} {action:<8} {count} row(s)")
        if not summary:
            print("  No changes: everything was already up to date")


if __name__ == "__main__":
    main()