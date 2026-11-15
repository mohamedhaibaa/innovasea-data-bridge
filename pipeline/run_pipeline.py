"""Run the whole Data Bridge pipeline end to end, as one logged run.

Load -> validate -> merge -> reconcile. This is the single command a
nightly schedule (Azure Function, SQL Agent job, cron) would call.
"""
from db import get_connection
from load_staging import finish_run, load_all, start_run
from merge import merge
from reconcile import reconcile
from validate import validate


def main() -> None:
    with get_connection() as conn:
        run_id = start_run(conn, "nightly_pipeline")
        print(f"Run {run_id} started")
        try:
            loaded = load_all(conn, run_id)
            print(f"1. Loaded {loaded} rows into staging")

            validate(conn, run_id)
            rejected = conn.cursor().execute(
                "SELECT RowsRejected FROM etl.RunLog WHERE RunId = ?;", run_id
            ).fetchval()
            print(f"2. Validated: {rejected} rows quarantined")

            changes = merge(conn, run_id)
            changed = sum(count for _, _, count in changes)
            print(f"3. Merged: {changed} rows inserted or updated")

            totals, issues = reconcile(conn, run_id)
            gap = totals.CrmWonTotal - totals.ErpOrderTotal
            print(f"4. Reconciled: CRM vs ERP gap {gap:,.2f}, "
                  f"explained by {len(issues)} issue(s)")

            finish_run(conn, run_id, "Succeeded",
                       rows_loaded=loaded, rows_rejected=rejected)
            print(f"Run {run_id} succeeded")
        except Exception as exc:
            conn.rollback()
            finish_run(conn, run_id, "Failed", error=str(exc))
            print(f"Run {run_id} failed: {exc}")
            raise


if __name__ == "__main__":
    main()