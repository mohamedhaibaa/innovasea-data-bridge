/* =====================================================================
   Step 5: validation and quarantine
   Checks every staged row for one run. Bad rows go to etl.Quarantine
   with the rule and the original data; good rows are marked VALID.
   Safe to re-run for the same RunId.
   ===================================================================== */
CREATE OR ALTER PROCEDURE etl.usp_ValidateStaging
@RunId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON; -- any error rolls back the whole validation
    BEGIN TRANSACTION;
    -- Re-run safety: clear previous results for this run
    DELETE etl.Quarantine
    WHERE  RunId = @RunId;
    UPDATE stg.Customer
    SET    ValidationStatus = NULL
    WHERE  RunId = @RunId;
    UPDATE stg.Product
    SET    ValidationStatus = NULL
    WHERE  RunId = @RunId;
    UPDATE stg.CrmDeal
    SET    ValidationStatus = NULL
    WHERE  RunId = @RunId;
    UPDATE stg.SalesOrder
    SET    ValidationStatus = NULL
    WHERE  RunId = @RunId;
    UPDATE stg.SalesOrderLine
    SET    ValidationStatus = NULL
    WHERE  RunId = @RunId;
    UPDATE stg.Budget
    SET    ValidationStatus = NULL
    WHERE  RunId = @RunId;
    -- Every failed check lands here first: one row per rule broken
    CREATE TABLE #Failures (
        SourceTable NVARCHAR (100) NOT NULL,
        StgRowId    INT            NOT NULL,
        RuleName    NVARCHAR (100) NOT NULL,
        Reason      NVARCHAR (400) NOT NULL
    );
    /* ---------------- 1. Customers ---------------- */
    INSERT INTO #Failures
    SELECT 'stg.Customer',
           StgRowId,
           'MissingRequiredField',
           'Customer code and name are required'
    FROM   stg.Customer
    WHERE  RunId = @RunId
           AND (CustomerCode IS NULL
                OR CustomerName IS NULL);
    INSERT INTO #Failures
    SELECT 'stg.Customer',
           StgRowId,
           'DuplicateCustomer',
           CONCAT('Customer ', CustomerCode, ' appears more than once')
    FROM   (SELECT StgRowId,
                   CustomerCode,
                   ROW_NUMBER() OVER (PARTITION BY CustomerCode ORDER BY StgRowId) AS rn
            FROM   stg.Customer
            WHERE  RunId = @RunId
                   AND CustomerCode IS NOT NULL) AS d
    WHERE  rn > 1;
    UPDATE s
    SET    ValidationStatus = CASE WHEN EXISTS (SELECT 1
                                                FROM   #Failures AS f
                                                WHERE  f.SourceTable = 'stg.Customer'
                                                       AND f.StgRowId = s.StgRowId) THEN 'REJECTED' ELSE 'VALID' END
    FROM   stg.Customer AS s
    WHERE  s.RunId = @RunId;
    /* ---------------- 2. Products ---------------- */
    INSERT INTO #Failures
    SELECT 'stg.Product',
           StgRowId,
           'MissingRequiredField',
           'Product code, name and product line are required'
    FROM   stg.Product
    WHERE  RunId = @RunId
           AND (ProductCode IS NULL
                OR ProductName IS NULL
                OR ProductLine IS NULL);
    INSERT INTO #Failures
    SELECT 'stg.Product',
           StgRowId,
           'InvalidPrice',
           CONCAT('Unit price "', UnitPrice, '" is not a number >= 0')
    FROM   stg.Product
    WHERE  RunId = @RunId
           AND (TRY_CONVERT (DECIMAL (18, 2), UnitPrice) IS NULL
                OR TRY_CONVERT (DECIMAL (18, 2), UnitPrice) < 0);
    INSERT INTO #Failures
    SELECT 'stg.Product',
           StgRowId,
           'DuplicateProduct',
           CONCAT('Product ', ProductCode, ' appears more than once')
    FROM   (SELECT StgRowId,
                   ProductCode,
                   ROW_NUMBER() OVER (PARTITION BY ProductCode ORDER BY StgRowId) AS rn
            FROM   stg.Product
            WHERE  RunId = @RunId
                   AND ProductCode IS NOT NULL) AS d
    WHERE  rn > 1;
    UPDATE s
    SET    ValidationStatus = CASE WHEN EXISTS (SELECT 1
                                                FROM   #Failures AS f
                                                WHERE  f.SourceTable = 'stg.Product'
                                                       AND f.StgRowId = s.StgRowId) THEN 'REJECTED' ELSE 'VALID' END
    FROM   stg.Product AS s
    WHERE  s.RunId = @RunId;
    /* ---------------- 3. CRM deals ---------------- */
    INSERT INTO #Failures
    SELECT 'stg.CrmDeal',
           StgRowId,
           'MissingRequiredField',
           'Deal ID, customer, deal name and stage are required'
    FROM   stg.CrmDeal
    WHERE  RunId = @RunId
           AND (CrmDealId IS NULL
                OR CustomerCode IS NULL
                OR DealName IS NULL
                OR Stage IS NULL);
    INSERT INTO #Failures
    SELECT 'stg.CrmDeal',
           StgRowId,
           'InvalidAmount',
           CONCAT('Amount "', Amount, '" is not a number >= 0')
    FROM   stg.CrmDeal
    WHERE  RunId = @RunId
           AND (TRY_CONVERT (DECIMAL (18, 2), Amount) IS NULL
                OR TRY_CONVERT (DECIMAL (18, 2), Amount) < 0);
    INSERT INTO #Failures
    SELECT 'stg.CrmDeal',
           StgRowId,
           'InvalidCloseDate',
           CONCAT('Close date "', CloseDate, '" is not a valid date')
    FROM   stg.CrmDeal
    WHERE  RunId = @RunId
           AND TRY_CONVERT (DATE, CloseDate, 23) IS NULL;
    INSERT INTO #Failures
    SELECT 'stg.CrmDeal',
           StgRowId,
           'DuplicateDeal',
           CONCAT('Deal ', CrmDealId, ' appears more than once')
    FROM   (SELECT StgRowId,
                   CrmDealId,
                   ROW_NUMBER() OVER (PARTITION BY CrmDealId ORDER BY StgRowId) AS rn
            FROM   stg.CrmDeal
            WHERE  RunId = @RunId
                   AND CrmDealId IS NOT NULL) AS d
    WHERE  rn > 1;
    UPDATE s
    SET    ValidationStatus = CASE WHEN EXISTS (SELECT 1
                                                FROM   #Failures AS f
                                                WHERE  f.SourceTable = 'stg.CrmDeal'
                                                       AND f.StgRowId = s.StgRowId) THEN 'REJECTED' ELSE 'VALID' END
    FROM   stg.CrmDeal AS s
    WHERE  s.RunId = @RunId;
    /* ---------------- 4. Sales orders ---------------- */
    INSERT INTO #Failures
    SELECT 'stg.SalesOrder',
           StgRowId,
           'MissingRequiredField',
           'Order number and customer are required'
    FROM   stg.SalesOrder
    WHERE  RunId = @RunId
           AND (OrderNumber IS NULL
                OR CustomerCode IS NULL);
    INSERT INTO #Failures
    SELECT 'stg.SalesOrder',
           StgRowId,
           'DuplicateOrder',
           CONCAT('Order ', OrderNumber, ' appears more than once; first copy kept')
    FROM   (SELECT StgRowId,
                   OrderNumber,
                   ROW_NUMBER() OVER (PARTITION BY OrderNumber ORDER BY StgRowId) AS rn
            FROM   stg.SalesOrder
            WHERE  RunId = @RunId
                   AND OrderNumber IS NOT NULL) AS d
    WHERE  rn > 1;
    INSERT INTO #Failures
    SELECT 'stg.SalesOrder',
           o.StgRowId,
           'UnknownCustomer',
           CONCAT('Customer ', o.CustomerCode, ' does not exist')
    FROM   stg.SalesOrder AS o
    WHERE  o.RunId = @RunId
           AND o.CustomerCode IS NOT NULL
           AND NOT EXISTS (SELECT 1
                           FROM   stg.Customer AS c
                           WHERE  c.RunId = @RunId
                                  AND c.ValidationStatus = 'VALID'
                                  AND c.CustomerCode = o.CustomerCode)
           AND NOT EXISTS (SELECT 1
                           FROM   dbo.Customer AS c
                           WHERE  c.CustomerCode = o.CustomerCode);
    INSERT INTO #Failures
    SELECT 'stg.SalesOrder',
           StgRowId,
           'InvalidOrderDate',
           CONCAT('Order date "', OrderDate, '" is not a valid date')
    FROM   stg.SalesOrder
    WHERE  RunId = @RunId
           AND TRY_CONVERT (DATE, OrderDate, 23) IS NULL;
    INSERT INTO #Failures
    SELECT 'stg.SalesOrder',
           StgRowId,
           'InvalidStatus',
           CONCAT('Status "', Status, '" must be Open, Shipped or Invoiced')
    FROM   stg.SalesOrder
    WHERE  RunId = @RunId
           AND (Status IS NULL
                OR Status NOT IN ('Open', 'Shipped', 'Invoiced'));
    UPDATE s
    SET    ValidationStatus = CASE WHEN EXISTS (SELECT 1
                                                FROM   #Failures AS f
                                                WHERE  f.SourceTable = 'stg.SalesOrder'
                                                       AND f.StgRowId = s.StgRowId) THEN 'REJECTED' ELSE 'VALID' END
    FROM   stg.SalesOrder AS s
    WHERE  s.RunId = @RunId;
    /* ---------------- 5. Sales order lines ---------------- */
    INSERT INTO #Failures
    SELECT 'stg.SalesOrderLine',
           l.StgRowId,
           'ParentOrderRejected',
           CONCAT('Order ', l.OrderNumber, ' was rejected or does not exist')
    FROM   stg.SalesOrderLine AS l
    WHERE  l.RunId = @RunId
           AND NOT EXISTS (SELECT 1
                           FROM   stg.SalesOrder AS o
                           WHERE  o.RunId = @RunId
                                  AND o.ValidationStatus = 'VALID'
                                  AND o.OrderNumber = l.OrderNumber)
           AND NOT EXISTS (SELECT 1
                           FROM   dbo.SalesOrder AS o
                           WHERE  o.OrderNumber = l.OrderNumber);
    INSERT INTO #Failures
    SELECT 'stg.SalesOrderLine',
           l.StgRowId,
           'UnknownProduct',
           CONCAT('Product ', l.ProductCode, ' does not exist')
    FROM   stg.SalesOrderLine AS l
    WHERE  l.RunId = @RunId
           AND NOT EXISTS (SELECT 1
                           FROM   stg.Product AS p
                           WHERE  p.RunId = @RunId
                                  AND p.ValidationStatus = 'VALID'
                                  AND p.ProductCode = l.ProductCode)
           AND NOT EXISTS (SELECT 1
                           FROM   dbo.Product AS p
                           WHERE  p.ProductCode = l.ProductCode);
    INSERT INTO #Failures
    SELECT 'stg.SalesOrderLine',
           StgRowId,
           'InvalidQuantity',
           CONCAT('Quantity "', Quantity, '" must be a whole number above 0')
    FROM   stg.SalesOrderLine
    WHERE  RunId = @RunId
           AND (TRY_CONVERT (INT, Quantity) IS NULL
                OR TRY_CONVERT (INT, Quantity) <= 0);
    INSERT INTO #Failures
    SELECT 'stg.SalesOrderLine',
           StgRowId,
           'InvalidPrice',
           CONCAT('Unit price "', UnitPrice, '" is not a number >= 0')
    FROM   stg.SalesOrderLine
    WHERE  RunId = @RunId
           AND (TRY_CONVERT (DECIMAL (18, 2), UnitPrice) IS NULL
                OR TRY_CONVERT (DECIMAL (18, 2), UnitPrice) < 0);
    INSERT INTO #Failures
    SELECT 'stg.SalesOrderLine',
           StgRowId,
           'InvalidLineNumber',
           CONCAT('Line number "', LineNumber, '" is not a whole number')
    FROM   stg.SalesOrderLine
    WHERE  RunId = @RunId
           AND TRY_CONVERT (INT, LineNumber) IS NULL;
    INSERT INTO #Failures
    SELECT 'stg.SalesOrderLine',
           StgRowId,
           'DuplicateLine',
           CONCAT('Order ', OrderNumber, ' line ', LineNumber, ' appears more than once')
    FROM   (SELECT StgRowId,
                   OrderNumber,
                   LineNumber,
                   ROW_NUMBER() OVER (PARTITION BY OrderNumber, LineNumber ORDER BY StgRowId) AS rn
            FROM   stg.SalesOrderLine
            WHERE  RunId = @RunId) AS d
    WHERE  rn > 1;
    UPDATE s
    SET    ValidationStatus = CASE WHEN EXISTS (SELECT 1
                                                FROM   #Failures AS f
                                                WHERE  f.SourceTable = 'stg.SalesOrderLine'
                                                       AND f.StgRowId = s.StgRowId) THEN 'REJECTED' ELSE 'VALID' END
    FROM   stg.SalesOrderLine AS s
    WHERE  s.RunId = @RunId;
    /* ---------------- 6. Budget ---------------- */
    INSERT INTO #Failures
    SELECT 'stg.Budget',
           StgRowId,
           'InvalidMonth',
           CONCAT('Budget month "', BudgetMonth, '" must be a valid date on the 1st')
    FROM   stg.Budget
    WHERE  RunId = @RunId
           AND (TRY_CONVERT (DATE, BudgetMonth, 23) IS NULL
                OR DAY(TRY_CONVERT (DATE, BudgetMonth, 23)) <> 1);
    INSERT INTO #Failures
    SELECT 'stg.Budget',
           StgRowId,
           'MissingRequiredField',
           'Product line is required'
    FROM   stg.Budget
    WHERE  RunId = @RunId
           AND ProductLine IS NULL;
    INSERT INTO #Failures
    SELECT 'stg.Budget',
           StgRowId,
           'InvalidAmount',
           CONCAT('Budget amount "', BudgetAmount, '" is not a number >= 0')
    FROM   stg.Budget
    WHERE  RunId = @RunId
           AND (TRY_CONVERT (DECIMAL (18, 2), BudgetAmount) IS NULL
                OR TRY_CONVERT (DECIMAL (18, 2), BudgetAmount) < 0);
    INSERT INTO #Failures
    SELECT 'stg.Budget',
           StgRowId,
           'DuplicateBudget',
           CONCAT('Budget for ', BudgetMonth, ' / ', ProductLine, ' appears more than once')
    FROM   (SELECT StgRowId,
                   BudgetMonth,
                   ProductLine,
                   ROW_NUMBER() OVER (PARTITION BY BudgetMonth, ProductLine ORDER BY StgRowId) AS rn
            FROM   stg.Budget
            WHERE  RunId = @RunId) AS d
    WHERE  rn > 1;
    UPDATE s
    SET    ValidationStatus = CASE WHEN EXISTS (SELECT 1
                                                FROM   #Failures AS f
                                                WHERE  f.SourceTable = 'stg.Budget'
                                                       AND f.StgRowId = s.StgRowId) THEN 'REJECTED' ELSE 'VALID' END
    FROM   stg.Budget AS s
    WHERE  s.RunId = @RunId;
    /* ---------------- 7. Quarantine, with the original row as JSON ---------------- */
    INSERT INTO etl.Quarantine (
        RunId,
        SourceTable,
        StgRowId,
        RuleName,
        Reason,
        RawRecord
    )
    SELECT @RunId,
           f.SourceTable,
           f.StgRowId,
           f.RuleName,
           f.Reason,
           CASE f.SourceTable WHEN 'stg.Customer' THEN (SELECT x.*
                                                        FROM   stg.Customer AS x
                                                        WHERE  x.StgRowId = f.StgRowId
                                                        FOR    JSON PATH, WITHOUT_ARRAY_WRAPPER) WHEN 'stg.Product' THEN (SELECT x.*
                                                                                                                          FROM   stg.Product AS x
                                                                                                                          WHERE  x.StgRowId = f.StgRowId
                                                                                                                          FOR    JSON PATH, WITHOUT_ARRAY_WRAPPER) WHEN 'stg.CrmDeal' THEN (SELECT x.*
                                                                                                                                                                                            FROM   stg.CrmDeal AS x
                                                                                                                                                                                            WHERE  x.StgRowId = f.StgRowId
                                                                                                                                                                                            FOR    JSON PATH, WITHOUT_ARRAY_WRAPPER) WHEN 'stg.SalesOrder' THEN (SELECT x.*
                                                                                                                                                                                                                                                                 FROM   stg.SalesOrder AS x
                                                                                                                                                                                                                                                                 WHERE  x.StgRowId = f.StgRowId
                                                                                                                                                                                                                                                                 FOR    JSON PATH, WITHOUT_ARRAY_WRAPPER) WHEN 'stg.SalesOrderLine' THEN (SELECT x.*
                                                                                                                                                                                                                                                                                                                                          FROM   stg.SalesOrderLine AS x
                                                                                                                                                                                                                                                                                                                                          WHERE  x.StgRowId = f.StgRowId
                                                                                                                                                                                                                                                                                                                                          FOR    JSON PATH, WITHOUT_ARRAY_WRAPPER) WHEN 'stg.Budget' THEN (SELECT x.*
                                                                                                                                                                                                                                                                                                                                                                                                           FROM   stg.Budget AS x
                                                                                                                                                                                                                                                                                                                                                                                                           WHERE  x.StgRowId = f.StgRowId
                                                                                                                                                                                                                                                                                                                                                                                                           FOR    JSON PATH, WITHOUT_ARRAY_WRAPPER) END
    FROM   #Failures AS f;
    -- Record how many distinct rows were rejected on the run log
    UPDATE etl.RunLog
    SET    RowsRejected = (SELECT COUNT(*)
                           FROM   (SELECT DISTINCT SourceTable,
                                                   StgRowId
                                   FROM   #Failures) AS d)
    WHERE  RunId = @RunId;
    COMMIT TRANSACTION;
    -- Summary for whoever called it
    SELECT   SourceTable,
             RuleName,
             COUNT(*) AS RowsFailed
    FROM     #Failures
    GROUP BY SourceTable, RuleName
    ORDER BY SourceTable, RuleName;
END