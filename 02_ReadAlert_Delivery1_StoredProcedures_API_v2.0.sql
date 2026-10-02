/* Cobble ReadAlert Delivery 1 Stored Procedure/API Deployment v2.0
   Revised MVP scope: reader profile, authors, books, book authors, user books read, scan/search.
   Change the USE line before running.
   Intended targets:
     Cobbled_NoRLS = NoRLS test
     Cobbled_RLS   = RLS test after base tables are deployed
     Cobbled       = live ApplicationPlane database
*/
USE [Cobbled_NoRLS];
GO
SET NOCOUNT ON;
PRINT 'Starting ReadAlert Delivery 1 stored procedure/API deployment v2.0...';
PRINT 'Current database: ' + DB_NAME();
GO

IF SCHEMA_ID(N'ral') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA ral AUTHORIZATION dbo;');
END;
GO

DECLARE @Missing TABLE (ObjectName SYSNAME NOT NULL);
INSERT INTO @Missing (ObjectName)
SELECT v.ObjectName
FROM (VALUES
    (N'ral.ral_ReaderProfile'),
    (N'ral.ral_Authors'),
    (N'ral.ral_Books'),
    (N'ral.ral_BookAuthors'),
    (N'ral.ral_UserBooks'),
    (N'ral.ral_BookLookupLog')
) v(ObjectName)
WHERE OBJECT_ID(v.ObjectName, N'U') IS NULL;

IF EXISTS (SELECT 1 FROM @Missing)
BEGIN
    SELECT ObjectName AS MissingRequiredTable FROM @Missing ORDER BY ObjectName;
    THROW 57001, 'ReadAlert Delivery 1 stored procedure/API deployment failed. Required base tables are missing in the current database.', 1;
END;
GO

CREATE OR ALTER PROCEDURE ral.ral_ReaderProfile_CRUD_JSON
    @Action  NVARCHAR(20),
    @Payload NVARCHAR(MAX),
    @Result  NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ActionCode NVARCHAR(20) = UPPER(LTRIM(RTRIM(ISNULL(@Action, N''))));
    DECLARE @TenantID CHAR(32) = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.TenantID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'TenantID')));
    DECLARE @MemberID CHAR(32) = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.MemberID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'MemberID')));

    IF @TenantID IS NULL THROW 57100, 'TenantID is required in payload or SESSION_CONTEXT.', 1;
    IF @ActionCode IN (N'GET',    N'READ')   SET @ActionCode = N'SELECT';
    IF @ActionCode IN (N'CREATE', N'INSERT') SET @ActionCode = N'INSERT';
    IF @ActionCode IN (N'EDIT',   N'UPDATE') SET @ActionCode = N'UPDATE';
    IF @ActionCode IN (N'REMOVE', N'DELETE') SET @ActionCode = N'DELETE';

    IF @ActionCode = N'SELECT'
    BEGIN
        SET @Result = (
            SELECT TenantID, MemberID, ReaderDisplayName, PreferredGenres, PreferredAuthors,
                   AlertOptIn, BooksellerMembershipOptIn, ReaderStatusCode, CreatedUtc, UpdatedUtc
            FROM ral.ral_ReaderProfile
            WHERE TenantID = @TenantID
              AND (@MemberID IS NULL OR MemberID = @MemberID)
            ORDER BY CreatedUtc DESC
            FOR JSON PATH
        );
        SELECT @Result AS ResultJson;
        RETURN;
    END;

    IF @MemberID IS NULL THROW 57101, 'MemberID is required for ReaderProfile write actions.', 1;

    IF @ActionCode = N'INSERT'
    BEGIN
        IF EXISTS (SELECT 1 FROM ral.ral_ReaderProfile WHERE TenantID = @TenantID AND MemberID = @MemberID)
            THROW 57102, 'ReaderProfile already exists for this TenantID/MemberID.', 1;
        INSERT INTO ral.ral_ReaderProfile
            (TenantID, MemberID, ReaderDisplayName, PreferredGenres, PreferredAuthors, AlertOptIn,
             BooksellerMembershipOptIn, ReaderStatusCode, CreatedUtc)
        VALUES
            (@TenantID, @MemberID,
             JSON_VALUE(@Payload, '$.ReaderDisplayName'),
             JSON_VALUE(@Payload, '$.PreferredGenres'),
             JSON_VALUE(@Payload, '$.PreferredAuthors'),
             COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@Payload, '$.AlertOptIn')), 0),
             COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@Payload, '$.BooksellerMembershipOptIn')), 0),
             COALESCE(NULLIF(JSON_VALUE(@Payload, '$.ReaderStatusCode'), ''), 'ACTIVE'),
             SYSUTCDATETIME());
    END
    ELSE IF @ActionCode = N'UPDATE'
    BEGIN
        UPDATE ral.ral_ReaderProfile
        SET ReaderDisplayName         = COALESCE(JSON_VALUE(@Payload, '$.ReaderDisplayName'), ReaderDisplayName),
            PreferredGenres           = COALESCE(JSON_VALUE(@Payload, '$.PreferredGenres'), PreferredGenres),
            PreferredAuthors          = COALESCE(JSON_VALUE(@Payload, '$.PreferredAuthors'), PreferredAuthors),
            AlertOptIn                = COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@Payload, '$.AlertOptIn')), AlertOptIn),
            BooksellerMembershipOptIn = COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@Payload, '$.BooksellerMembershipOptIn')), BooksellerMembershipOptIn),
            ReaderStatusCode          = COALESCE(NULLIF(JSON_VALUE(@Payload, '$.ReaderStatusCode'), ''), ReaderStatusCode),
            UpdatedUtc                = SYSUTCDATETIME()
        WHERE TenantID = @TenantID AND MemberID = @MemberID;
        IF @@ROWCOUNT = 0 THROW 57103, 'ReaderProfile not found for update.', 1;
    END
    ELSE IF @ActionCode = N'DELETE'
    BEGIN
        UPDATE ral.ral_ReaderProfile
        SET ReaderStatusCode = 'INACTIVE', UpdatedUtc = SYSUTCDATETIME()
        WHERE TenantID = @TenantID AND MemberID = @MemberID;
        IF @@ROWCOUNT = 0 THROW 57104, 'ReaderProfile not found for delete/deactivate.', 1;
    END
    ELSE THROW 57105, 'Unsupported ReaderProfile action.', 1;

    SET @Result = (
        SELECT TenantID, MemberID, ReaderDisplayName, PreferredGenres, PreferredAuthors,
               AlertOptIn, BooksellerMembershipOptIn, ReaderStatusCode, CreatedUtc, UpdatedUtc
        FROM ral.ral_ReaderProfile
        WHERE TenantID = @TenantID AND MemberID = @MemberID
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );
    SELECT @Result AS ResultJson;
