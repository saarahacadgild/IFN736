/* Cobble ReadAlert Delivery 1 Base NoRLS Table Deployment v2.0
   Revised scope: reader registration/profile, authors, books, book authors, user books read, ISBN/title search log.
   Change the USE line for the target database before running.
   Intended targets:
     Cobbled_NoRLS = NoRLS test
     Cobbled_RLS   = RLS test base tables before RLS overlay
     Cobbled       = live ApplicationPlane database
*/
USE [Cobbled_NoRLS];
GO

SET NOCOUNT ON;
PRINT 'Starting ReadAlert Delivery 1 Base NoRLS table deployment v2.0...';
PRINT 'Current database: ' + DB_NAME();

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'ral')
BEGIN
    EXEC(N'CREATE SCHEMA ral AUTHORIZATION dbo;');
END;
GO

IF OBJECT_ID(N'ral.ral_ReaderProfile', N'U') IS NULL
BEGIN
    CREATE TABLE ral.ral_ReaderProfile
    (
        TenantID CHAR(32) NOT NULL,
        MemberID CHAR(32) NOT NULL,
        ReaderDisplayName NVARCHAR(200) NULL,
        PreferredGenres NVARCHAR(1000) NULL,
        PreferredAuthors NVARCHAR(1000) NULL,
        AlertOptIn BIT NOT NULL CONSTRAINT DF_ral_ReaderProfile_AlertOptIn DEFAULT (0),
        BooksellerMembershipOptIn BIT NOT NULL CONSTRAINT DF_ral_ReaderProfile_BooksellerMembershipOptIn DEFAULT (0),
        ReaderStatusCode VARCHAR(30) NOT NULL CONSTRAINT DF_ral_ReaderProfile_ReaderStatusCode DEFAULT ('ACTIVE'),
        CreatedUtc DATETIME2(7) NOT NULL CONSTRAINT DF_ral_ReaderProfile_CreatedUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedUtc DATETIME2(7) NULL,
        CONSTRAINT PK_ral_ReaderProfile PRIMARY KEY CLUSTERED (TenantID, MemberID),
        CONSTRAINT CK_ral_ReaderProfile_Status CHECK (ReaderStatusCode IN ('ACTIVE','INACTIVE','PENDING','SUSPENDED'))
    );
END;
GO

IF OBJECT_ID(N'ral.ral_Authors', N'U') IS NULL
BEGIN
    CREATE TABLE ral.ral_Authors
    (
        TenantID CHAR(32) NOT NULL,
        AuthorID CHAR(32) NOT NULL,
        AuthorName NVARCHAR(200) NOT NULL,
        AuthorSortName NVARCHAR(200) NULL,
        Biography NVARCHAR(MAX) NULL,
        Country NVARCHAR(100) NULL,
        WebsiteUrl NVARCHAR(500) NULL,
        IsVerified BIT NOT NULL CONSTRAINT DF_ral_Authors_IsVerified DEFAULT (0),
        AuthorComments NVARCHAR(1000) NULL,
        CreatedByMemberID CHAR(32) NULL,
        CreatedUtc DATETIME2(7) NOT NULL CONSTRAINT DF_ral_Authors_CreatedUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedByMemberID CHAR(32) NULL,
        UpdatedUtc DATETIME2(7) NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_ral_Authors_IsActive DEFAULT (1),
        CONSTRAINT PK_ral_Authors PRIMARY KEY CLUSTERED (TenantID, AuthorID)
    );
END;
GO

