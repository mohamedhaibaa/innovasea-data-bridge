/* =====================================================================
   Innovasea Data Bridge: schema
   Creates every table the pipeline uses. Safe to re-run: it drops
   and rebuilds everything (development only, never on real data).
   ===================================================================== */
-- ---------------------------------------------------------------------
-- 1. Schemas: one per stage of the data's journey
-- ---------------------------------------------------------------------
IF SCHEMA_ID('stg') IS NULL
    EXECUTE ('CREATE SCHEMA stg'); -- raw, unchecked

IF SCHEMA_ID('etl') IS NULL
    EXECUTE ('CREATE SCHEMA etl'); -- run log, quarantine

IF SCHEMA_ID('rpt') IS NULL
    EXECUTE ('CREATE SCHEMA rpt'); -- reporting views (Step 8)


GO
-- ---------------------------------------------------------------------
-- 2. Drop old tables (children before parents, because of foreign keys)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.SalesOrderLine;

DROP TABLE IF EXISTS dbo.SalesOrder;

DROP TABLE IF EXISTS dbo.Product;

DROP TABLE IF EXISTS dbo.Customer;

DROP TABLE IF EXISTS dbo.CrmDeal;

DROP TABLE IF EXISTS dbo.Budget;

DROP TABLE IF EXISTS etl.Quarantine;

DROP TABLE IF EXISTS etl.RunLog;

DROP TABLE IF EXISTS stg.Customer;

DROP TABLE IF EXISTS stg.Product;

DROP TABLE IF EXISTS stg.SalesOrder;

DROP TABLE IF EXISTS stg.SalesOrderLine;

DROP TABLE IF EXISTS stg.CrmDeal;

DROP TABLE IF EXISTS stg.Budget;


GO
-- ---------------------------------------------------------------------
-- 3. Control tables (etl)
-- ---------------------------------------------------------------------
-- One row per pipeline run. RunId doubles as the batch number.
CREATE TABLE etl.RunLog (
    RunId        INT            IDENTITY (1, 1) PRIMARY KEY,
    PipelineName NVARCHAR (100) NOT NULL,
    StartedAtUtc DATETIME2 (0)  DEFAULT SYSUTCDATETIME() NOT NULL,
    EndedAtUtc   DATETIME2 (0)  NULL,
    Status       NVARCHAR (20)  DEFAULT 'Running' NOT NULL CONSTRAINT CK_RunLog_Status CHECK (Status IN ('Running', 'Succeeded', 'Failed')),
    RowsLoaded   INT            NULL,
    RowsRejected INT            NULL,
    ErrorMessage NVARCHAR (MAX) NULL
);

-- Every rejected row, with the rule it broke and why. Nothing is dropped silently.
CREATE TABLE etl.Quarantine (
    QuarantineId     INT            IDENTITY (1, 1) PRIMARY KEY,
    RunId            INT            NOT NULL CONSTRAINT FK_Quarantine_RunLog FOREIGN KEY REFERENCES etl.RunLog (RunId),
    SourceTable      NVARCHAR (100) NOT NULL,
    StgRowId         INT            NOT NULL,
    RuleName         NVARCHAR (100) NOT NULL,
    Reason           NVARCHAR (400) NOT NULL,
    RawRecord        NVARCHAR (MAX) NULL, -- the original row as JSON, for review
    QuarantinedAtUtc DATETIME2 (0)  DEFAULT SYSUTCDATETIME() NOT NULL
);


GO
-- ---------------------------------------------------------------------
-- 4. Staging tables (stg): everything is text and nullable on purpose,
--    so a bad row can still land here and be checked, not crash the load.
-- ---------------------------------------------------------------------
CREATE TABLE stg.Customer (
    StgRowId         INT            IDENTITY (1, 1) PRIMARY KEY,
    RunId            INT            NOT NULL,
    LoadedAtUtc      DATETIME2 (0)  DEFAULT SYSUTCDATETIME() NOT NULL,
    ValidationStatus NVARCHAR (10)  NULL, -- NULL = not checked, VALID, REJECTED
    CustomerCode     NVARCHAR (100) NULL,
    CustomerName     NVARCHAR (300) NULL,
    Country          NVARCHAR (100) NULL,
    Region           NVARCHAR (100) NULL,
    Email            NVARCHAR (300) NULL
);

