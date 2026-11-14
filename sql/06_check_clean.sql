-- 1. Row counts in the system of record
SELECT 'dbo.Customer' AS clean_table,
       COUNT(*) AS row_count
FROM   dbo.Customer
UNION ALL
SELECT 'dbo.Product',
       COUNT(*)
FROM   dbo.Product
UNION ALL
SELECT 'dbo.CrmDeal',
       COUNT(*)
FROM   dbo.CrmDeal
UNION ALL
SELECT 'dbo.SalesOrder',
       COUNT(*)
FROM   dbo.SalesOrder
UNION ALL
SELECT 'dbo.SalesOrderLine',
       COUNT(*)
FROM   dbo.SalesOrderLine
UNION ALL
SELECT 'dbo.Budget',
       COUNT(*)
FROM   dbo.Budget;

-- 2. The clean data joined together: orders with customer, total and source deal
SELECT   TOP 10 o.OrderNumber,
                c.CustomerName,
                o.OrderDate,
                o.Status,
                o.CrmDealId,
                SUM(l.LineAmount) AS OrderTotal
FROM     dbo.SalesOrder AS o
         INNER JOIN
         dbo.Customer AS c
         ON c.CustomerId = o.CustomerId
         INNER JOIN
         dbo.SalesOrderLine AS l
         ON l.SalesOrderId = o.SalesOrderId
GROUP BY o.OrderNumber, c.CustomerName, o.OrderDate, o.Status, o.CrmDealId
ORDER BY o.OrderNumber;

-- 3. None of the bad data made it in
SELECT 'Unknown customer C-9999' AS check_name,
       COUNT(*) AS found
FROM   dbo.SalesOrder AS o
       INNER JOIN
       dbo.Customer AS c
       ON c.CustomerId = o.CustomerId
WHERE  c.CustomerCode = 'C-9999'
UNION ALL
SELECT 'Order SO-5041 or SO-5042',
       COUNT(*)
FROM   dbo.SalesOrder
WHERE  OrderNumber IN ('SO-5041', 'SO-5042')
UNION ALL
SELECT 'SO-5010 stored more than once',
       COUNT(*) - 1
FROM   dbo.SalesOrder
WHERE  OrderNumber = 'SO-5010'
UNION ALL
SELECT 'Negative quantities',
       COUNT(*)
FROM   dbo.SalesOrderLine
WHERE  Quantity <= 0;