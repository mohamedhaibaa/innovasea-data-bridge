"""Step 7: reconcile the CRM (Salesforce) against the ERP (SYSPRO)."""
from db import get_connection
from validate import latest_run_id


def reconcile(conn, run_id: int):
    """Run the reconciliation; return the headline totals and every issue."""
    cursor = conn.cursor()
    cursor.execute("EXEC etl.usp_Reconcile @RunId = ?;", run_id)
    totals = cursor.fetchone()   # result 1: headline numbers
    cursor.nextset()
    issues = cursor.fetchall()   # result 2: the issues
    conn.commit()
    return totals, issues


def main() -> None:
    with get_connection() as conn:
        run_id = latest_run_id(conn)
        totals, issues = reconcile(conn, run_id)

        crm, erp = totals.CrmWonTotal, totals.ErpOrderTotal
        print(f"Reconciliation for run {run_id}:")
        print(f"  CRM won deals : {crm:>14,.2f}")
        print(f"  ERP orders    : {erp:>14,.2f}")
        print(f"  Difference    : {crm - erp:>14,.2f}")
        print()

        if not issues:
            print("  The systems agree: no issues found")
        for i in issues:
            print(f"  {i.Issue:<20} {i.CrmDealId or '-':<9} "
                  f"{i.OrderNumber or '-':<8} {i.Difference:>10,.2f}  {i.Detail}")


if __name__ == "__main__":
    main()