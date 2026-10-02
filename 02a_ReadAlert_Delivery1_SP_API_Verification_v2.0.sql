/* Cobble ReadAlert Delivery 1 Stored Procedure/API Verification v2.0
   Change USE line for target database before running.
*/
USE [Cobbled_NoRLS];
GO
SET NOCOUNT ON;
PRINT 'Verifying ReadAlert Delivery 1 stored procedure/API deployment v2.0...';
PRINT 'Current database: ' + DB_NAME();

DECLARE @Required TABLE (ObjectName SYSNAME NOT NULL, ObjectType CHAR(2) NOT NULL);
INSERT INTO @Required (ObjectName, ObjectType) VALUES
(N'ral.ral_ReaderProfile_CRUD_JSON',  N'P'),
(N'ral.ral_Authors_CRUD_JSON',        N'P'),
(N'ral.ral_Books_CRUD_JSON',          N'P'),
(N'ral.ral_BookAuthors_CRUD_JSON',    N'P'),
(N'ral.ral_UserBooks_CRUD_JSON',      N'P'),
(N'ral.ral_BookLookupLog_CRUD_JSON',  N'P'),
(N'ral.ral_SearchBooks_JSON',         N'P'),
(N'ral.ral_ScanBook_JSON',            N'P'),
(N'ral.ral_AddBookRead_JSON',         N'P'),
(N'ral.ral_UpdateBookRead_JSON',      N'P');

SELECT
    r.ObjectName,
    CASE WHEN OBJECT_ID(r.ObjectName, r.ObjectType) IS NULL THEN 'Missing' ELSE 'Present' END AS ObjectStatus,
    OBJECT_ID(r.ObjectName, r.ObjectType) AS ObjectID
FROM @Required r
ORDER BY r.ObjectName;

IF EXISTS (SELECT 1 FROM @Required WHERE OBJECT_ID(ObjectName, ObjectType) IS NULL)
BEGIN
    THROW 57200, 'ReadAlert Delivery 1 SP/API verification failed. Required procedure is missing.', 1;
END;

DECLARE @TenantID CHAR(32) = N'F115B0A094467E7FCBA8DB16DF52242E';
DECLARE @MemberID CHAR(32) = N'00000000000000000000000000000001';
DECLARE @Result   NVARCHAR(MAX);
DECLARE @Payload  NVARCHAR(MAX);

EXEC sys.sp_set_session_context @key=N'TenantID', @value=@TenantID;
EXEC sys.sp_set_session_context @key=N'MemberID', @value=@MemberID;

-- Reader profile SELECT
SET @Payload = N'{"TenantID":"F115B0A094467E7FCBA8DB16DF52242E","MemberID":"00000000000000000000000000000001"}';
EXEC ral.ral_ReaderProfile_CRUD_JSON @Action=N'SELECT', @Payload=@Payload, @Result=@Result OUTPUT;
SELECT 'ReaderProfile_SELECT' AS TestName, CASE WHEN ISJSON(@Result)=1 AND CHARINDEX('Avery Reader',@Result)>0 THEN 'PASS' ELSE 'CHECK' END AS TestStatus, @Result AS ResultJson;

-- Author SELECT and comment field check
SET @Payload = N'{"TenantID":"F115B0A094467E7FCBA8DB16DF52242E","AuthorID":"10000000000000000000000000000001"}';
EXEC ral.ral_Authors_CRUD_JSON @Action=N'SELECT', @Payload=@Payload, @Result=@Result OUTPUT;
SELECT 'Authors_SELECT' AS TestName, CASE WHEN ISJSON(@Result)=1 AND CHARINDEX('AuthorComments',@Result)>0 THEN 'PASS' ELSE 'CHECK' END AS TestStatus, @Result AS ResultJson;

-- Book title search
SET @Payload = N'{"TenantID":"F115B0A094467E7FCBA8DB16DF52242E","MemberID":"00000000000000000000000000000001","SearchType":"TITLE_SEARCH","SearchText":"Martian","Limit":10,"ExternalSourceCode":"LOCAL"}';
EXEC ral.ral_SearchBooks_JSON @Payload=@Payload, @Result=@Result OUTPUT;
SELECT 'SearchBooks_TITLE' AS TestName, CASE WHEN ISJSON(@Result)=1 AND CHARINDEX('The Martian',@Result)>0 THEN 'PASS' ELSE 'CHECK' END AS TestStatus, @Result AS ResultJson;

-- ISBN scan
SET @Payload = N'{"TenantID":"F115B0A094467E7FCBA8DB16DF52242E","MemberID":"00000000000000000000000000000001","ISBN13":"9780553418026","ExternalSourceCode":"LOCAL"}';
EXEC ral.ral_ScanBook_JSON @Payload=@Payload, @Result=@Result OUTPUT;
SELECT 'ScanBook_ISBN13' AS TestName, CASE WHEN ISJSON(@Result)=1 AND CHARINDEX('The Martian',@Result)>0 THEN 'PASS' ELSE 'CHECK' END AS TestStatus, @Result AS ResultJson;

-- Add/upsert a book-read row
SET @Payload = N'{"TenantID":"F115B0A094467E7FCBA8DB16DF52242E","MemberID":"00000000000000000000000000000001","BookID":"20000000000000000000000000000002","ReadingStatusCode":"READ","StartedDate":"2025-04-01","FinishedDate":"2025-04-12","Rating":5,"ReviewText":"Verification test add/update through API stored procedure.","PrivateNote":"Verification note.","SourceCode":"SCAN_ISBN"}';
EXEC ral.ral_AddBookRead_JSON @Payload=@Payload, @Result=@Result OUTPUT;
SELECT 'AddBookRead_UPSERT' AS TestName, CASE WHEN ISJSON(@Result)=1 AND CHARINDEX('Verification test',@Result)>0 THEN 'PASS' ELSE 'CHECK' END AS TestStatus, @Result AS ResultJson;

-- Direct UserBooks SELECT
SET @Payload = N'{"TenantID":"F115B0A094467E7FCBA8DB16DF52242E","MemberID":"00000000000000000000000000000001"}';
EXEC ral.ral_UserBooks_CRUD_JSON @Action=N'SELECT', @Payload=@Payload, @Result=@Result OUTPUT;
SELECT 'UserBooks_SELECT' AS TestName, CASE WHEN ISJSON(@Result)=1 AND CHARINDEX('Murder on the Orient Express',@Result)>0 THEN 'PASS' ELSE 'CHECK' END AS TestStatus, @Result AS ResultJson;

-- Count lookup logs
SELECT 'LookupLog_Count' AS TestName, COUNT(*) AS [RecordCount]
FROM ral.ral_BookLookupLog
WHERE TenantID = @TenantID AND MemberID = @MemberID;

EXEC sys.sp_set_session_context @key=N'TenantID', @value=NULL;
EXEC sys.sp_set_session_context @key=N'MemberID', @value=NULL;

PRINT 'ReadAlert Delivery 1 stored procedure/API verification v2.0 complete.';
GO

