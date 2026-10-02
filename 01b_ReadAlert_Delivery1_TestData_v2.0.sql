/* Cobble ReadAlert Delivery 1 Test Data v2.0
   Safe to run in NoRLS or RLS if the target database line is correct.
   For RLS, this script sets TenantID and MemberID in SESSION_CONTEXT before inserting protected rows.
*/
USE [Cobbled_NoRLS];
GO

SET NOCOUNT ON;
PRINT 'Seeding ReadAlert Delivery 1 sample data v2.0 if not already present...';
PRINT 'Current database: ' + DB_NAME();

IF OBJECT_ID(N'ral.ral_Authors', N'U') IS NULL OR OBJECT_ID(N'ral.ral_Books', N'U') IS NULL OR OBJECT_ID(N'ral.ral_UserBooks', N'U') IS NULL
BEGIN
    THROW 52100, 'ReadAlert Delivery 1 test data failed. Base tables are missing in the current database.', 1;
END;

DECLARE @Tenant1 CHAR(32) = N'F115B0A094467E7FCBA8DB16DF52242E';
DECLARE @Tenant2 CHAR(32) = N'C220B0A094467E7FCBA8DB16DF52242E';
DECLARE @Member1 CHAR(32) = N'00000000000000000000000000000001';
DECLARE @Member2 CHAR(32) = N'00000000000000000000000000000002';
DECLARE @Member3 CHAR(32) = N'00000000000000000000000000000003';

EXEC sys.sp_set_session_context @key=N'TenantID', @value=@Tenant1;
EXEC sys.sp_set_session_context @key=N'MemberID', @value=@Member1;

IF NOT EXISTS (SELECT 1 FROM ral.ral_ReaderProfile WHERE TenantID=@Tenant1 AND MemberID=@Member1)
INSERT INTO ral.ral_ReaderProfile (TenantID, MemberID, ReaderDisplayName, PreferredGenres, PreferredAuthors, AlertOptIn, BooksellerMembershipOptIn)
VALUES (@Tenant1, @Member1, N'Avery Reader', N'Mystery; Science Fiction; Business', N'Agatha Christie; Andy Weir', 1, 1);

IF NOT EXISTS (SELECT 1 FROM ral.ral_ReaderProfile WHERE TenantID=@Tenant1 AND MemberID=@Member2)
INSERT INTO ral.ral_ReaderProfile (TenantID, MemberID, ReaderDisplayName, PreferredGenres, PreferredAuthors, AlertOptIn, BooksellerMembershipOptIn)
VALUES (@Tenant1, @Member2, N'Blair Reader', N'History; Cybersecurity; Fiction', N'Kim Stanley Robinson', 1, 0);

IF NOT EXISTS (SELECT 1 FROM ral.ral_Authors WHERE TenantID=@Tenant1 AND AuthorID=N'10000000000000000000000000000001')
INSERT INTO ral.ral_Authors (TenantID, AuthorID, AuthorName, AuthorSortName, Biography, Country, WebsiteUrl, IsVerified, AuthorComments, CreatedByMemberID)
VALUES (@Tenant1, N'10000000000000000000000000000001', N'Agatha Christie', N'Christie, Agatha', N'Author record used for ReadAlert sample data.', N'United Kingdom', N'https://www.agathachristie.com', 1, N'Sample author. Comments field confirms Delivery 1 design update.', @Member1);

IF NOT EXISTS (SELECT 1 FROM ral.ral_Authors WHERE TenantID=@Tenant1 AND AuthorID=N'10000000000000000000000000000002')
INSERT INTO ral.ral_Authors (TenantID, AuthorID, AuthorName, AuthorSortName, Biography, Country, WebsiteUrl, IsVerified, AuthorComments, CreatedByMemberID)
VALUES (@Tenant1, N'10000000000000000000000000000002', N'Andy Weir', N'Weir, Andy', N'Author record used for ReadAlert sample data.', N'United States', N'https://andyweirauthor.com', 1, N'Sample author for ISBN/title search scenarios.', @Member1);

