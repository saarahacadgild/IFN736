
USE [Cobbled_NoRLS];
GO

SET NOCOUNT ON;
PRINT 'Verifying ReadAlert Delivery 1 NoRLS table deployment v2.0...';
PRINT 'Current database: ' + DB_NAME();

DECLARE @Expected TABLE (ObjectName SYSNAME NOT NULL);
INSERT INTO @Expected (ObjectName) VALUES
(N'ral.ral_ReaderProfile'),
(N'ral.ral_Authors'),
(N'ral.ral_Books'),
(N'ral.ral_BookAuthors'),
(N'ral.ral_UserBooks'),
(N'ral.ral_BookLookupLog');

SELECT
    ObjectName,
    CASE WHEN OBJECT_ID(ObjectName, N'U') IS NULL THEN 'Missing' ELSE 'Present' END AS ObjectStatus
FROM @Expected
ORDER BY ObjectName;

SELECT 'ral_ReaderProfile' AS TableName, COUNT(1) AS [RecordCount] FROM ral.ral_ReaderProfile
UNION ALL SELECT 'ral_Authors',      COUNT(1) FROM ral.ral_Authors
UNION ALL SELECT 'ral_Books',        COUNT(1) FROM ral.ral_Books
UNION ALL SELECT 'ral_BookAuthors',  COUNT(1) FROM ral.ral_BookAuthors
UNION ALL SELECT 'ral_UserBooks',    COUNT(1) FROM ral.ral_UserBooks
UNION ALL SELECT 'ral_BookLookupLog',COUNT(1) FROM ral.ral_BookLookupLog;

SELECT TOP (20)
    ub.TenantID,
    ub.MemberID,
    b.BookTitle,
    ub.ReadingStatusCode,
    ub.FinishedDate,
    ub.Rating
FROM ral.ral_UserBooks ub
JOIN ral.ral_Books b
    ON b.TenantID = ub.TenantID
   AND b.BookID   = ub.BookID
ORDER BY ub.CreatedUtc DESC;

PRINT 'ReadAlert Delivery 1 NoRLS verification v2.0 complete.';
GO

