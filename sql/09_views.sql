/* =====================================================================
   Step 8b: reusable reporting views (the rpt schema)
   Reports read from these, never straight from the tables, so every
   report uses the same definitions of "revenue", "order total", etc.
   ===================================================================== */
-- One row per order, with customer and totals: the building block for others
CREATE OR ALTER VIEW rpt.OrderSummary
AS
SELECT   o.SalesOrderId,
         o.OrderNumber,
         o.OrderDate,
         o.Status,
         o.CrmDealId,
         c.CustomerCode,
         c.CustomerName,
         c.Country,
         c.Region,
         SUM(l.Quantity) AS Units,
         SUM(l.LineAmount) AS OrderTotal
FROM     dbo.SalesOrder AS o
         INNER JOIN
         dbo.Customer AS c
         ON c.CustomerId = o.CustomerId
         INNER JOIN
         dbo.SalesOrderLine AS l
         ON l.SalesOrderId = o.SalesOrderId
GROUP BY o.SalesOrderId, o.OrderNumber, o.OrderDate, o.Status, o.CrmDealId, c.CustomerCode, c.CustomerName, c.Country, c.Region;


GO
-- Revenue by month and product line (for the Sales page)
CREATE OR ALTER VIEW rpt.SalesByMonth
AS
SELECT   DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1) AS SalesMonth,
         p.ProductLine,
         COUNT(DISTINCT o.SalesOrderId) AS Orders,
         SUM(l.Quantity) AS Units,
         SUM(l.LineAmount) AS Revenue
FROM     dbo.SalesOrder AS o
         INNER JOIN
         dbo.SalesOrderLine AS l
         ON l.SalesOrderId = o.SalesOrderId
         INNER JOIN
         dbo.Product AS p
         ON p.ProductId = l.ProductId
GROUP BY DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1), p.ProductLine;


GO
-- Open orders waiting to ship, oldest first (for the Operations page)
CREATE OR ALTER VIEW rpt.OrdersPendingShipment
AS
SELECT OrderNumber,
       CustomerName,
       Region,
       OrderDate,
       DATEDIFF(DAY, OrderDate, CAST (SYSUTCDATETIME() AS DATE)) AS DaysOpen,
       Units,
       OrderTotal
FROM   rpt.OrderSummary
WHERE  Status = 'Open';


GO
-- Budget (Adaptive) vs actual revenue (ERP), per month and product line
CREATE OR ALTER VIEW rpt.BudgetVsActual
AS
SELECT b.BudgetMonth,
       b.ProductLine,
       b.BudgetAmount,
       ISNULL(a.Revenue, 0) AS ActualRevenue,
       ISNULL(a.Revenue, 0) - b.BudgetAmount AS Variance,
       CASE WHEN b.BudgetAmount = 0 THEN NULL ELSE CAST ((ISNULL(a.Revenue, 0) - b.BudgetAmount) * 100.0 / b.BudgetAmount AS DECIMAL (9, 1)) END AS VariancePct
FROM   dbo.Budget AS b
       LEFT OUTER JOIN
       rpt.SalesByMonth AS a
       ON a.SalesMonth = b.BudgetMonth
          AND a.ProductLine = b.ProductLine;


GO
-- What was rejected in the latest run, and why (for the Data Quality page)
CREATE OR ALTER VIEW rpt.DataQuality
AS
SELECT   q.RunId,
         q.SourceTable,
         q.RuleName,
         COUNT(*) AS RowsRejected,
         MIN(q.Reason) AS ExampleReason
FROM     etl.Quarantine AS q
WHERE    q.RunId = (SELECT MAX(RunId)
                    FROM   etl.Quarantine)
GROUP BY q.RunId, q.SourceTable, q.RuleName;


GO
-- Where the CRM and ERP disagree, latest run (for the Data Quality page)
CREATE OR ALTER VIEW rpt.ReconciliationIssues
AS
SELECT RunId,
       Issue,
       CrmDealId,
       OrderNumber,
       CustomerCode,
       CrmAmount,
       ErpAmount,
       Difference,
       Detail
FROM   etl.ReconciliationResult
WHERE  RunId = (SELECT MAX(RunId)
                FROM   etl.ReconciliationResult);


GO
-- Quick look at each view
SELECT   TOP 5 *
FROM     rpt.SalesByMonth
ORDER BY SalesMonth DESC;

SELECT   TOP 5 *
FROM     rpt.OrdersPendingShipment
ORDER BY DaysOpen DESC;

SELECT   *
FROM     rpt.BudgetVsActual
ORDER BY BudgetMonth, ProductLine;

SELECT *
FROM   rpt.DataQuality;

SELECT *
FROM   rpt.ReconciliationIssues;