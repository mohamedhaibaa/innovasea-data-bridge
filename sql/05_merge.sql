/* =====================================================================
   Step 6: MERGE valid staging rows into the clean tables (system of record)
   Insert new records, update changed ones, leave unchanged ones alone.
   Idempotent: running it twice for the same run changes nothing the 2nd time.
   ===================================================================== */
CREATE OR ALTER PROCEDURE etl.usp_MergeToClean
@RunId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    -- What MERGE did, for the summary at the end
    CREATE TABLE #Actions (
        TableName NVARCHAR (100),
        Action    NVARCHAR (10) 
    );
    BEGIN TRANSACTION;
    /* ---------------- 1. Customers ---------------- */
    MERGE INTO dbo.Customer
     AS t
    USING (SELECT CustomerCode,
                  CustomerName,
                  Country,
                  Region,
                  Email
           FROM   stg.Customer
           WHERE  RunId = @RunId
                  AND ValidationStatus = 'VALID') AS s ON t.CustomerCode = s.CustomerCode
    -- Update only if something actually changed (EXCEPT also compares NULLs safely)
    WHEN MATCHED AND EXISTS (SELECT s.CustomerName,
                                    s.Country,
                                    s.Region,
                                    s.Email
                             EXCEPT
                             SELECT t.CustomerName,
                                    t.Country,
                                    t.Region,
                                    t.Email) THEN UPDATE 
    SET CustomerName = s.CustomerName,
        Country      = s.Country,
        Region       = s.Region,
        Email        = s.Email,
        UpdatedAtUtc = SYSUTCDATETIME(),
        LastRunId    = @RunId
    WHEN NOT MATCHED BY TARGET THEN INSERT (
        CustomerCode,
        CustomerName,
        Country,
        Region,
        Email,
        LastRunId
    ) VALUES (s.CustomerCode, s.CustomerName, s.Country, s.Region, s.Email, @RunId)
    OUTPUT 'dbo.Customer', $ACTION INTO #Actions (TableName, Action);
    /* ---------------- 2. Products ---------------- */
    MERGE INTO dbo.Product
     AS t
    USING (SELECT ProductCode,
                  ProductName,
                  ProductLine,
                  TRY_CONVERT (DECIMAL (18, 2), UnitPrice) AS UnitPrice
           FROM   stg.Product
           WHERE  RunId = @RunId
                  AND ValidationStatus = 'VALID') AS s ON t.ProductCode = s.ProductCode
    WHEN MATCHED AND EXISTS (SELECT s.ProductName,
                                    s.ProductLine,
                                    s.UnitPrice
                             EXCEPT
                             SELECT t.ProductName,
                                    t.ProductLine,
                                    t.UnitPrice) THEN UPDATE 
    SET ProductName  = s.ProductName,
        ProductLine  = s.ProductLine,
        UnitPrice    = s.UnitPrice,
        UpdatedAtUtc = SYSUTCDATETIME(),
        LastRunId    = @RunId
    WHEN NOT MATCHED BY TARGET THEN INSERT (
        ProductCode,
        ProductName,
        ProductLine,
        UnitPrice,
        LastRunId
    ) VALUES (s.ProductCode, s.ProductName, s.ProductLine, s.UnitPrice, @RunId)
    OUTPUT 'dbo.Product', $ACTION INTO #Actions (TableName, Action);
    /* ---------------- 3. CRM deals ---------------- */
    MERGE INTO dbo.CrmDeal
     AS t
    USING (SELECT CrmDealId,
                  CustomerCode,
                  DealName,
                  TRY_CONVERT (DECIMAL (18, 2), Amount) AS Amount,
                  Stage,
                  TRY_CONVERT (DATE, CloseDate, 23) AS CloseDate
           FROM   stg.CrmDeal
           WHERE  RunId = @RunId
                  AND ValidationStatus = 'VALID') AS s ON t.CrmDealId = s.CrmDealId
    WHEN MATCHED AND EXISTS (SELECT s.CustomerCode,
                                    s.DealName,
                                    s.Amount,
                                    s.Stage,
                                    s.CloseDate
                             EXCEPT
                             SELECT t.CustomerCode,
                                    t.DealName,
                                    t.Amount,
                                    t.Stage,
                                    t.CloseDate) THEN UPDATE 
    SET CustomerCode = s.CustomerCode,
        DealName     = s.DealName,
        Amount       = s.Amount,
        Stage        = s.Stage,
        CloseDate    = s.CloseDate,
        UpdatedAtUtc = SYSUTCDATETIME(),
        LastRunId    = @RunId
    WHEN NOT MATCHED BY TARGET THEN INSERT (
        CrmDealId,
        CustomerCode,
        DealName,
        Amount,
        Stage,
        CloseDate,
        LastRunId
    ) VALUES (s.CrmDealId, s.CustomerCode, s.DealName, s.Amount, s.Stage, s.CloseDate, @RunId)
    OUTPUT 'dbo.CrmDeal', $ACTION INTO #Actions (TableName, Action);
    /* ---------------- 4. Sales orders (look up the customer's ID) ---------------- */
    MERGE INTO dbo.SalesOrder
     AS t
    USING (SELECT s.OrderNumber,
                  c.CustomerId,
                  TRY_CONVERT (DATE, s.OrderDate, 23) AS OrderDate,
                  s.Status,
                  s.CrmDealId
           FROM   stg.SalesOrder AS s
                  INNER JOIN
                  dbo.Customer AS c
                  ON c.CustomerCode = s.CustomerCode
           WHERE  s.RunId = @RunId
                  AND s.ValidationStatus = 'VALID') AS s ON t.OrderNumber = s.OrderNumber
    WHEN MATCHED AND EXISTS (SELECT s.CustomerId,
                                    s.OrderDate,
                                    s.Status,
                                    s.CrmDealId
                             EXCEPT
                             SELECT t.CustomerId,
                                    t.OrderDate,
                                    t.Status,
                                    t.CrmDealId) THEN UPDATE 
    SET CustomerId   = s.CustomerId,
        OrderDate    = s.OrderDate,
        Status       = s.Status,
        CrmDealId    = s.CrmDealId,
        UpdatedAtUtc = SYSUTCDATETIME(),
        LastRunId    = @RunId
    WHEN NOT MATCHED BY TARGET THEN INSERT (
        OrderNumber,
        CustomerId,
        OrderDate,
        Status,
        CrmDealId,
        LastRunId
    ) VALUES (s.OrderNumber, s.CustomerId, s.OrderDate, s.Status, s.CrmDealId, @RunId)
    OUTPUT 'dbo.SalesOrder', $ACTION INTO #Actions (TableName, Action);
    /* ---------------- 5. Order lines (look up order and product IDs) ---------------- */
    MERGE INTO dbo.SalesOrderLine
     AS t
    USING (SELECT o.SalesOrderId,
                  TRY_CONVERT (INT, l.LineNumber) AS LineNumber,
                  p.ProductId,
                  TRY_CONVERT (INT, l.Quantity) AS Quantity,
                  TRY_CONVERT (DECIMAL (18, 2), l.UnitPrice) AS UnitPrice
           FROM   stg.SalesOrderLine AS l
                  INNER JOIN
                  dbo.SalesOrder AS o
                  ON o.OrderNumber = l.OrderNumber
                  INNER JOIN
                  dbo.Product AS p
                  ON p.ProductCode = l.ProductCode
           WHERE  l.RunId = @RunId
                  AND l.ValidationStatus = 'VALID') AS s ON t.SalesOrderId = s.SalesOrderId
                                                            AND t.LineNumber = s.LineNumber
    WHEN MATCHED AND EXISTS (SELECT s.ProductId,
                                    s.Quantity,
                                    s.UnitPrice
                             EXCEPT
                             SELECT t.ProductId,
                                    t.Quantity,
                                    t.UnitPrice) THEN UPDATE 
    SET ProductId = s.ProductId,
        Quantity  = s.Quantity,
        UnitPrice = s.UnitPrice,
        LastRunId = @RunId
    WHEN NOT MATCHED BY TARGET THEN INSERT (
        SalesOrderId,
        LineNumber,
        ProductId,
        Quantity,
        UnitPrice,
        LastRunId
    ) VALUES (s.SalesOrderId, s.LineNumber, s.ProductId, s.Quantity, s.UnitPrice, @RunId)
    OUTPUT 'dbo.SalesOrderLine', $ACTION INTO #Actions (TableName, Action);
    /* ---------------- 6. Budget ---------------- */
    MERGE INTO dbo.Budget
     AS t
    USING (SELECT TRY_CONVERT (DATE, BudgetMonth, 23) AS BudgetMonth,
                  ProductLine,
                  TRY_CONVERT (DECIMAL (18, 2), BudgetAmount) AS BudgetAmount
           FROM   stg.Budget
           WHERE  RunId = @RunId
                  AND ValidationStatus = 'VALID') AS s ON t.BudgetMonth = s.BudgetMonth
                                                          AND t.ProductLine = s.ProductLine
    WHEN MATCHED AND t.BudgetAmount <> s.BudgetAmount THEN UPDATE 
    SET BudgetAmount = s.BudgetAmount,
        LastRunId    = @RunId
    WHEN NOT MATCHED BY TARGET THEN INSERT (
        BudgetMonth,
        ProductLine,
        BudgetAmount,
        LastRunId
    ) VALUES (s.BudgetMonth, s.ProductLine, s.BudgetAmount, @RunId)
    OUTPUT 'dbo.Budget', $ACTION INTO #Actions (TableName, Action);
    COMMIT TRANSACTION;
    -- Summary: how many rows each table inserted or updated
    SELECT   TableName,
             Action,
             COUNT(*) AS RowsAffected
    FROM     #Actions
    GROUP BY TableName, Action
    ORDER BY TableName, Action;
END