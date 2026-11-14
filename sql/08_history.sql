/* =====================================================================
   Step 8a: two years of historical, already-invoiced orders (2024-2025)
   so performance tuning is realistic. History has no CRM deal, so
   reconciliation ignores it. Order numbers start with H-. Safe to re-run.
   ===================================================================== */
SET NOCOUNT ON;

-- Re-run safety: remove previous history (lines first, then orders)
DELETE l
FROM   dbo.SalesOrderLine AS l
       INNER JOIN
       dbo.SalesOrder AS o
       ON o.SalesOrderId = l.SalesOrderId
WHERE  o.OrderNumber LIKE 'H-%';

DELETE dbo.SalesOrder
WHERE  OrderNumber LIKE 'H-%';

-- Numbered lists of customers and products to spread orders across
SELECT CustomerId,
       ROW_NUMBER() OVER (ORDER BY CustomerId) - 1 AS rn
INTO   #C
FROM   dbo.Customer;

SELECT ProductId,
       UnitPrice,
       ROW_NUMBER() OVER (ORDER BY ProductId) - 1 AS rn
INTO   #P
FROM   dbo.Product;

DECLARE @customers AS INT = (SELECT COUNT(*)
                             FROM   #C);

DECLARE @products AS INT = (SELECT COUNT(*)
                            FROM   #P);

-- 40,000 orders spread over 2024 and 2025
WITH n
AS   (SELECT TOP (40000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
      FROM   sys.all_objects AS a
             CROSS JOIN sys.all_objects AS b)
INSERT INTO dbo.SalesOrder (
    OrderNumber,
    CustomerId,
    OrderDate,
    Status,
    CrmDealId
)
SELECT CONCAT('H-', RIGHT(CONCAT('000000', n.i), 6)),
       c.CustomerId,
       DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 731, CAST ('2024-01-01' AS DATE)),
       'Invoiced',
       NULL
FROM   n
       INNER JOIN
       #C AS c
       ON c.rn = n.i % @customers;

-- 1 to 3 lines per historical order
INSERT INTO dbo.SalesOrderLine (
    SalesOrderId,
    LineNumber,
    ProductId,
    Quantity,
    UnitPrice
)
SELECT o.SalesOrderId,
       v.LineNumber,
       p.ProductId,
       1 + ABS(CHECKSUM(NEWID())) % 20,
       p.UnitPrice
FROM   dbo.SalesOrder AS o
       CROSS JOIN (VALUES (1), (2), (3)) AS v(LineNumber)
       INNER JOIN
       #P AS p
       ON p.rn = (o.SalesOrderId + v.LineNumber) % @products
WHERE  o.OrderNumber LIKE 'H-%'
       AND v.LineNumber <= 1 + o.SalesOrderId % 3;

-- Check
SELECT (SELECT COUNT(*)
        FROM   dbo.SalesOrder) AS total_orders,
       (SELECT COUNT(*)
        FROM   dbo.SalesOrderLine) AS total_lines;