IF NOT EXISTS (SELECT 1 FROM ral.ral_Books WHERE TenantID=@Tenant1 AND BookID=N'20000000000000000000000000000001')
INSERT INTO ral.ral_Books (TenantID, BookID, ISBN10, ISBN13, BookTitle, Subtitle, Publisher, PublishedDate, Edition, LanguageCode, CoverImageUrl, Description, CreatedByMemberID)
VALUES (@Tenant1, N'20000000000000000000000000000001', N'0007119313', N'9780007119318', N'Murder on the Orient Express', NULL, N'HarperCollins', '1934-01-01', N'Sample edition', 'en', NULL, N'Sample book record for ReadAlert Delivery 1.', @Member1);

IF NOT EXISTS (SELECT 1 FROM ral.ral_Books WHERE TenantID=@Tenant1 AND BookID=N'20000000000000000000000000000002')
INSERT INTO ral.ral_Books (TenantID, BookID, ISBN10, ISBN13, BookTitle, Subtitle, Publisher, PublishedDate, Edition, LanguageCode, CoverImageUrl, Description, CreatedByMemberID)
VALUES (@Tenant1, N'20000000000000000000000000000002', N'0553418025', N'9780553418026', N'The Martian', NULL, N'Crown', '2014-02-11', N'Sample edition', 'en', NULL, N'Sample book record for ReadAlert Delivery 1.', @Member1);

IF NOT EXISTS (SELECT 1 FROM ral.ral_BookAuthors WHERE TenantID=@Tenant1 AND BookAuthorID=N'30000000000000000000000000000001')
INSERT INTO ral.ral_BookAuthors (TenantID, BookAuthorID, BookID, AuthorID, AuthorOrder, ContributionCode)
VALUES (@Tenant1, N'30000000000000000000000000000001', N'20000000000000000000000000000001', N'10000000000000000000000000000001', 1, 'AUTHOR');

IF NOT EXISTS (SELECT 1 FROM ral.ral_BookAuthors WHERE TenantID=@Tenant1 AND BookAuthorID=N'30000000000000000000000000000002')
INSERT INTO ral.ral_BookAuthors (TenantID, BookAuthorID, BookID, AuthorID, AuthorOrder, ContributionCode)
VALUES (@Tenant1, N'30000000000000000000000000000002', N'20000000000000000000000000000002', N'10000000000000000000000000000002', 1, 'AUTHOR');

IF NOT EXISTS (SELECT 1 FROM ral.ral_UserBooks WHERE TenantID=@Tenant1 AND UserBookID=N'40000000000000000000000000000001')
INSERT INTO ral.ral_UserBooks (TenantID, UserBookID, MemberID, BookID, ReadingStatusCode, StartedDate, FinishedDate, Rating, ReviewText, PrivateNote, SourceCode)
VALUES (@Tenant1, N'40000000000000000000000000000001', @Member1, N'20000000000000000000000000000001', 'READ', '2025-02-01', '2025-02-12', 5, N'Classic locked-room/travel mystery sample review.', N'Private sample note.', 'TITLE_SEARCH');

IF NOT EXISTS (SELECT 1 FROM ral.ral_UserBooks WHERE TenantID=@Tenant1 AND UserBookID=N'40000000000000000000000000000002')
INSERT INTO ral.ral_UserBooks (TenantID, UserBookID, MemberID, BookID, ReadingStatusCode, StartedDate, FinishedDate, Rating, ReviewText, PrivateNote, SourceCode)
VALUES (@Tenant1, N'40000000000000000000000000000002', @Member2, N'20000000000000000000000000000002', 'READING', '2025-03-03', NULL, NULL, NULL, N'Sample currently reading note.', 'SCAN_ISBN');

IF NOT EXISTS (SELECT 1 FROM ral.ral_BookLookupLog WHERE TenantID=@Tenant1 AND BookLookupLogID=N'50000000000000000000000000000001')
INSERT INTO ral.ral_BookLookupLog (TenantID, BookLookupLogID, MemberID, LookupTypeCode, SearchText, ISBN10, ISBN13, MatchedBookID, ResultStatusCode, ExternalSourceCode)
VALUES (@Tenant1, N'50000000000000000000000000000001', @Member1, 'TITLE_SEARCH', N'Murder on the Orient Express', NULL, NULL, N'20000000000000000000000000000001', 'MATCHED', 'LOCAL');

