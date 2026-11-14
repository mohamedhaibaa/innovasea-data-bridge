"""Generate mock CRM (Salesforce), ERP (SYSPRO) and planning (Adaptive) data.

All names are invented. Bad rows are planted on purpose and listed in
data/planted_issues.md, the answer key used to prove the pipeline works.
"""
import csv
import random
import re
from datetime import date
from decimal import Decimal
from pathlib import Path

random.seed(42)  # same data every run, so results are repeatable
DATA_DIR = Path(__file__).resolve().parent.parent / "data"

# ---------------------------------------------------------------------
# Master data (invented)
# ---------------------------------------------------------------------
CUSTOMERS = [
    ("C-1001", "North Atlantic Salmon Co.", "Canada", "Atlantic Canada"),
    ("C-1002", "Fundy Bay Aquafarms", "Canada", "Atlantic Canada"),
    ("C-1003", "Cape Breton Seafarms", "Canada", "Atlantic Canada"),
    ("C-1004", "Pacific Rim Fisheries Research", "Canada", "Western Canada"),
    ("C-1005", "Great Lakes Fish Institute", "United States", "Midwest"),
    ("C-1006", "Fjordline Aquaculture", "Norway", "Europe"),
    ("C-1007", "Patagonia Salmon Farms", "Chile", "South America"),
    ("C-1008", "Aegean Sea Farms", "Greece", "Europe"),
    ("C-1009", "Red Sea Mariculture", "Saudi Arabia", "Middle East"),
    ("C-1010", "Columbia River Conservation Lab", "United States", "Pacific Northwest"),
    ("C-1011", "Shetland Marine Harvest", "United Kingdom", "Europe"),
    ("C-1012", "Nile Delta Aquaculture", "Egypt", "Middle East"),
]

PRODUCTS = [
    ("TAG-V9", "Acoustic Tag V9", "Fish Tracking", Decimal("300.00")),
    ("TAG-V13", "Acoustic Tag V13", "Fish Tracking", Decimal("420.00")),
    ("RCV-200", "Acoustic Receiver", "Fish Tracking", Decimal("1600.00")),
    ("RCV-LR", "Long-Range Receiver", "Fish Tracking", Decimal("2400.00")),
    ("SEN-O2", "Oxygen Sensor", "Aquaculture Intelligence", Decimal("950.00")),
    ("SEN-TMP", "Temperature Sensor", "Aquaculture Intelligence", Decimal("450.00")),
    ("CAM-BIO", "Biomass Camera", "Aquaculture Intelligence", Decimal("7800.00")),
    ("HUB-100", "Sensor Hub", "Aquaculture Intelligence", Decimal("2200.00")),
]


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def random_date() -> date:
    return date(2026, random.randint(1, 6), random.randint(1, 28))


def write_csv(name: str, rows: list[dict]) -> None:
    path = DATA_DIR / name
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"{name:<24} {len(rows):>4} rows")


