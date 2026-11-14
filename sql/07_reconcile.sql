/* =====================================================================
   Step 7: reconciliation between the CRM (Salesforce) and the ERP (SYSPRO)
   Validation checks each row on its own; reconciliation checks that
   the two systems agree with each other.
   ===================================================================== */
-- Results are kept per run, so there's a history of what was found when
IF OBJECT_ID('etl.ReconciliationResult') IS NULL
    CREATE TABLE etl.ReconciliationResult (
        ReconId      INT             IDENTITY (1, 1) PRIMARY KEY,
        RunId        INT             NOT NULL,
        Issue        NVARCHAR (50)   NOT NULL,
        CrmDealId    NVARCHAR (30)   NULL,
        OrderNumber  NVARCHAR (20)   NULL,
        CustomerCode NVARCHAR (20)   NULL,
        CrmAmount    DECIMAL (18, 2) NULL,
        ErpAmount    DECIMAL (18, 2) NULL,
        Difference   AS              (ISNULL(CrmAmount, 0) - ISNULL(ErpAmount, 0)) PERSISTED,
        Detail       NVARCHAR (400)  NOT NULL,
        CheckedAtUtc DATETIME2 (0)   DEFAULT SYSUTCDATETIME() NOT NULL
    );


GO
CREATE OR ALTER PROCEDURE etl.usp_Reconcile
@RunId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    -- Re-run safety
    DELETE etl.ReconciliationResult
    WHERE  RunId = @RunId;
    -- Each ERP order with its customer and calculated total
    SELECT   o.SalesOrderId,
             o.OrderNumber,
             o.CrmDealId,
             c.CustomerCode,
             ISNULL(SUM(l.LineAmount), 0) AS ErpAmount
    INTO     #OrderTotals
    FROM     dbo.SalesOrder AS o
             INNER JOIN
             dbo.Customer AS c
             ON c.CustomerId = o.CustomerId
             LEFT OUTER JOIN
             dbo.SalesOrderLine AS l
             ON l.SalesOrderId = o.SalesOrderId
    GROUP BY o.SalesOrderId, o.OrderNumber, o.CrmDealId, c.CustomerCode;
    -- 1. Won in the CRM, but no order in the ERP
    INSERT INTO etl.ReconciliationResult (
        RunId,
        Issue,
        CrmDealId,
        CustomerCode,
        CrmAmount,
        ErpAmount,
        Detail
    )
    SELECT @RunId,
           'WonDealMissingOrder',
           d.CrmDealId,
           d.CustomerCode,
           d.Amount,
           NULL,
           CONCAT('Deal ', d.CrmDealId, ' was won in the CRM but has no order in the ERP')
    FROM   dbo.CrmDeal AS d
    WHERE  d.Stage = 'Closed Won'
           AND NOT EXISTS (SELECT 1
                           FROM   #OrderTotals AS o
                           WHERE  o.CrmDealId = d.CrmDealId);
    -- 2. Deal amount does not match the order total
    INSERT INTO etl.ReconciliationResult (
        RunId,
        Issue,
        CrmDealId,
        OrderNumber,
        CustomerCode,
        CrmAmount,
        ErpAmount,
        Detail
    )
    SELECT @RunId,
           'AmountMismatch',
           d.CrmDealId,
           o.OrderNumber,
           d.CustomerCode,
           d.Amount,
           o.ErpAmount,
           CONCAT('CRM deal is ', FORMAT(d.Amount, 'N2'), ' but order ', o.OrderNumber, ' totals ', FORMAT(o.ErpAmount, 'N2'))
    FROM   dbo.CrmDeal AS d
           INNER JOIN
           #OrderTotals AS o
           ON o.CrmDealId = d.CrmDealId
    WHERE  d.Stage = 'Closed Won'
           AND d.Amount <> o.ErpAmount;
    -- 3. Deal and order point to different customers
    INSERT INTO etl.ReconciliationResult (
        RunId,
        Issue,
        CrmDealId,
        OrderNumber,
        CustomerCode,
        CrmAmount,
        ErpAmount,
        Detail
    )
    SELECT @RunId,
           'CustomerMismatch',
           d.CrmDealId,
           o.OrderNumber,
           d.CustomerCode,
           d.Amount,
           o.ErpAmount,
           CONCAT('Deal is for ', d.CustomerCode, ' but order ', o.OrderNumber, ' is for ', o.CustomerCode)
    FROM   dbo.CrmDeal AS d
           INNER JOIN
           #OrderTotals AS o
           ON o.CrmDealId = d.CrmDealId
    WHERE  d.CustomerCode <> o.CustomerCode;
    -- 4. A lost deal should not have an order
    INSERT INTO etl.ReconciliationResult (
        RunId,
        Issue,
        CrmDealId,
        OrderNumber,
        CustomerCode,
        CrmAmount,
        ErpAmount,
        Detail
    )
    SELECT @RunId,
           'LostDealHasOrder',
           d.CrmDealId,
           o.OrderNumber,
           d.CustomerCode,
           NULL,
           o.ErpAmount,
           CONCAT('Deal ', d.CrmDealId, ' is ', d.Stage, ' but has order ', o.OrderNumber)
    FROM   dbo.CrmDeal AS d
           INNER JOIN
           #OrderTotals AS o
           ON o.CrmDealId = d.CrmDealId
    WHERE  d.Stage <> 'Closed Won';
    -- 5. Order points to a deal the CRM does not have
    INSERT INTO etl.ReconciliationResult (
        RunId,
        Issue,
        OrderNumber,
        CustomerCode,
        CrmAmount,
        ErpAmount,
        Detail
    )
    SELECT @RunId,
           'OrderDealNotFound',
           o.OrderNumber,
           o.CustomerCode,
           NULL,
           o.ErpAmount,
           CONCAT('Order ', o.OrderNumber, ' refers to deal ', o.CrmDealId, ' which is not in the CRM')
    FROM   #OrderTotals AS o
    WHERE  o.CrmDealId IS NOT NULL
           AND NOT EXISTS (SELECT 1
                           FROM   dbo.CrmDeal AS d
                           WHERE  d.CrmDealId = o.CrmDealId);
    COMMIT TRANSACTION;
    -- Result 1: the headline numbers
    SELECT (SELECT ISNULL(SUM(Amount), 0)
            FROM   dbo.CrmDeal
            WHERE  Stage = 'Closed Won') AS CrmWonTotal,
           (SELECT ISNULL(SUM(ErpAmount), 0)
            FROM   #OrderTotals
            WHERE  CrmDealId IS NOT NULL) AS ErpOrderTotal;
    -- Result 2: every issue, biggest difference first
    SELECT   Issue,
             CrmDealId,
             OrderNumber,
             CustomerCode,
             CrmAmount,
             ErpAmount,
             Difference,
             Detail
    FROM     etl.ReconciliationResult
    WHERE    RunId = @RunId
    ORDER BY ABS(Difference) DESC;
END