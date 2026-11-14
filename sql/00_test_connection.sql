-- First test: confirm we're connected to the right database on Azure
SELECT DB_NAME() AS database_name,
       @@VERSION AS sql_version,
       SYSDATETIME() AS server_time;