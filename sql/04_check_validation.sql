-- 1. Every rejected row, with the rule, the reason and the original data
SELECT   q.SourceTable,
         q.RuleName,
         q.Reason,
         q.RawRecord
FROM     etl.Quarantine AS q
WHERE    q.RunId = (SELECT MAX(RunId)
                    FROM   etl.RunLog)
ORDER BY q.SourceTable, q.RuleName;

-- 2. Valid vs rejected per table
SELECT   'stg.Customer' AS staging_table,
         ValidationStatus,
         COUNT(*) AS row_count
FROM     stg.Customer
GROUP BY ValidationStatus
UNION ALL
SELECT   'stg.Product',
         ValidationStatus,
         COUNT(*)
FROM     stg.Product
GROUP BY ValidationStatus
UNION ALL
SELECT   'stg.CrmDeal',
         ValidationStatus,
         COUNT(*)
FROM     stg.CrmDeal
GROUP BY ValidationStatus
UNION ALL
SELECT   'stg.SalesOrder',
         ValidationStatus,
         COUNT(*)
FROM     stg.SalesOrder
GROUP BY ValidationStatus
UNION ALL
SELECT   'stg.SalesOrderLine',
         ValidationStatus,
         COUNT(*)
FROM     stg.SalesOrderLine
GROUP BY ValidationStatus
UNION ALL
SELECT   'stg.Budget',
         ValidationStatus,
         COUNT(*)
FROM     stg.Budget
GROUP BY ValidationStatus
ORDER BY staging_table, ValidationStatus;

-- 3. The run log now shows how many rows were rejected
SELECT   RunId,
         Status,
         RowsLoaded,
         RowsRejected
FROM     etl.RunLog
ORDER BY RunId DESC;