END;
GO

CREATE OR ALTER PROCEDURE ral.ral_Authors_CRUD_JSON
    @Action  NVARCHAR(20),
    @Payload NVARCHAR(MAX),
    @Result  NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ActionCode NVARCHAR(20) = UPPER(LTRIM(RTRIM(ISNULL(@Action, N''))));
    DECLARE @TenantID   CHAR(32)      = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.TenantID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'TenantID')));
    DECLARE @MemberID   CHAR(32)      = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.MemberID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'MemberID')));
    DECLARE @AuthorID   CHAR(32)      = NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.AuthorID')), '');
    DECLARE @SearchText NVARCHAR(200) = NULLIF(JSON_VALUE(@Payload, '$.SearchText'), '');
    IF @TenantID IS NULL THROW 57110, 'TenantID is required in payload or SESSION_CONTEXT.', 1;

    IF @ActionCode IN (N'GET',    N'READ')   SET @ActionCode = N'SELECT';
    IF @ActionCode IN (N'CREATE', N'INSERT') SET @ActionCode = N'INSERT';
    IF @ActionCode IN (N'EDIT',   N'UPDATE') SET @ActionCode = N'UPDATE';
    IF @ActionCode IN (N'REMOVE', N'DELETE') SET @ActionCode = N'DELETE';

    IF @ActionCode = N'SELECT'
    BEGIN
        SET @Result = (
            SELECT TOP (100) TenantID, AuthorID, AuthorName, AuthorSortName, Biography, Country,
                   WebsiteUrl, IsVerified, AuthorComments, CreatedByMemberID, CreatedUtc,
                   UpdatedByMemberID, UpdatedUtc, IsActive
            FROM ral.ral_Authors
            WHERE TenantID = @TenantID
              AND (@AuthorID   IS NULL OR AuthorID   = @AuthorID)
              AND (@SearchText IS NULL OR AuthorName LIKE N'%' + @SearchText + N'%' OR AuthorSortName LIKE N'%' + @SearchText + N'%')
            ORDER BY AuthorSortName, AuthorName
            FOR JSON PATH
        );
        SELECT @Result AS ResultJson;
        RETURN;
    END;

    IF @ActionCode = N'INSERT'
    BEGIN
        SET @AuthorID = COALESCE(@AuthorID, LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 32));
        IF EXISTS (SELECT 1 FROM ral.ral_Authors WHERE TenantID = @TenantID AND AuthorID = @AuthorID)
            THROW 57111, 'AuthorID already exists.', 1;
        INSERT INTO ral.ral_Authors
            (TenantID, AuthorID, AuthorName, AuthorSortName, Biography, Country, WebsiteUrl, IsVerified,
             AuthorComments, CreatedByMemberID, CreatedUtc, IsActive)
        VALUES
            (@TenantID, @AuthorID,
             JSON_VALUE(@Payload, '$.AuthorName'),
             COALESCE(JSON_VALUE(@Payload, '$.AuthorSortName'), JSON_VALUE(@Payload, '$.AuthorName')),
             JSON_VALUE(@Payload, '$.Biography'), JSON_VALUE(@Payload, '$.Country'), JSON_VALUE(@Payload, '$.WebsiteUrl'),
             COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@Payload, '$.IsVerified')), 0),
             JSON_VALUE(@Payload, '$.AuthorComments'), @MemberID, SYSUTCDATETIME(),
             COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@Payload, '$.IsActive')), 1));
    END
    ELSE IF @ActionCode = N'UPDATE'
    BEGIN
        IF @AuthorID IS NULL THROW 57112, 'AuthorID is required for update.', 1;
        UPDATE ral.ral_Authors
        SET AuthorName        = COALESCE(JSON_VALUE(@Payload, '$.AuthorName'),        AuthorName),
            AuthorSortName    = COALESCE(JSON_VALUE(@Payload, '$.AuthorSortName'),    AuthorSortName),
            Biography         = COALESCE(JSON_VALUE(@Payload, '$.Biography'),         Biography),
            Country           = COALESCE(JSON_VALUE(@Payload, '$.Country'),           Country),
            WebsiteUrl        = COALESCE(JSON_VALUE(@Payload, '$.WebsiteUrl'),        WebsiteUrl),
            IsVerified        = COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@Payload, '$.IsVerified')), IsVerified),
            AuthorComments    = COALESCE(JSON_VALUE(@Payload, '$.AuthorComments'),    AuthorComments),
            UpdatedByMemberID = @MemberID,
            UpdatedUtc        = SYSUTCDATETIME(),
            IsActive          = COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@Payload, '$.IsActive')), IsActive)
        WHERE TenantID = @TenantID AND AuthorID = @AuthorID;
        IF @@ROWCOUNT = 0 THROW 57113, 'Author not found for update.', 1;
    END
    ELSE IF @ActionCode = N'DELETE'
    BEGIN
        IF @AuthorID IS NULL THROW 57114, 'AuthorID is required for delete/deactivate.', 1;
        UPDATE ral.ral_Authors
        SET IsActive = 0, UpdatedByMemberID = @MemberID, UpdatedUtc = SYSUTCDATETIME()
        WHERE TenantID = @TenantID AND AuthorID = @AuthorID;
        IF @@ROWCOUNT = 0 THROW 57115, 'Author not found for delete/deactivate.', 1;
    END
    ELSE THROW 57116, 'Unsupported Authors action.', 1;

    SET @Result = (SELECT * FROM ral.ral_Authors WHERE TenantID = @TenantID AND AuthorID = @AuthorID FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    SELECT @Result AS ResultJson;
END;
GO

CREATE OR ALTER PROCEDURE ral.ral_Books_CRUD_JSON
    @Action  NVARCHAR(20),
    @Payload NVARCHAR(MAX),
    @Result  NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ActionCode NVARCHAR(20)  = UPPER(LTRIM(RTRIM(ISNULL(@Action, N''))));
    DECLARE @TenantID   CHAR(32)      = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.TenantID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'TenantID')));
    DECLARE @MemberID   CHAR(32)      = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.MemberID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'MemberID')));
    DECLARE @BookID     CHAR(32)      = NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.BookID')), '');
    DECLARE @SearchText NVARCHAR(300) = NULLIF(JSON_VALUE(@Payload, '$.SearchText'), '');
    IF @TenantID IS NULL THROW 57120, 'TenantID is required in payload or SESSION_CONTEXT.', 1;

    IF @ActionCode IN (N'GET',    N'READ')   SET @ActionCode = N'SELECT';
    IF @ActionCode IN (N'CREATE', N'INSERT') SET @ActionCode = N'INSERT';
    IF @ActionCode IN (N'EDIT',   N'UPDATE') SET @ActionCode = N'UPDATE';
    IF @ActionCode IN (N'REMOVE', N'DELETE') SET @ActionCode = N'DELETE';

    IF @ActionCode = N'SELECT'
    BEGIN
        SET @Result = (
            SELECT TOP (100) b.TenantID, b.BookID, b.ISBN10, b.ISBN13, b.BookTitle, b.Subtitle, b.Publisher,
                   b.PublishedDate, b.Edition, b.LanguageCode, b.CoverImageUrl, b.Description,
                   b.CreatedByMemberID, b.CreatedUtc, b.UpdatedByMemberID, b.UpdatedUtc, b.IsActive
            FROM ral.ral_Books b
            WHERE b.TenantID = @TenantID
              AND (@BookID     IS NULL OR b.BookID   = @BookID)
              AND (@SearchText IS NULL OR b.BookTitle LIKE N'%' + @SearchText + N'%' OR b.ISBN10 = @SearchText OR b.ISBN13 = @SearchText)
            ORDER BY b.BookTitle
            FOR JSON PATH
        );
        SELECT @Result AS ResultJson;
        RETURN;
    END;

    IF @ActionCode = N'INSERT'
    BEGIN
        SET @BookID = COALESCE(@BookID, LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 32));
        IF EXISTS (SELECT 1 FROM ral.ral_Books WHERE TenantID = @TenantID AND BookID = @BookID)
            THROW 57121, 'BookID already exists.', 1;
        INSERT INTO ral.ral_Books
            (TenantID, BookID, ISBN10, ISBN13, BookTitle, Subtitle, Publisher, PublishedDate, Edition,
             LanguageCode, CoverImageUrl, Description, CreatedByMemberID, CreatedUtc, IsActive)
        VALUES
            (@TenantID, @BookID,
             JSON_VALUE(@Payload, '$.ISBN10'), JSON_VALUE(@Payload, '$.ISBN13'),
             JSON_VALUE(@Payload, '$.BookTitle'), JSON_VALUE(@Payload, '$.Subtitle'), JSON_VALUE(@Payload, '$.Publisher'),
             TRY_CONVERT(DATE, JSON_VALUE(@Payload, '$.PublishedDate')), JSON_VALUE(@Payload, '$.Edition'),
             JSON_VALUE(@Payload, '$.LanguageCode'), JSON_VALUE(@Payload, '$.CoverImageUrl'), JSON_VALUE(@Payload, '$.Description'),
             @MemberID, SYSUTCDATETIME(), COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@Payload, '$.IsActive')), 1));
    END
    ELSE IF @ActionCode = N'UPDATE'
    BEGIN
        IF @BookID IS NULL THROW 57122, 'BookID is required for update.', 1;
        UPDATE ral.ral_Books
        SET ISBN10             = COALESCE(JSON_VALUE(@Payload, '$.ISBN10'),     ISBN10),
            ISBN13             = COALESCE(JSON_VALUE(@Payload, '$.ISBN13'),     ISBN13),
            BookTitle          = COALESCE(JSON_VALUE(@Payload, '$.BookTitle'),  BookTitle),
            Subtitle           = COALESCE(JSON_VALUE(@Payload, '$.Subtitle'),   Subtitle),
            Publisher          = COALESCE(JSON_VALUE(@Payload, '$.Publisher'),  Publisher),
            PublishedDate      = COALESCE(TRY_CONVERT(DATE, JSON_VALUE(@Payload, '$.PublishedDate')), PublishedDate),
            Edition            = COALESCE(JSON_VALUE(@Payload, '$.Edition'),    Edition),
            LanguageCode       = COALESCE(JSON_VALUE(@Payload, '$.LanguageCode'), LanguageCode),
            CoverImageUrl      = COALESCE(JSON_VALUE(@Payload, '$.CoverImageUrl'), CoverImageUrl),
            Description        = COALESCE(JSON_VALUE(@Payload, '$.Description'), Description),
            UpdatedByMemberID  = @MemberID,
            UpdatedUtc         = SYSUTCDATETIME(),
            IsActive           = COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@Payload, '$.IsActive')), IsActive)
        WHERE TenantID = @TenantID AND BookID = @BookID;
        IF @@ROWCOUNT = 0 THROW 57123, 'Book not found for update.', 1;
    END
    ELSE IF @ActionCode = N'DELETE'
    BEGIN
        IF @BookID IS NULL THROW 57124, 'BookID is required for delete/deactivate.', 1;
        UPDATE ral.ral_Books
        SET IsActive = 0, UpdatedByMemberID = @MemberID, UpdatedUtc = SYSUTCDATETIME()
        WHERE TenantID = @TenantID AND BookID = @BookID;
        IF @@ROWCOUNT = 0 THROW 57125, 'Book not found for delete/deactivate.', 1;
    END
    ELSE THROW 57126, 'Unsupported Books action.', 1;

    SET @Result = (SELECT * FROM ral.ral_Books WHERE TenantID = @TenantID AND BookID = @BookID FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    SELECT @Result AS ResultJson;
END;
GO

CREATE OR ALTER PROCEDURE ral.ral_BookAuthors_CRUD_JSON
    @Action  NVARCHAR(20),
    @Payload NVARCHAR(MAX),
    @Result  NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ActionCode   NVARCHAR(20) = UPPER(LTRIM(RTRIM(ISNULL(@Action, N''))));
    DECLARE @TenantID     CHAR(32)     = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.TenantID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'TenantID')));
    DECLARE @BookAuthorID CHAR(32)     = NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.BookAuthorID')), '');
    DECLARE @BookID       CHAR(32)     = NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.BookID')),       '');
    DECLARE @AuthorID     CHAR(32)     = NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.AuthorID')),     '');
    IF @TenantID IS NULL THROW 57130, 'TenantID is required in payload or SESSION_CONTEXT.', 1;

    IF @ActionCode IN (N'GET',    N'READ')   SET @ActionCode = N'SELECT';
    IF @ActionCode IN (N'CREATE', N'INSERT') SET @ActionCode = N'INSERT';
    IF @ActionCode IN (N'EDIT',   N'UPDATE') SET @ActionCode = N'UPDATE';
    IF @ActionCode IN (N'REMOVE', N'DELETE') SET @ActionCode = N'DELETE';

    IF @ActionCode = N'SELECT'
    BEGIN
        SET @Result = (
            SELECT ba.TenantID, ba.BookAuthorID, ba.BookID, b.BookTitle, ba.AuthorID, a.AuthorName,
                   ba.AuthorOrder, ba.ContributionCode, ba.CreatedUtc, ba.IsActive
            FROM ral.ral_BookAuthors ba
            INNER JOIN ral.ral_Books   b ON b.TenantID  = ba.TenantID AND b.BookID   = ba.BookID
            INNER JOIN ral.ral_Authors a ON a.TenantID  = ba.TenantID AND a.AuthorID = ba.AuthorID
            WHERE ba.TenantID = @TenantID
              AND (@BookAuthorID IS NULL OR ba.BookAuthorID = @BookAuthorID)
              AND (@BookID       IS NULL OR ba.BookID       = @BookID)
              AND (@AuthorID     IS NULL OR ba.AuthorID     = @AuthorID)
            ORDER BY b.BookTitle, ba.AuthorOrder, a.AuthorName
            FOR JSON PATH
        );
        SELECT @Result AS ResultJson;
        RETURN;
    END;

    IF @ActionCode = N'INSERT'
    BEGIN
        IF @BookID IS NULL OR @AuthorID IS NULL THROW 57131, 'BookID and AuthorID are required for BookAuthors insert.', 1;
        SET @BookAuthorID = COALESCE(@BookAuthorID, LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 32));
        INSERT INTO ral.ral_BookAuthors
            (TenantID, BookAuthorID, BookID, AuthorID, AuthorOrder, ContributionCode, CreatedUtc, IsActive)
        VALUES
            (@TenantID, @BookAuthorID, @BookID, @AuthorID,
             COALESCE(TRY_CONVERT(INT, JSON_VALUE(@Payload, '$.AuthorOrder')), 1),
             COALESCE(NULLIF(JSON_VALUE(@Payload, '$.ContributionCode'), ''), 'AUTHOR'),
             SYSUTCDATETIME(), COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@Payload, '$.IsActive')), 1));
    END
    ELSE IF @ActionCode = N'UPDATE'
    BEGIN
        IF @BookAuthorID IS NULL THROW 57132, 'BookAuthorID is required for update.', 1;
        UPDATE ral.ral_BookAuthors
        SET AuthorOrder      = COALESCE(TRY_CONVERT(INT, JSON_VALUE(@Payload, '$.AuthorOrder')), AuthorOrder),
            ContributionCode = COALESCE(NULLIF(JSON_VALUE(@Payload, '$.ContributionCode'), ''), ContributionCode),
            IsActive         = COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@Payload, '$.IsActive')), IsActive)
        WHERE TenantID = @TenantID AND BookAuthorID = @BookAuthorID;
        IF @@ROWCOUNT = 0 THROW 57133, 'BookAuthor link not found for update.', 1;
    END
    ELSE IF @ActionCode = N'DELETE'
    BEGIN
        IF @BookAuthorID IS NULL THROW 57134, 'BookAuthorID is required for delete/deactivate.', 1;
        UPDATE ral.ral_BookAuthors SET IsActive = 0 WHERE TenantID = @TenantID AND BookAuthorID = @BookAuthorID;
        IF @@ROWCOUNT = 0 THROW 57135, 'BookAuthor link not found for delete/deactivate.', 1;
    END
    ELSE THROW 57136, 'Unsupported BookAuthors action.', 1;

    SET @Result = (SELECT * FROM ral.ral_BookAuthors WHERE TenantID = @TenantID AND BookAuthorID = @BookAuthorID FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    SELECT @Result AS ResultJson;
END;
GO

CREATE OR ALTER PROCEDURE ral.ral_UserBooks_CRUD_JSON
    @Action  NVARCHAR(20),
    @Payload NVARCHAR(MAX),
    @Result  NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ActionCode NVARCHAR(20) = UPPER(LTRIM(RTRIM(ISNULL(@Action, N''))));
    DECLARE @TenantID   CHAR(32)     = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.TenantID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'TenantID')));
    DECLARE @MemberID   CHAR(32)     = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.MemberID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'MemberID')));
    DECLARE @UserBookID CHAR(32)     = NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.UserBookID')), '');
    DECLARE @BookID     CHAR(32)     = NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.BookID')),     '');
    IF @TenantID IS NULL THROW 57140, 'TenantID is required in payload or SESSION_CONTEXT.', 1;

    IF @ActionCode IN (N'GET',    N'READ')   SET @ActionCode = N'SELECT';
    IF @ActionCode IN (N'CREATE', N'INSERT') SET @ActionCode = N'INSERT';
    IF @ActionCode IN (N'EDIT',   N'UPDATE') SET @ActionCode = N'UPDATE';
    IF @ActionCode IN (N'REMOVE', N'DELETE') SET @ActionCode = N'DELETE';

    IF @ActionCode = N'SELECT'
    BEGIN
        SET @Result = (
            SELECT ub.TenantID, ub.UserBookID, ub.MemberID, ub.BookID, b.BookTitle, b.ISBN10, b.ISBN13,
                   ub.ReadingStatusCode, ub.StartedDate, ub.FinishedDate, ub.Rating,
                   ub.ReviewText, ub.PrivateNote, ub.SourceCode, ub.CreatedUtc, ub.UpdatedUtc, ub.IsActive
            FROM ral.ral_UserBooks ub
            INNER JOIN ral.ral_Books b ON b.TenantID = ub.TenantID AND b.BookID = ub.BookID
            WHERE ub.TenantID = @TenantID
              AND (@UserBookID IS NULL OR ub.UserBookID = @UserBookID)
              AND (@MemberID   IS NULL OR ub.MemberID   = @MemberID)
              AND (@BookID     IS NULL OR ub.BookID     = @BookID)
            ORDER BY COALESCE(ub.FinishedDate, ub.StartedDate, CONVERT(DATE, ub.CreatedUtc)) DESC, b.BookTitle
            FOR JSON PATH
        );
        SELECT @Result AS ResultJson;
        RETURN;
    END;

    IF @MemberID IS NULL THROW 57141, 'MemberID is required for UserBooks write actions.', 1;

    IF @ActionCode = N'INSERT'
    BEGIN
        IF @BookID IS NULL THROW 57142, 'BookID is required for UserBooks insert.', 1;
        SET @UserBookID = COALESCE(@UserBookID, LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 32));
        INSERT INTO ral.ral_UserBooks
            (TenantID, UserBookID, MemberID, BookID, ReadingStatusCode, StartedDate, FinishedDate, Rating,
             ReviewText, PrivateNote, SourceCode, CreatedUtc, IsActive)
        VALUES
            (@TenantID, @UserBookID, @MemberID, @BookID,
             COALESCE(NULLIF(JSON_VALUE(@Payload, '$.ReadingStatusCode'), ''), 'READ'),
             TRY_CONVERT(DATE, JSON_VALUE(@Payload, '$.StartedDate')),
             TRY_CONVERT(DATE, JSON_VALUE(@Payload, '$.FinishedDate')),
             TRY_CONVERT(TINYINT, JSON_VALUE(@Payload, '$.Rating')),
             JSON_VALUE(@Payload, '$.ReviewText'), JSON_VALUE(@Payload, '$.PrivateNote'),
             COALESCE(NULLIF(JSON_VALUE(@Payload, '$.SourceCode'), ''), 'MANUAL'),
             SYSUTCDATETIME(), COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@Payload, '$.IsActive')), 1));
    END
    ELSE IF @ActionCode = N'UPDATE'
    BEGIN
        IF @UserBookID IS NULL THROW 57143, 'UserBookID is required for update.', 1;
        UPDATE ral.ral_UserBooks
        SET ReadingStatusCode = COALESCE(NULLIF(JSON_VALUE(@Payload, '$.ReadingStatusCode'), ''), ReadingStatusCode),
            StartedDate       = COALESCE(TRY_CONVERT(DATE, JSON_VALUE(@Payload, '$.StartedDate')),   StartedDate),
            FinishedDate      = COALESCE(TRY_CONVERT(DATE, JSON_VALUE(@Payload, '$.FinishedDate')),  FinishedDate),
            Rating            = COALESCE(TRY_CONVERT(TINYINT, JSON_VALUE(@Payload, '$.Rating')),     Rating),
            ReviewText        = COALESCE(JSON_VALUE(@Payload, '$.ReviewText'),  ReviewText),
            PrivateNote       = COALESCE(JSON_VALUE(@Payload, '$.PrivateNote'), PrivateNote),
            SourceCode        = COALESCE(NULLIF(JSON_VALUE(@Payload, '$.SourceCode'), ''), SourceCode),
            UpdatedUtc        = SYSUTCDATETIME(),
            IsActive          = COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@Payload, '$.IsActive')), IsActive)
        WHERE TenantID = @TenantID AND UserBookID = @UserBookID AND MemberID = @MemberID;
        IF @@ROWCOUNT = 0 THROW 57144, 'UserBook not found for update or not owned by member.', 1;
    END
    ELSE IF @ActionCode = N'DELETE'
    BEGIN
        IF @UserBookID IS NULL THROW 57145, 'UserBookID is required for delete/deactivate.', 1;
        UPDATE ral.ral_UserBooks
        SET IsActive = 0, UpdatedUtc = SYSUTCDATETIME()
        WHERE TenantID = @TenantID AND UserBookID = @UserBookID AND MemberID = @MemberID;
        IF @@ROWCOUNT = 0 THROW 57146, 'UserBook not found for delete/deactivate or not owned by member.', 1;
    END
    ELSE THROW 57147, 'Unsupported UserBooks action.', 1;

    SET @Result = (SELECT * FROM ral.ral_UserBooks WHERE TenantID = @TenantID AND UserBookID = @UserBookID FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    SELECT @Result AS ResultJson;
END;
GO

CREATE OR ALTER PROCEDURE ral.ral_BookLookupLog_CRUD_JSON
    @Action  NVARCHAR(20),
    @Payload NVARCHAR(MAX),
    @Result  NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ActionCode      NVARCHAR(20) = UPPER(LTRIM(RTRIM(ISNULL(@Action, N''))));
    DECLARE @TenantID        CHAR(32)     = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.TenantID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'TenantID')));
    DECLARE @MemberID        CHAR(32)     = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.MemberID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'MemberID')));
    DECLARE @BookLookupLogID CHAR(32)     = NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.BookLookupLogID')), '');
    IF @TenantID IS NULL THROW 57150, 'TenantID is required in payload or SESSION_CONTEXT.', 1;
    IF @ActionCode IN (N'GET',    N'READ')   SET @ActionCode = N'SELECT';
    IF @ActionCode IN (N'CREATE', N'INSERT') SET @ActionCode = N'INSERT';

    IF @ActionCode = N'SELECT'
    BEGIN
        SET @Result = (
            SELECT TOP (200) TenantID, BookLookupLogID, MemberID, LookupTypeCode, SearchText, ISBN10, ISBN13,
                   MatchedBookID, ResultStatusCode, ExternalSourceCode, ErrorMessage, CreatedUtc
            FROM ral.ral_BookLookupLog
            WHERE TenantID = @TenantID
              AND (@BookLookupLogID IS NULL OR BookLookupLogID = @BookLookupLogID)
              AND (@MemberID        IS NULL OR MemberID        = @MemberID)
            ORDER BY CreatedUtc DESC
            FOR JSON PATH
        );
        SELECT @Result AS ResultJson;
        RETURN;
    END;

    IF @ActionCode = N'INSERT'
    BEGIN
        SET @BookLookupLogID = COALESCE(@BookLookupLogID, LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 32));
        INSERT INTO ral.ral_BookLookupLog
            (TenantID, BookLookupLogID, MemberID, LookupTypeCode, SearchText, ISBN10, ISBN13, MatchedBookID,
             ResultStatusCode, ExternalSourceCode, ErrorMessage, CreatedUtc)
        VALUES
            (@TenantID, @BookLookupLogID, @MemberID,
             COALESCE(NULLIF(JSON_VALUE(@Payload, '$.LookupTypeCode'), ''), 'MANUAL_ENTRY'),
             JSON_VALUE(@Payload, '$.SearchText'), JSON_VALUE(@Payload, '$.ISBN10'), JSON_VALUE(@Payload, '$.ISBN13'),
             NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.MatchedBookID')), ''),
             COALESCE(NULLIF(JSON_VALUE(@Payload, '$.ResultStatusCode'), ''), 'MANUAL_CREATED'),
             JSON_VALUE(@Payload, '$.ExternalSourceCode'), JSON_VALUE(@Payload, '$.ErrorMessage'), SYSUTCDATETIME());
    END
    ELSE THROW 57151, 'BookLookupLog supports SELECT and INSERT only.', 1;

    SET @Result = (SELECT * FROM ral.ral_BookLookupLog WHERE TenantID = @TenantID AND BookLookupLogID = @BookLookupLogID FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    SELECT @Result AS ResultJson;
END;
GO

CREATE OR ALTER PROCEDURE ral.ral_SearchBooks_JSON
    @Payload NVARCHAR(MAX),
    @Result  NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TenantID   CHAR(32)      = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.TenantID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'TenantID')));
    DECLARE @MemberID   CHAR(32)      = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.MemberID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'MemberID')));
    DECLARE @SearchText NVARCHAR(500) = NULLIF(JSON_VALUE(@Payload, '$.SearchText'), '');
    DECLARE @SearchType VARCHAR(30)   = COALESCE(NULLIF(UPPER(JSON_VALUE(@Payload, '$.SearchType')), ''), 'TITLE_SEARCH');
    DECLARE @Limit      INT           = COALESCE(TRY_CONVERT(INT, JSON_VALUE(@Payload, '$.Limit')), 25);
    DECLARE @LookupID   CHAR(32)      = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 32);
    DECLARE @MatchCount INT;
    DECLARE @ResultStatus VARCHAR(30);

    IF @TenantID  IS NULL THROW 57160, 'TenantID is required in payload or SESSION_CONTEXT.', 1;
    IF @SearchText IS NULL THROW 57161, 'SearchText is required.', 1;
    IF @Limit < 1 OR @Limit > 100 SET @Limit = 25;

    DECLARE @Matches TABLE
    (
        BookID        CHAR(32)      NOT NULL,
        BookTitle     NVARCHAR(300) NOT NULL,
        ISBN10        NVARCHAR(20)  NULL,
        ISBN13        NVARCHAR(20)  NULL,
        Publisher     NVARCHAR(200) NULL,
        PublishedDate DATE          NULL,
        AuthorName    NVARCHAR(200) NULL
    );

    INSERT INTO @Matches (BookID, BookTitle, ISBN10, ISBN13, Publisher, PublishedDate, AuthorName)
    SELECT DISTINCT TOP (@Limit)
        b.BookID, b.BookTitle, b.ISBN10, b.ISBN13, b.Publisher, b.PublishedDate, a.AuthorName
    FROM ral.ral_Books b
    LEFT JOIN ral.ral_BookAuthors ba ON ba.TenantID = b.TenantID AND ba.BookID = b.BookID AND ba.IsActive = 1
    LEFT JOIN ral.ral_Authors     a  ON a.TenantID  = ba.TenantID AND a.AuthorID = ba.AuthorID AND a.IsActive = 1
    WHERE b.TenantID = @TenantID
      AND b.IsActive = 1
      AND (
            (@SearchType IN ('ISBN_SEARCH','ISBN_SCAN') AND (b.ISBN10 = @SearchText OR b.ISBN13 = @SearchText))
         OR (@SearchType = 'TITLE_SEARCH'  AND b.BookTitle  LIKE N'%' + @SearchText + N'%')
         OR (@SearchType = 'AUTHOR_SEARCH' AND a.AuthorName LIKE N'%' + @SearchText + N'%')
         OR (@SearchType = 'ANY'           AND (b.BookTitle LIKE N'%' + @SearchText + N'%' OR b.ISBN10 = @SearchText OR b.ISBN13 = @SearchText OR a.AuthorName LIKE N'%' + @SearchText + N'%'))
      )
    ORDER BY b.BookTitle;

    SELECT @MatchCount = COUNT(*) FROM @Matches;
    SET @ResultStatus  = CASE WHEN @MatchCount = 0 THEN 'NOT_MATCHED' WHEN @MatchCount = 1 THEN 'MATCHED' ELSE 'MULTIPLE_MATCHES' END;

    INSERT INTO ral.ral_BookLookupLog
        (TenantID, BookLookupLogID, MemberID, LookupTypeCode, SearchText, ISBN10, ISBN13, MatchedBookID, ResultStatusCode, ExternalSourceCode, ErrorMessage, CreatedUtc)
    SELECT @TenantID, @LookupID, @MemberID,
           CASE WHEN @SearchType IN ('ISBN_SEARCH','ISBN_SCAN') THEN @SearchType WHEN @SearchType = 'AUTHOR_SEARCH' THEN 'AUTHOR_SEARCH' ELSE 'TITLE_SEARCH' END,
           @SearchText,
           CASE WHEN @SearchType IN ('ISBN_SEARCH','ISBN_SCAN') AND LEN(@SearchText) <= 10 THEN @SearchText ELSE NULL END,
           CASE WHEN @SearchType IN ('ISBN_SEARCH','ISBN_SCAN') AND LEN(@SearchText) >  10 THEN @SearchText ELSE NULL END,
           CASE WHEN @MatchCount = 1 THEN (SELECT TOP (1) BookID FROM @Matches) ELSE NULL END,
           @ResultStatus, JSON_VALUE(@Payload, '$.ExternalSourceCode'), NULL, SYSUTCDATETIME();

    SET @Result = (
        SELECT @LookupID     AS BookLookupLogID,
               @SearchType   AS SearchType,
               @SearchText   AS SearchText,
               @MatchCount   AS MatchCount,
               @ResultStatus AS ResultStatusCode,
               JSON_QUERY((SELECT * FROM @Matches ORDER BY BookTitle FOR JSON PATH)) AS Books
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );
    SELECT @Result AS ResultJson;