CREATE TABLE stg.Product (
    StgRowId         INT            IDENTITY (1, 1) PRIMARY KEY,
    RunId            INT            NOT NULL,
    LoadedAtUtc      DATETIME2 (0)  DEFAULT SYSUTCDATETIME() NOT NULL,
    ValidationStatus NVARCHAR (10)  NULL,
    ProductCode      NVARCHAR (100) NULL,
    ProductName      NVARCHAR (300) NULL,
    ProductLine      NVARCHAR (100) NULL,
    UnitPrice        NVARCHAR (50)  NULL
);

CREATE TABLE stg.SalesOrder (
    StgRowId         INT            IDENTITY (1, 1) PRIMARY KEY,
    RunId            INT            NOT NULL,
    LoadedAtUtc      DATETIME2 (0)  DEFAULT SYSUTCDATETIME() NOT NULL,
    ValidationStatus NVARCHAR (10)  NULL,
    OrderNumber      NVARCHAR (100) NULL,
    CustomerCode     NVARCHAR (100) NULL,
    OrderDate        NVARCHAR (50)  NULL,
    Status           NVARCHAR (50)  NULL,
    CrmDealId        NVARCHAR (100) NULL
);

CREATE TABLE stg.SalesOrderLine (
    StgRowId         INT            IDENTITY (1, 1) PRIMARY KEY,
    RunId            INT            NOT NULL,
    LoadedAtUtc      DATETIME2 (0)  DEFAULT SYSUTCDATETIME() NOT NULL,
    ValidationStatus NVARCHAR (10)  NULL,
    OrderNumber      NVARCHAR (100) NULL,
    LineNumber       NVARCHAR (50)  NULL,
    ProductCode      NVARCHAR (100) NULL,
    Quantity         NVARCHAR (50)  NULL,
    UnitPrice        NVARCHAR (50)  NULL
);

CREATE TABLE stg.CrmDeal (
    StgRowId         INT            IDENTITY (1, 1) PRIMARY KEY,
    RunId            INT            NOT NULL,
    LoadedAtUtc      DATETIME2 (0)  DEFAULT SYSUTCDATETIME() NOT NULL,
    ValidationStatus NVARCHAR (10)  NULL,
    CrmDealId        NVARCHAR (100) NULL,
    CustomerCode     NVARCHAR (100) NULL,
    DealName         NVARCHAR (300) NULL,
    Amount           NVARCHAR (50)  NULL,
    Stage            NVARCHAR (100) NULL,
    CloseDate        NVARCHAR (50)  NULL
);

CREATE TABLE stg.Budget (
    StgRowId         INT            IDENTITY (1, 1) PRIMARY KEY,
    RunId            INT            NOT NULL,
    LoadedAtUtc      DATETIME2 (0)  DEFAULT SYSUTCDATETIME() NOT NULL,
    ValidationStatus NVARCHAR (10)  NULL,
    BudgetMonth      NVARCHAR (50)  NULL,
    ProductLine      NVARCHAR (100) NULL,
    BudgetAmount     NVARCHAR (50)  NULL
);


GO
-- ---------------------------------------------------------------------
-- 5. Clean tables (dbo): the system of record.
--    Real types, keys and constraints: the database's last line of defence.
-- ---------------------------------------------------------------------
CREATE TABLE dbo.Customer (
    CustomerId   INT            IDENTITY (1, 1) PRIMARY KEY,
    CustomerCode NVARCHAR (20)  NOT NULL CONSTRAINT UQ_Customer_Code UNIQUE,
    CustomerName NVARCHAR (200) NOT NULL,
    Country      NVARCHAR (60)  NULL,
    Region       NVARCHAR (60)  NULL,
    Email        NVARCHAR (200) NULL, -- masked for readers in Step 10
    CreatedAtUtc DATETIME2 (0)  DEFAULT SYSUTCDATETIME() NOT NULL,
    UpdatedAtUtc DATETIME2 (0)  DEFAULT SYSUTCDATETIME() NOT NULL,
    LastRunId    INT            NULL -- which run last touched this row
);

