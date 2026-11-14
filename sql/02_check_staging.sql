-- 1. The run log: what ran, when, and how it went
SELECT   TOP 5 RunId,
               PipelineName,
               StartedAtUtc,
               EndedAtUtc,
               Status,
               RowsLoaded,
               ErrorMessage
FROM     etl.RunLog
ORDER BY RunId DESC;

-- 2. Row counts per staging table
SELECT 'stg.Customer' AS staging_table,
       COUNT(*) AS row_count
FROM   stg.Customer
UNION ALL
SELECT 'stg.Product',
       COUNT(*)
FROM   stg.Product
UNION ALL
SELECT 'stg.CrmDeal',
       COUNT(*)
FROM   stg.CrmDeal
UNION ALL
SELECT 'stg.SalesOrder',
       COUNT(*)
FROM   stg.SalesOrder
UNION ALL
SELECT 'stg.SalesOrderLine',
       COUNT(*)
FROM   stg.SalesOrderLine
UNION ALL
SELECT 'stg.Budget',
       COUNT(*)
FROM   stg.Budget;

-- 3. The bad rows arrived too, unchanged, waiting to be checked
SELECT   StgRowId,
         OrderNumber,
         CustomerCode,
         OrderDate,
         ValidationStatus
FROM     stg.SalesOrder
WHERE    OrderNumber IN ('SO-5010', 'SO-5041', 'SO-5042')
ORDER BY OrderNumber, StgRowId;