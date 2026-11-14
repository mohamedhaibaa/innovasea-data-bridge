/* =====================================================================
   Step 8c: refactoring a "legacy" report query
   Same question both times: every order in March 2025, with customer
   and total. Run this file BEFORE and AFTER adding indexes (11_indexes.sql)
   and compare the logical reads in the Messages tab.
   ===================================================================== */
SET STATISTICS IO ON; -- how many data pages each query reads

SET STATISTICS TIME ON; -- CPU and elapsed time

-- LEGACY: works, but...
--   1. YEAR()/MONTH() on the column stops SQL Server from using an index
--   2. SELECT * returns columns nobody needs
--   3. Correlated subqueries run once per order
--   4. Recalculates Quantity * UnitPrice instead of using LineAmount
SELECT   *,
         (SELECT c.CustomerName
          FROM   dbo.Customer AS c
          WHERE  c.CustomerId = o.CustomerId) AS CustomerName,
         (SELECT SUM(l.Quantity * l.UnitPrice)
          FROM   dbo.SalesOrderLine AS l
          WHERE  l.SalesOrderId = o.SalesOrderId) AS OrderTotal
FROM     dbo.SalesOrder AS o
WHERE    YEAR(o.OrderDate) = 2025
         AND MONTH(o.OrderDate) = 3
ORDER BY o.OrderDate;

-- REFACTORED: same answer, but...
--   1. A date range the index can use
--   2. Only the columns the report needs
--   3. Reuses the shared rpt.OrderSummary view (one definition of "order total")
SELECT   OrderNumber,
         OrderDate,
         CustomerName,
         OrderTotal
FROM     rpt.OrderSummary
WHERE    OrderDate >= '2025-03-01'
         AND OrderDate < '2025-04-01'
ORDER BY OrderDate;

SET STATISTICS IO OFF;

SET STATISTICS TIME OFF;