END;
GO

CREATE OR ALTER PROCEDURE ral.ral_ScanBook_JSON
    @Payload NVARCHAR(MAX),
    @Result  NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ISBN NVARCHAR(20) = COALESCE(
        NULLIF(JSON_VALUE(@Payload, '$.ISBN13'), ''),
        NULLIF(JSON_VALUE(@Payload, '$.ISBN10'), ''),
        NULLIF(JSON_VALUE(@Payload, '$.ISBN'),   '')
    );
    IF @ISBN IS NULL THROW 57170, 'ISBN, ISBN10 or ISBN13 is required.', 1;
    DECLARE @SearchPayload NVARCHAR(MAX) = JSON_MODIFY(@Payload, '$.SearchText', @ISBN);
    SET @SearchPayload = JSON_MODIFY(@SearchPayload, '$.SearchType', 'ISBN_SCAN');
    EXEC ral.ral_SearchBooks_JSON @Payload = @SearchPayload, @Result = @Result OUTPUT;
END;
GO

CREATE OR ALTER PROCEDURE ral.ral_AddBookRead_JSON
    @Payload NVARCHAR(MAX),
    @Result  NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TenantID   CHAR(32)      = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.TenantID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'TenantID')));
    DECLARE @MemberID   CHAR(32)      = COALESCE(NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.MemberID')), ''), CONVERT(CHAR(32), SESSION_CONTEXT(N'MemberID')));
    DECLARE @BookID     CHAR(32)      = NULLIF(CONVERT(CHAR(32), JSON_VALUE(@Payload, '$.BookID')), '');
    DECLARE @AuthorID   CHAR(32);
    DECLARE @AuthorName NVARCHAR(200) = NULLIF(JSON_VALUE(@Payload, '$.AuthorName'), '');
    DECLARE @UserBookID CHAR(32);
    IF @TenantID IS NULL THROW 57180, 'TenantID is required in payload or SESSION_CONTEXT.', 1;
    IF @MemberID IS NULL THROW 57181, 'MemberID is required in payload or SESSION_CONTEXT.', 1;

    IF @BookID IS NULL
    BEGIN
        SELECT TOP (1) @BookID = BookID FROM ral.ral_Books
        WHERE TenantID = @TenantID
          AND ((ISBN13 IS NOT NULL AND ISBN13 = JSON_VALUE(@Payload, '$.ISBN13'))
            OR (ISBN10 IS NOT NULL AND ISBN10 = JSON_VALUE(@Payload, '$.ISBN10')));
    END;

    IF @BookID IS NULL
    BEGIN
        IF NULLIF(JSON_VALUE(@Payload, '$.BookTitle'), '') IS NULL
            THROW 57182, 'BookID or BookTitle/ISBN metadata is required to add a read book.', 1;
        SET @BookID = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 32);
        INSERT INTO ral.ral_Books
            (TenantID, BookID, ISBN10, ISBN13, BookTitle, Subtitle, Publisher, PublishedDate, Edition, LanguageCode,
             CoverImageUrl, Description, CreatedByMemberID, CreatedUtc, IsActive)
        VALUES
            (@TenantID, @BookID,
             JSON_VALUE(@Payload, '$.ISBN10'), JSON_VALUE(@Payload, '$.ISBN13'),
             JSON_VALUE(@Payload, '$.BookTitle'), JSON_VALUE(@Payload, '$.Subtitle'), JSON_VALUE(@Payload, '$.Publisher'),
             TRY_CONVERT(DATE, JSON_VALUE(@Payload, '$.PublishedDate')), JSON_VALUE(@Payload, '$.Edition'),
             JSON_VALUE(@Payload, '$.LanguageCode'), JSON_VALUE(@Payload, '$.CoverImageUrl'),
             JSON_VALUE(@Payload, '$.Description'), @MemberID, SYSUTCDATETIME(), 1);

        IF @AuthorName IS NOT NULL
        BEGIN
            SELECT TOP (1) @AuthorID = AuthorID FROM ral.ral_Authors WHERE TenantID = @TenantID AND AuthorName = @AuthorName;
            IF @AuthorID IS NULL
            BEGIN
                SET @AuthorID = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 32);
                INSERT INTO ral.ral_Authors (TenantID, AuthorID, AuthorName, AuthorSortName, CreatedByMemberID, CreatedUtc, IsActive)
                VALUES (@TenantID, @AuthorID, @AuthorName, @AuthorName, @MemberID, SYSUTCDATETIME(), 1);
            END;
            INSERT INTO ral.ral_BookAuthors (TenantID, BookAuthorID, BookID, AuthorID, AuthorOrder, ContributionCode, CreatedUtc, IsActive)
            VALUES (@TenantID, LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 32), @BookID, @AuthorID, 1, 'AUTHOR', SYSUTCDATETIME(), 1);
        END;
    END;

    SELECT @UserBookID = UserBookID FROM ral.ral_UserBooks WHERE TenantID = @TenantID AND MemberID = @MemberID AND BookID = @BookID;

    IF @UserBookID IS NULL
    BEGIN
        SET @UserBookID = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 32);
        INSERT INTO ral.ral_UserBooks
            (TenantID, UserBookID, MemberID, BookID, ReadingStatusCode, StartedDate, FinishedDate, Rating,
             ReviewText, PrivateNote, SourceCode, CreatedUtc, IsActive)
        VALUES
            (@TenantID, @UserBookID, @MemberID, @BookID,
             COALESCE(NULLIF(JSON_VALUE(@Payload, '$.ReadingStatusCode'), ''), 'READ'),
             TRY_CONVERT(DATE, JSON_VALUE(@Payload, '$.StartedDate')),
             TRY_CONVERT(DATE, JSON_VALUE(@Payload, '$.FinishedDate')),
             TRY_CONVERT(TINYINT, JSON_VALUE(@Payload, '$.Rating')),
             JSON_VALUE(@Payload, '$.ReviewText'), JSON_VALUE(@Payload, '$.PrivateNote'),
             COALESCE(NULLIF(JSON_VALUE(@Payload, '$.SourceCode'), ''), 'MANUAL'), SYSUTCDATETIME(), 1);
    END
    ELSE
    BEGIN
        UPDATE ral.ral_UserBooks
        SET ReadingStatusCode = COALESCE(NULLIF(JSON_VALUE(@Payload, '$.ReadingStatusCode'), ''), ReadingStatusCode),
            StartedDate       = COALESCE(TRY_CONVERT(DATE, JSON_VALUE(@Payload, '$.StartedDate')),  StartedDate),
            FinishedDate      = COALESCE(TRY_CONVERT(DATE, JSON_VALUE(@Payload, '$.FinishedDate')), FinishedDate),
            Rating            = COALESCE(TRY_CONVERT(TINYINT, JSON_VALUE(@Payload, '$.Rating')),    Rating),
            ReviewText        = COALESCE(JSON_VALUE(@Payload, '$.ReviewText'),  ReviewText),
            PrivateNote       = COALESCE(JSON_VALUE(@Payload, '$.PrivateNote'), PrivateNote),
            SourceCode        = COALESCE(NULLIF(JSON_VALUE(@Payload, '$.SourceCode'), ''), SourceCode),
            UpdatedUtc        = SYSUTCDATETIME(), IsActive = 1
        WHERE TenantID = @TenantID AND UserBookID = @UserBookID;
    END;

    SET @Result = (
        SELECT ub.TenantID, ub.UserBookID, ub.MemberID, ub.BookID, b.BookTitle, b.ISBN10, b.ISBN13,
               ub.ReadingStatusCode, ub.StartedDate, ub.FinishedDate, ub.Rating, ub.ReviewText,
               ub.PrivateNote, ub.SourceCode, ub.CreatedUtc, ub.UpdatedUtc, ub.IsActive
        FROM ral.ral_UserBooks ub
        INNER JOIN ral.ral_Books b ON b.TenantID = ub.TenantID AND b.BookID = ub.BookID
        WHERE ub.TenantID = @TenantID AND ub.UserBookID = @UserBookID
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );
    SELECT @Result AS ResultJson;
END;
GO

CREATE OR ALTER PROCEDURE ral.ral_UpdateBookRead_JSON
    @Payload NVARCHAR(MAX),
    @Result  NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InnerResult NVARCHAR(MAX);
    EXEC ral.ral_UserBooks_CRUD_JSON @Action = N'UPDATE', @Payload = @Payload, @Result = @InnerResult OUTPUT;
    SET @Result = @InnerResult;
END;
GO

PRINT 'ReadAlert Delivery 1 stored procedure/API deployment v2.0 complete.';
GO

