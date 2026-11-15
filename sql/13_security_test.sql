/* Act as the dashboard user and see what it can and can't do */
EXECUTE AS USER = 'dashboard_user';

SELECT USER_NAME() AS acting_as;

-- Allowed: a reporting view. Emails come back MASKED.
SELECT TOP 3 CustomerCode,
             CustomerName,
             Email
FROM   rpt.CustomerDirectory;

-- Not allowed: reading a raw table
BEGIN TRY
    SELECT TOP 1 *
    FROM   dbo.SalesOrder;
END TRY
BEGIN CATCH
    SELECT 'Read dbo.SalesOrder' AS attempted,
           ERROR_MESSAGE() AS result;
END CATCH

-- Not allowed: changing data
BEGIN TRY
    UPDATE dbo.Product
    SET    UnitPrice = 0;
END TRY
BEGIN CATCH
    SELECT 'Change product prices' AS attempted,
           ERROR_MESSAGE() AS result;
END CATCH

REVERT; -- back to the admin

-- As the admin, the real emails are visible
SELECT TOP 3 CustomerCode,
             CustomerName,
             Email
FROM   rpt.CustomerDirectory;