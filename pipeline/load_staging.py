"""Step 4: load the raw CSV files into staging, exactly as they arrived.

Every run is recorded in etl.RunLog, and its RunId is stamped on every
staged row, so any row can be traced back to the load that brought it in.
"""
import csv
from pathlib import Path

from db import get_connection

DATA_DIR = Path(__file__).resolve().parent.parent / "data"

# Which source file lands in which staging table
FILES = {
    "customers.csv": "stg.Customer",
    "products.csv": "stg.Product",
    "crm_deals.csv": "stg.CrmDeal",
    "sales_orders.csv": "stg.SalesOrder",
    "sales_order_lines.csv": "stg.SalesOrderLine",
    "budget.csv": "stg.Budget",
}


def start_run(conn, pipeline_name: str) -> int:
    """Create a run-log entry and return its RunId (the batch number)."""
    row = conn.cursor().execute(
        "INSERT INTO etl.RunLog (PipelineName) OUTPUT INSERTED.RunId VALUES (?);",
        pipeline_name,
    ).fetchone()
    conn.commit()
    return row[0]


def finish_run(conn, run_id: int, status: str, rows_loaded=None,
               rows_rejected=None, error=None) -> None:
    """Close the run-log entry with its outcome."""
    conn.cursor().execute(
        """UPDATE etl.RunLog
           SET EndedAtUtc = SYSUTCDATETIME(), Status = ?, RowsLoaded = ?,
               RowsRejected = ?, ErrorMessage = ?
           WHERE RunId = ?;""",
        status, rows_loaded, rows_rejected, error, run_id,
    )
    conn.commit()


def load_file(cursor, run_id: int, file_name: str, table: str) -> int:
    """Insert one CSV into its staging table, unchanged except '' -> NULL."""
    with (DATA_DIR / file_name).open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        columns = reader.fieldnames
        rows = [
            [run_id] + [row[c] if row[c] != "" else None for c in columns]
            for row in reader
        ]

    column_list = ", ".join(["RunId"] + columns)
    placeholders = ", ".join("?" * (len(columns) + 1))
    cursor.fast_executemany = True  # send rows in bulk, not one by one
    cursor.executemany(
        f"INSERT INTO {table} ({column_list}) VALUES ({placeholders});", rows
    )
    return len(rows)


def load_all(conn, run_id: int) -> int:
    """Clear staging and load every file. All-or-nothing in one transaction."""
    cursor = conn.cursor()
    for table in FILES.values():
        cursor.execute(f"DELETE FROM {table};")

    total = 0
    for file_name, table in FILES.items():
        count = load_file(cursor, run_id, file_name, table)
        print(f"{table:<20} {count:>4} rows")
        total += count

    conn.commit()
    return total


def main() -> None:
    with get_connection() as conn:
        run_id = start_run(conn, "load_staging")
        try:
            total = load_all(conn, run_id)
            finish_run(conn, run_id, "Succeeded", rows_loaded=total)
            print(f"Run {run_id} succeeded: {total} rows loaded into staging")
        except Exception as exc:
            conn.rollback()  # undo the partial load
            finish_run(conn, run_id, "Failed", error=str(exc))
            print(f"Run {run_id} failed: {exc}")
            raise


if __name__ == "__main__":
    main()