IF OBJECT_ID(N'ral.ral_Books', N'U') IS NULL
BEGIN
    CREATE TABLE ral.ral_Books
    (
        TenantID CHAR(32) NOT NULL,
        BookID CHAR(32) NOT NULL,
        ISBN10 NVARCHAR(20) NULL,
        ISBN13 NVARCHAR(20) NULL,
        BookTitle NVARCHAR(300) NOT NULL,
        Subtitle NVARCHAR(300) NULL,
        Publisher NVARCHAR(200) NULL,
        PublishedDate DATE NULL,
        Edition NVARCHAR(100) NULL,
        LanguageCode VARCHAR(10) NULL,
        CoverImageUrl NVARCHAR(1000) NULL,
        Description NVARCHAR(MAX) NULL,
        CreatedByMemberID CHAR(32) NULL,
        CreatedUtc DATETIME2(7) NOT NULL CONSTRAINT DF_ral_Books_CreatedUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedByMemberID CHAR(32) NULL,
        UpdatedUtc DATETIME2(7) NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_ral_Books_IsActive DEFAULT (1),
        CONSTRAINT PK_ral_Books PRIMARY KEY CLUSTERED (TenantID, BookID)
    );
END;
GO

IF OBJECT_ID(N'ral.ral_BookAuthors', N'U') IS NULL
BEGIN
    CREATE TABLE ral.ral_BookAuthors
    (
        TenantID CHAR(32) NOT NULL,
        BookAuthorID CHAR(32) NOT NULL,
        BookID CHAR(32) NOT NULL,
        AuthorID CHAR(32) NOT NULL,
        AuthorOrder INT NOT NULL CONSTRAINT DF_ral_BookAuthors_AuthorOrder DEFAULT (1),
        ContributionCode VARCHAR(30) NOT NULL CONSTRAINT DF_ral_BookAuthors_ContributionCode DEFAULT ('AUTHOR'),
        CreatedUtc DATETIME2(7) NOT NULL CONSTRAINT DF_ral_BookAuthors_CreatedUtc DEFAULT (SYSUTCDATETIME()),
        IsActive BIT NOT NULL CONSTRAINT DF_ral_BookAuthors_IsActive DEFAULT (1),
        CONSTRAINT PK_ral_BookAuthors PRIMARY KEY CLUSTERED (TenantID, BookAuthorID),
        CONSTRAINT UQ_ral_BookAuthors_Book_Author UNIQUE (TenantID, BookID, AuthorID),
        CONSTRAINT CK_ral_BookAuthors_Contribution CHECK (ContributionCode IN ('AUTHOR','COAUTHOR','EDITOR','ILLUSTRATOR','TRANSLATOR','CONTRIBUTOR')),
        CONSTRAINT FK_ral_BookAuthors_Books FOREIGN KEY (TenantID, BookID) REFERENCES ral.ral_Books (TenantID, BookID),
        CONSTRAINT FK_ral_BookAuthors_Authors FOREIGN KEY (TenantID, AuthorID) REFERENCES ral.ral_Authors (TenantID, AuthorID)
    );
END;
GO

IF OBJECT_ID(N'ral.ral_UserBooks', N'U') IS NULL
BEGIN
    CREATE TABLE ral.ral_UserBooks
    (
        TenantID CHAR(32) NOT NULL,
        UserBookID CHAR(32) NOT NULL,
        MemberID CHAR(32) NOT NULL,
        BookID CHAR(32) NOT NULL,
        ReadingStatusCode VARCHAR(30) NOT NULL CONSTRAINT DF_ral_UserBooks_ReadingStatusCode DEFAULT ('READ'),
        StartedDate DATE NULL,
        FinishedDate DATE NULL,
        Rating TINYINT NULL,
        ReviewText NVARCHAR(MAX) NULL,
        PrivateNote NVARCHAR(MAX) NULL,
        SourceCode VARCHAR(30) NOT NULL CONSTRAINT DF_ral_UserBooks_SourceCode DEFAULT ('MANUAL'),
        CreatedUtc DATETIME2(7) NOT NULL CONSTRAINT DF_ral_UserBooks_CreatedUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedUtc DATETIME2(7) NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_ral_UserBooks_IsActive DEFAULT (1),
        CONSTRAINT PK_ral_UserBooks PRIMARY KEY CLUSTERED (TenantID, UserBookID),
        CONSTRAINT UQ_ral_UserBooks_Member_Book UNIQUE (TenantID, MemberID, BookID),
        CONSTRAINT CK_ral_UserBooks_Status CHECK (ReadingStatusCode IN ('WANT_TO_READ','READING','READ','ABANDONED','REJECTED')),
        CONSTRAINT CK_ral_UserBooks_Rating CHECK (Rating IS NULL OR Rating BETWEEN 0 AND 5),
        CONSTRAINT CK_ral_UserBooks_Source CHECK (SourceCode IN ('SCAN_ISBN','MANUAL','TITLE_SEARCH','AUTHOR_SEARCH','IMPORT','SYSTEM')),
        CONSTRAINT FK_ral_UserBooks_Books FOREIGN KEY (TenantID, BookID) REFERENCES ral.ral_Books (TenantID, BookID)
    );