IF NOT EXISTS (SELECT 1 FROM ral.ral_BookLookupLog WHERE TenantID=@Tenant1 AND BookLookupLogID=N'50000000000000000000000000000002')
INSERT INTO ral.ral_BookLookupLog (TenantID, BookLookupLogID, MemberID, LookupTypeCode, SearchText, ISBN10, ISBN13, MatchedBookID, ResultStatusCode, ExternalSourceCode)
VALUES (@Tenant1, N'50000000000000000000000000000002', @Member2, 'ISBN_SCAN', N'9780553418026', NULL, N'9780553418026', N'20000000000000000000000000000002', 'MATCHED', 'LOCAL');

EXEC sys.sp_set_session_context @key=N'TenantID', @value=@Tenant2;
EXEC sys.sp_set_session_context @key=N'MemberID', @value=@Member3;

IF NOT EXISTS (SELECT 1 FROM ral.ral_ReaderProfile WHERE TenantID=@Tenant2 AND MemberID=@Member3)
INSERT INTO ral.ral_ReaderProfile (TenantID, MemberID, ReaderDisplayName, PreferredGenres, PreferredAuthors, AlertOptIn, BooksellerMembershipOptIn)
VALUES (@Tenant2, @Member3, N'Casey Reader', N'Fiction; Biography', N'Local authors', 0, 0);

IF NOT EXISTS (SELECT 1 FROM ral.ral_Authors WHERE TenantID=@Tenant2 AND AuthorID=N'10000000000000000000000000000003')
INSERT INTO ral.ral_Authors (TenantID, AuthorID, AuthorName, AuthorSortName, Biography, Country, IsVerified, AuthorComments, CreatedByMemberID)
VALUES (@Tenant2, N'10000000000000000000000000000003', N'Sample Tenant Two Author', N'Author, Sample Tenant Two', N'Tenant two sample author.', N'Australia', 0, N'Separate tenant sample to validate RLS isolation.', @Member3);

IF NOT EXISTS (SELECT 1 FROM ral.ral_Books WHERE TenantID=@Tenant2 AND BookID=N'20000000000000000000000000000003')
INSERT INTO ral.ral_Books (TenantID, BookID, ISBN13, BookTitle, Publisher, PublishedDate, LanguageCode, Description, CreatedByMemberID)
VALUES (@Tenant2, N'20000000000000000000000000000003', N'9780000000003', N'Tenant Two Sample Book', N'Sample Press', '2025-01-01', 'en', N'Separate tenant sample book.', @Member3);

IF NOT EXISTS (SELECT 1 FROM ral.ral_BookAuthors WHERE TenantID=@Tenant2 AND BookAuthorID=N'30000000000000000000000000000003')
INSERT INTO ral.ral_BookAuthors (TenantID, BookAuthorID, BookID, AuthorID, AuthorOrder, ContributionCode)
VALUES (@Tenant2, N'30000000000000000000000000000003', N'20000000000000000000000000000003', N'10000000000000000000000000000003', 1, 'AUTHOR');

IF NOT EXISTS (SELECT 1 FROM ral.ral_UserBooks WHERE TenantID=@Tenant2 AND UserBookID=N'40000000000000000000000000000003')
INSERT INTO ral.ral_UserBooks (TenantID, UserBookID, MemberID, BookID, ReadingStatusCode, StartedDate, FinishedDate, Rating, ReviewText, PrivateNote, SourceCode)
VALUES (@Tenant2, N'40000000000000000000000000000003', @Member3, N'20000000000000000000000000000003', 'WANT_TO_READ', NULL, NULL, NULL, NULL, N'Tenant two isolation sample.', 'MANUAL');

EXEC sys.sp_set_session_context @key=N'TenantID', @value=NULL;
EXEC sys.sp_set_session_context @key=N'MemberID', @value=NULL;

PRINT 'ReadAlert Delivery 1 sample data v2.0 seeded successfully.';
GO

