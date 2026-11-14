"""Step 9: leadership dashboard for the Innovasea Data Bridge.

Reads only from the rpt views and the run log, never the raw tables,
so every number matches the shared definitions in Azure SQL.
"""
import sys
from decimal import Decimal
from pathlib import Path

import pandas as pd
import streamlit as st

# Reuse the pipeline's connection helper (one place for connection settings)
sys.path.append(str(Path(__file__).resolve().parent.parent / "pipeline"))
from db import get_connection  # noqa: E402

st.set_page_config(page_title="Innovasea Data Bridge", layout="wide")


@st.cache_data(ttl=600)  # cache results for 10 minutes so the page stays fast
def query(sql: str) -> pd.DataFrame:
    """Run a read-only query and return a DataFrame with money as floats."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(sql)
        columns = [c[0] for c in cursor.description]
        df = pd.DataFrame.from_records([tuple(r) for r in cursor.fetchall()],
                                       columns=columns)
    for col in df.columns:
        if df[col].map(lambda v: isinstance(v, Decimal)).any():
            df[col] = df[col].map(lambda v: float(v) if v is not None else None)
    return df


# ---------------------------------------------------------------- data
run = query("""SELECT TOP 1 RunId, Status, StartedAtUtc, RowsLoaded, RowsRejected
               FROM etl.RunLog ORDER BY RunId DESC""")
sales = query("SELECT SalesMonth, ProductLine, Orders, Units, Revenue FROM rpt.SalesByMonth")
sales["SalesMonth"] = pd.to_datetime(sales["SalesMonth"])
pending = query("""SELECT OrderNumber, CustomerName, Region, OrderDate, DaysOpen,
                          Units, OrderTotal
                   FROM rpt.OrdersPendingShipment ORDER BY DaysOpen DESC""")
budget = query("""SELECT BudgetMonth, ProductLine, BudgetAmount, ActualRevenue,
                         Variance, VariancePct
                  FROM rpt.BudgetVsActual ORDER BY BudgetMonth, ProductLine""")
quality = query("""SELECT SourceTable, RuleName, RowsRejected, ExampleReason
                   FROM rpt.DataQuality ORDER BY RowsRejected DESC""")
recon = query("""SELECT Issue, CrmDealId, OrderNumber, CustomerCode,
                        CrmAmount, ErpAmount, Difference, Detail
                 FROM rpt.ReconciliationIssues ORDER BY ABS(Difference) DESC""")

# ---------------------------------------------------------------- header
st.title("Innovasea Data Bridge")
if not run.empty:
    r = run.iloc[0]
    st.caption(
        f"Mock Salesforce, SYSPRO and Adaptive data in Azure SQL · "
        f"Latest run {r.RunId}: {r.Status}, {r.RowsLoaded} rows loaded, "
        f"{r.RowsRejected} rejected · {r.StartedAtUtc:%Y-%m-%d %H:%M} UTC"
    )

revenue_2026 = sales.loc[sales.SalesMonth.dt.year == 2026, "Revenue"].sum()
gap = recon["Difference"].sum() if not recon.empty else 0

c1, c2, c3, c4 = st.columns(4)
c1.metric("2026 revenue (ERP)", f"${revenue_2026:,.0f}")
c2.metric("Open orders", f"{len(pending)}",
          f"${pending.OrderTotal.sum():,.0f} waiting to ship", delta_color="off")
c3.metric("Rows rejected (latest run)",
          int(quality.RowsRejected.sum()) if not quality.empty else 0)
c4.metric("CRM vs ERP gap", f"${gap:,.0f}",
          f"{len(recon)} issue(s) explain it", delta_color="off")

sales_tab, ops_tab, quality_tab = st.tabs(["Sales", "Operations", "Data Quality"])

# ---------------------------------------------------------------- sales
# ---------------------------------------------------------------- sales
with sales_tab:
    years = sorted(sales.SalesMonth.dt.year.unique(), reverse=True)
    year = st.selectbox("Year", years, index=0)  # newest year first
    selected = sales[sales.SalesMonth.dt.year == year]

    st.subheader(f"Revenue by month and product line, {year}")
    trend = (selected.pivot_table(index="SalesMonth", columns="ProductLine",
                                  values="Revenue", aggfunc="sum")
             .sort_index())
    trend.index = trend.index.strftime("%Y-%m")
    st.bar_chart(trend, stack=False)
    if year < 2026:
        st.caption("Generated order history, used for performance testing.")

    st.subheader(f"{year} by product line")
    by_line = (selected.groupby("ProductLine")[["Orders", "Units", "Revenue"]]
               .sum().reset_index())
    st.dataframe(by_line, hide_index=True, use_container_width=True,
                 column_config={"Revenue": st.column_config.NumberColumn(format="$%.0f")})

# ---------------------------------------------------------------- operations
with ops_tab:
    left, right = st.columns(2)

    with left:
        st.subheader("Budget vs actual (Adaptive vs ERP)")
        monthly = (budget.groupby("BudgetMonth")[["BudgetAmount", "ActualRevenue"]]
                   .sum().rename(columns={"BudgetAmount": "Budget",
                                          "ActualRevenue": "Actual"}))
        st.bar_chart(monthly, stack=False)
        st.dataframe(budget, hide_index=True, use_container_width=True,
                     column_config={
                         "BudgetAmount": st.column_config.NumberColumn("Budget", format="$%.0f"),
                         "ActualRevenue": st.column_config.NumberColumn("Actual", format="$%.0f"),
                         "Variance": st.column_config.NumberColumn(format="$%.0f"),
                         "VariancePct": st.column_config.NumberColumn("Variance %", format="%.1f%%"),
                     })

    with right:
        st.subheader("Orders waiting to ship, oldest first")
        st.dataframe(pending, hide_index=True, use_container_width=True,
                     column_config={"OrderTotal": st.column_config.NumberColumn(
                         "Order total", format="$%.0f")})

# ---------------------------------------------------------------- data quality
with quality_tab:
    st.subheader("Rejected at the integration boundary (latest run)")
    if quality.empty:
        st.success("No rows were rejected in the latest run.")
    else:
        st.dataframe(quality, hide_index=True, use_container_width=True)

    st.subheader("Where Salesforce and SYSPRO disagree")
    if recon.empty:
        st.success("The CRM and the ERP agree.")
    else:
        st.dataframe(recon, hide_index=True, use_container_width=True,
                     column_config={
                         "CrmAmount": st.column_config.NumberColumn("CRM amount", format="$%.2f"),
                         "ErpAmount": st.column_config.NumberColumn("ERP amount", format="$%.2f"),
                         "Difference": st.column_config.NumberColumn(format="$%.2f"),
                     })
        st.caption(f"These {len(recon)} issues explain the full ${gap:,.2f} gap between the systems.")