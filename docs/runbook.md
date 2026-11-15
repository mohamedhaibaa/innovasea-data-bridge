# Runbook: Innovasea Data Bridge

## Run the pipeline

    python pipeline/run_pipeline.py

## Check the last run

    SELECT TOP 5 * FROM etl.RunLog ORDER BY RunId DESC;

## When something goes wrong

| Symptom                      | Likely cause                         | What to do                                                                                                                 |
| ---------------------------- | ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| Run status **Failed**        | A file is missing or malformed       | Read `ErrorMessage` in `etl.RunLog`. The load is all-or-nothing, so staging is unchanged. Fix the file, re-run.            |
| Rows in quarantine           | Source data broke a rule             | `SELECT * FROM etl.Quarantine WHERE RunId = <id>`. Fix the record in the source system (not in the database), then re-run. |
| Reconciliation issues        | CRM and ERP disagree                 | Check `rpt.ReconciliationIssues`. Sales fixes the deal or Operations fixes the order; the next run confirms it.            |
| Login timeout                | Database paused when idle            | Connections retry automatically; wait a minute and try again.                                                              |
| "Client IP not allowed"      | New network                          | Azure portal → SQL server → Networking → add your client IP only.                                                          |
| "Login failed for user"      | Wrong or mistyped password           | Check the user exists and has its role, then reset the password with `ALTER USER`.                                         |
| Dashboard slow on first load | Free tier app and database waking up | Wait about a minute; open it a few minutes before demos.                                                                   |

## Safe to re-run?

Yes. Loads, validation, merge and reconciliation are all idempotent:
re-running the same data changes nothing.

## Rollback

Each step runs in a transaction, so a failure rolls back that step.
Every clean row carries `LastRunId`, so changes from a bad run can be traced.

## Access

| User               | Used by           | Can do                                          |
| ------------------ | ----------------- | ----------------------------------------------- |
| `dashboard_user`   | Dashboard         | Read `rpt` views only                           |
| `pipeline_user`    | `run_pipeline.py` | Load staging, write run log, run ETL procedures |
| `databridge_admin` | Setup only        | Everything; not used day to day                 |