CREATE TABLE dbo.Product (
    ProductId    INT             IDENTITY (1, 1) PRIMARY KEY,
    ProductCode  NVARCHAR (20)   NOT NULL CONSTRAINT UQ_Product_Code UNIQUE,
    ProductName  NVARCHAR (200)  NOT NULL,
    ProductLine  NVARCHAR (60)   NOT NULL,
    UnitPrice    DECIMAL (18, 2) NOT NULL CONSTRAINT CK_Product_Price CHECK (UnitPrice >= 0),
    CreatedAtUtc DATETIME2 (0)   DEFAULT SYSUTCDATETIME() NOT NULL,
    UpdatedAtUtc DATETIME2 (0)   DEFAULT SYSUTCDATETIME() NOT NULL,
    LastRunId    INT             NULL
);

-- Won deals from the CRM. No foreign key to Customer on purpose:
-- a deal for a customer missing from the ERP is exactly what
-- reconciliation needs to find, not something to hide.
CREATE TABLE dbo.CrmDeal (
    CrmDealId    NVARCHAR (30)   PRIMARY KEY,
    CustomerCode NVARCHAR (20)   NOT NULL,
    DealName     NVARCHAR (200)  NOT NULL,
    Amount       DECIMAL (18, 2) NOT NULL CONSTRAINT CK_CrmDeal_Amount CHECK (Amount >= 0),
    Stage        NVARCHAR (30)   NOT NULL,
    CloseDate    DATE            NOT NULL,
    UpdatedAtUtc DATETIME2 (0)   DEFAULT SYSUTCDATETIME() NOT NULL,
    LastRunId    INT             NULL
);

CREATE TABLE dbo.SalesOrder (
    SalesOrderId INT           IDENTITY (1, 1) PRIMARY KEY,
    OrderNumber  NVARCHAR (20) NOT NULL CONSTRAINT UQ_SalesOrder_Number UNIQUE,
    CustomerId   INT           NOT NULL CONSTRAINT FK_SalesOrder_Customer FOREIGN KEY REFERENCES dbo.Customer (CustomerId),
    OrderDate    DATE          NOT NULL,
    Status       NVARCHAR (20) NOT NULL CONSTRAINT CK_SalesOrder_Status CHECK (Status IN ('Open', 'Shipped', 'Invoiced')),
    CrmDealId    NVARCHAR (30) NULL, -- link back to the Salesforce deal
    CreatedAtUtc DATETIME2 (0) DEFAULT SYSUTCDATETIME() NOT NULL,
    UpdatedAtUtc DATETIME2 (0) DEFAULT SYSUTCDATETIME() NOT NULL,
    LastRunId    INT           NULL
);

CREATE TABLE dbo.SalesOrderLine (
    SalesOrderLineId INT             IDENTITY (1, 1) PRIMARY KEY,
    SalesOrderId     INT             NOT NULL CONSTRAINT FK_Line_SalesOrder FOREIGN KEY REFERENCES dbo.SalesOrder (SalesOrderId),
    LineNumber       INT             NOT NULL,
    ProductId        INT             NOT NULL CONSTRAINT FK_Line_Product FOREIGN KEY REFERENCES dbo.Product (ProductId),
    Quantity         INT             NOT NULL CONSTRAINT CK_Line_Quantity CHECK (Quantity > 0),
    UnitPrice        DECIMAL (18, 2) NOT NULL CONSTRAINT CK_Line_Price CHECK (UnitPrice >= 0),
    LineAmount       AS              (Quantity * UnitPrice) PERSISTED, -- calculated, never typed
    LastRunId        INT             NULL,
    CONSTRAINT UQ_Line_Order_LineNumber UNIQUE (SalesOrderId, LineNumber)
);

CREATE TABLE dbo.Budget (
    BudgetId     INT             IDENTITY (1, 1) PRIMARY KEY,
    BudgetMonth  DATE            NOT NULL, -- always the 1st of the month
    ProductLine  NVARCHAR (60)   NOT NULL,
    BudgetAmount DECIMAL (18, 2) NOT NULL CONSTRAINT CK_Budget_Amount CHECK (BudgetAmount >= 0),
    LastRunId    INT             NULL,
    CONSTRAINT UQ_Budget_Month_Line UNIQUE (BudgetMonth, ProductLine)
);


GO
-- ---------------------------------------------------------------------
-- 6. Check: list every table we just created
-- ---------------------------------------------------------------------
SELECT   s.name AS schema_name,
         t.name AS table_name
FROM     sys.tables AS t
         INNER JOIN
         sys.schemas AS s
         ON s.schema_id = t.schema_id
ORDER BY s.name, t.name;