END;
GO

IF OBJECT_ID(N'ral.ral_BookLookupLog', N'U') IS NULL
BEGIN
    CREATE TABLE ral.ral_BookLookupLog
    (
        TenantID CHAR(32) NOT NULL,
        BookLookupLogID CHAR(32) NOT NULL,
        MemberID CHAR(32) NULL,
        LookupTypeCode VARCHAR(30) NOT NULL,
        SearchText NVARCHAR(500) NULL,
        ISBN10 NVARCHAR(20) NULL,
        ISBN13 NVARCHAR(20) NULL,
        MatchedBookID CHAR(32) NULL,
        ResultStatusCode VARCHAR(30) NOT NULL,
        ExternalSourceCode VARCHAR(50) NULL,
        ErrorMessage NVARCHAR(1000) NULL,
        CreatedUtc DATETIME2(7) NOT NULL CONSTRAINT DF_ral_BookLookupLog_CreatedUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_ral_BookLookupLog PRIMARY KEY CLUSTERED (TenantID, BookLookupLogID),
        CONSTRAINT CK_ral_BookLookupLog_LookupType CHECK (LookupTypeCode IN ('ISBN_SCAN','ISBN_SEARCH','TITLE_SEARCH','AUTHOR_SEARCH','MANUAL_ENTRY')),
        CONSTRAINT CK_ral_BookLookupLog_ResultStatus CHECK (ResultStatusCode IN ('MATCHED','NOT_MATCHED','MULTIPLE_MATCHES','ERROR','MANUAL_CREATED')),
        CONSTRAINT FK_ral_BookLookupLog_MatchedBook FOREIGN KEY (TenantID, MatchedBookID) REFERENCES ral.ral_Books (TenantID, BookID)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_ral_Authors_Search' AND object_id=OBJECT_ID(N'ral.ral_Authors'))
    CREATE INDEX IX_ral_Authors_Search ON ral.ral_Authors (TenantID, IsActive, AuthorSortName, AuthorName) WHERE IsActive = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_ral_Books_ISBN13' AND object_id=OBJECT_ID(N'ral.ral_Books'))
    CREATE INDEX IX_ral_Books_ISBN13 ON ral.ral_Books (TenantID, ISBN13) WHERE ISBN13 IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_ral_Books_ISBN10' AND object_id=OBJECT_ID(N'ral.ral_Books'))
    CREATE INDEX IX_ral_Books_ISBN10 ON ral.ral_Books (TenantID, ISBN10) WHERE ISBN10 IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_ral_Books_Title' AND object_id=OBJECT_ID(N'ral.ral_Books'))
    CREATE INDEX IX_ral_Books_Title ON ral.ral_Books (TenantID, IsActive, BookTitle) WHERE IsActive = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_ral_UserBooks_Member_Status' AND object_id=OBJECT_ID(N'ral.ral_UserBooks'))
    CREATE INDEX IX_ral_UserBooks_Member_Status ON ral.ral_UserBooks (TenantID, MemberID, ReadingStatusCode, FinishedDate DESC) WHERE IsActive = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_ral_BookLookupLog_Member_Date' AND object_id=OBJECT_ID(N'ral.ral_BookLookupLog'))
    CREATE INDEX IX_ral_BookLookupLog_Member_Date ON ral.ral_BookLookupLog (TenantID, MemberID, CreatedUtc DESC);
GO

PRINT 'ReadAlert Delivery 1 Base NoRLS table deployment v2.0 complete.';
GO