def main() -> None:
    DATA_DIR.mkdir(exist_ok=True)
    price = {code: p for code, _, _, p in PRODUCTS}

    customers = [
        {"CustomerCode": c, "CustomerName": n, "Country": co,
         "Region": r, "Email": f"ops@{slug(n)}.example"}
        for c, n, co, r in CUSTOMERS
    ]
    products = [
        {"ProductCode": c, "ProductName": n, "ProductLine": pl, "UnitPrice": str(p)}
        for c, n, pl, p in PRODUCTS
    ]

    # 40 clean won deals, each with a matching ERP order
    deals, orders, lines = [], [], []
    for i in range(40):
        deal_id, order_no = f"OPP-{1001 + i}", f"SO-{5001 + i}"
        customer = random.choice(CUSTOMERS)[0]
        order_date = random_date()
        total = Decimal("0")
        for line_no in range(1, random.randint(1, 3) + 1):
            code = random.choice(PRODUCTS)[0]
            qty = random.randint(1, 20)
            lines.append({"OrderNumber": order_no, "LineNumber": line_no,
                          "ProductCode": code, "Quantity": qty,
                          "UnitPrice": str(price[code])})
            total += qty * price[code]
        orders.append({"OrderNumber": order_no, "CustomerCode": customer,
                       "OrderDate": order_date.isoformat(),
                       "Status": random.choices(["Open", "Shipped", "Invoiced"],
                                                weights=[2, 3, 5])[0],
                       "CrmDealId": deal_id})
        deals.append({"CrmDealId": deal_id, "CustomerCode": customer,
                      "DealName": f"{customer} {order_date:%b} order",
                      "Amount": str(total), "Stage": "Closed Won",
                      "CloseDate": order_date.isoformat()})

    # --- Planted issues: validation should quarantine these -----------
    # 1. Order for a customer that doesn't exist
    orders.append({"OrderNumber": "SO-5041", "CustomerCode": "C-9999",
                   "OrderDate": "2026-04-10", "Status": "Open", "CrmDealId": ""})
    lines.append({"OrderNumber": "SO-5041", "LineNumber": 1,
                  "ProductCode": "SEN-O2", "Quantity": 4, "UnitPrice": "950.00"})
    # 2. Impossible date
    orders.append({"OrderNumber": "SO-5042", "CustomerCode": "C-1002",
                   "OrderDate": "2026-13-45", "Status": "Open", "CrmDealId": ""})
    lines.append({"OrderNumber": "SO-5042", "LineNumber": 1,
                  "ProductCode": "TAG-V9", "Quantity": 10, "UnitPrice": "300.00"})
    # 3. Duplicate order (SO-5010 sent twice)
    orders.append(dict(orders[9]))
    # 4. Unknown product code
    lines.append({"OrderNumber": "SO-5002", "LineNumber": 9,
                  "ProductCode": "RCV-999", "Quantity": 2, "UnitPrice": "1600.00"})
    # 5. Negative quantity
    lines.append({"OrderNumber": "SO-5003", "LineNumber": 9,
                  "ProductCode": "TAG-V9", "Quantity": -5, "UnitPrice": "300.00"})
    # 6. Customer with no name
    customers.append({"CustomerCode": "C-1013", "CustomerName": "",
                      "Country": "Canada", "Region": "Atlantic Canada",
                      "Email": "ops@unknown.example"})

    # --- Planted issues: reconciliation should flag these --------------
    # 8. Won deal with no ERP order
    deals.append({"CrmDealId": "OPP-1041", "CustomerCode": "C-1003",
                  "DealName": "C-1003 May order", "Amount": "12800.00",
                  "Stage": "Closed Won", "CloseDate": "2026-05-14"})
    # 9. Deal amount differs from the order total
    deals[4]["Amount"] = str(Decimal(deals[4]["Amount"]) + Decimal("1500.00"))

    # Normal: lost deals have no orders, and reconciliation must ignore them
    for n, cust in zip((1042, 1043, 1044), ("C-1006", "C-1008", "C-1011")):
        deals.append({"CrmDealId": f"OPP-{n}", "CustomerCode": cust,
                      "DealName": f"{cust} lost opportunity", "Amount": "9500.00",
                      "Stage": "Closed Lost", "CloseDate": "2026-03-20"})

    # Budget: Jan to Jun 2026, per product line
    budget = []
    for month in range(1, 7):
        for line_name in ("Fish Tracking", "Aquaculture Intelligence"):
            amount = Decimal(random.randrange(60, 161) * 1000)
            budget.append({"BudgetMonth": date(2026, month, 1).isoformat(),
                           "ProductLine": line_name, "BudgetAmount": f"{amount:.2f}"})
    # 7. Budget amount that isn't a number
    budget.append({"BudgetMonth": "2026-07-01", "ProductLine": "Fish Tracking",
                   "BudgetAmount": "TBD"})

    write_csv("customers.csv", customers)
    write_csv("products.csv", products)
    write_csv("crm_deals.csv", deals)
    write_csv("sales_orders.csv", orders)
    write_csv("sales_order_lines.csv", lines)
    write_csv("budget.csv", budget)

    (DATA_DIR / "planted_issues.md").write_text(
        "# Planted issues (answer key)\n\n"
        "## Validation should quarantine\n"
        "1. SO-5041: customer C-9999 does not exist (its line is rejected too)\n"
        "2. SO-5042: impossible order date 2026-13-45 (its line is rejected too)\n"
        "3. SO-5010: duplicate order row (keep the first, reject the copy)\n"
        "4. SO-5002 line 9: unknown product RCV-999\n"
        "5. SO-5003 line 9: negative quantity -5\n"
        "6. C-1013: customer with no name\n"
        "7. Budget 2026-07-01 Fish Tracking: amount 'TBD' is not a number\n\n"
        "## Reconciliation should flag\n"
        "8. OPP-1041: Closed Won deal with no ERP order\n"
        f"9. {deals[4]['CrmDealId']}: deal amount is $1,500 higher than the order total\n\n"
        "## Normal (must NOT be flagged)\n"
        "- OPP-1042, OPP-1043, OPP-1044: Closed Lost deals without orders\n",
        encoding="utf-8",
    )
    print("planted_issues.md written")


if __name__ == "__main__":
    main()