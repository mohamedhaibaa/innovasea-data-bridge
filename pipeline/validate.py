"""Step 5: run validation for the latest successful staging load."""
from db import get_connection


def latest_run_id(conn) -> int:
    """The most recent successful load into staging."""
    row = conn.cursor().execute(
        """SELECT MAX(RunId) FROM etl.RunLog
           WHERE PipelineName = 'load_staging' AND Status = 'Succeeded';"""
    ).fetchone()
    if row[0] is None:
        raise RuntimeError("No successful staging load found. Run load_staging.py first.")
    return row[0]


def validate(conn, run_id: int) -> list:
    """Run every validation rule for one run and return the summary."""
    cursor = conn.cursor()
    rows = cursor.execute("EXEC etl.usp_ValidateStaging @RunId = ?;", run_id).fetchall()
    conn.commit()
    return rows


def main() -> None:
    with get_connection() as conn:
        run_id = latest_run_id(conn)
        summary = validate(conn, run_id)
        print(f"Validation for run {run_id}:")
        for source_table, rule, count in summary:
            print(f"  {source_table:<20} {rule:<22} {count} row(s)")
        if not summary:
            print("  No problems found")


if __name__ == "__main__":
    main()