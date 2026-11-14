/* =====================================================================
   Step 8d: indexes for the reporting workload
   SQL Server does NOT index foreign keys or date columns automatically.
   Safe to re-run: drops each index first, then creates it.
   ===================================================================== */
-- Find orders by date quickly; INCLUDE the columns reports read,
-- so SQL Server never has to go back to the main table
DROP INDEX IF EXISTS IX_SalesOrder_OrderDate
    ON dbo.SalesOrder;

CREATE INDEX IX_SalesOrder_OrderDate
    ON dbo.SalesOrder(OrderDate)
    INCLUDE(OrderNumber, CustomerId, Status, CrmDealId);

-- Find an order's lines quickly, with the amounts already in the index
DROP INDEX IF EXISTS IX_SalesOrderLine_SalesOrderId
    ON dbo.SalesOrderLine;

CREATE INDEX IX_SalesOrderLine_SalesOrderId
    ON dbo.SalesOrderLine(SalesOrderId)
    INCLUDE(ProductId, Quantity, LineAmount);

-- Check: both indexes exist
SELECT t.name AS table_name,
       i.name AS index_name,
       i.type_desc
FROM   sys.indexes AS i
       INNER JOIN
       sys.tables AS t
       ON t.object_id = i.object_id
WHERE  i.name IN ('IX_SalesOrder_OrderDate', 'IX_SalesOrderLine_SalesOrderId');