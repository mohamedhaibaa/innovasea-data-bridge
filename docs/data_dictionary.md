# Data dictionary

## Schemas

| Schema | Purpose                                                 |
| ------ | ------------------------------------------------------- |
| `stg`  | Raw data as it arrived; all text, nothing enforced      |
| `dbo`  | Clean system of record; typed, keyed, constrained       |
| `etl`  | Run log, quarantine, reconciliation results, procedures |
| `rpt`  | Reporting views; the only thing the dashboard can read  |

## Clean tables (`dbo`)

| Table            | Mirrors                  | Business key                  | Notes                                                            |
| ---------------- | ------------------------ | ----------------------------- | ---------------------------------------------------------------- |
| `Customer`       | SYSPRO customers         | `CustomerCode`                | `Email` is masked for readers                                    |
| `Product`        | SYSPRO stock items       | `ProductCode`                 | `UnitPrice` DECIMAL(18,2), >= 0                                  |
| `CrmDeal`        | Salesforce opportunities | `CrmDealId`                   | No FK to Customer on purpose, so reconciliation can find gaps    |
| `SalesOrder`     | SYSPRO order headers     | `OrderNumber`                 | Links to deal via `CrmDealId`; `H-` orders are generated history |
| `SalesOrderLine` | SYSPRO order lines       | `SalesOrderId` + `LineNumber` | `LineAmount` is calculated, never typed                          |
| `Budget`         | Adaptive monthly plan    | `BudgetMonth` + `ProductLine` | Month is always the 1st                                          |

Every clean table has `LastRunId` (which run last changed it); most have
`CreatedAtUtc` / `UpdatedAtUtc`. All times are UTC.

## Control tables (`etl`)

| Table                  | Purpose                                                    |
| ---------------------- | ---------------------------------------------------------- |
| `RunLog`               | One row per run: status, rows loaded, rows rejected, error |
| `Quarantine`           | Every rejected row: rule, reason, original row as JSON     |
| `ReconciliationResult` | Every CRM vs ERP gap, per run                              |

## Stored procedures (`etl`)

| Procedure             | Does                                          |
| --------------------- | --------------------------------------------- |
| `usp_ValidateStaging` | Checks every staged row; quarantines failures |
| `usp_MergeToClean`    | Inserts new and updates changed rows in `dbo` |
| `usp_Reconcile`       | Compares CRM deals with ERP orders            |

## Reporting views (`rpt`)

| View                    | Used for                                                  |
| ----------------------- | --------------------------------------------------------- |
| `OrderSummary`          | One row per order with customer and total; building block |
| `SalesByMonth`          | Revenue by month and product line                         |
| `OrdersPendingShipment` | Open orders, oldest first                                 |
| `BudgetVsActual`        | Adaptive budget vs ERP revenue                            |
| `DataQuality`           | Rejections in the latest run                              |
| `ReconciliationIssues`  | CRM vs ERP gaps in the latest run                         |
| `LatestRun`             | Status of the latest run                                  |
| `CustomerDirectory`     | Customer list (emails masked)                             |
