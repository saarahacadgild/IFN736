ReadAlert Delivery 1

Cobbled User Application Plane module. Module code: RAL | Route: api/ral/v01 | Schema: ral | DB: Cobbled_NoRLS

FOLDER LAYOUT (Developer Instructions section 4)

ReadAlert-v3/
  module.manifest.json
  README.md
  assets/
  api/
      Program.cs                        <- pure Minimal API (Wayne EDP pattern)
      ReadAlert.Api.csproj
      appsettings.json
      appsettings.Development.json
      Middleware/TenantContextMiddleware.cs    <- Wayne skeleton verbatim
      Repositories/IReadAlertRepository.cs    <- Wayne skeleton verbatim
      Repositories/SqlReadAlertRepository.cs  <- Wayne skeleton verbatim
      Services/IReadAlertService.cs           <- Wayne skeleton verbatim
      Services/ReadAlertService.cs            <- Wayne skeleton verbatim
  database/no-rls/
      00_ ... Preflight (tables + schema + indexes)
      00a_ ... DEVTEST Reset
      01a_ ... NoRLS Verification
      01b_ ... TestData
      02_ ... StoredProcedures_API  <- all 10 SPs (Wayne SP Pack verbatim)
      02a_ ... SP Verification
  scripts/
      install.ps1
      verify.ps1
  service/service.manifest.json
  ReadAlert.sln

SQL RUN ORDER (Wayne SP Pack README)
  1. 00_ Preflight (creates schema + 6 tables + indexes)
  2. 01b_ TestData (seeds Avery Reader, The Martian, Murder on Orient Express)
  3. 02_ StoredProcedures_API (deploys 10 stored procedures)
  4. 01a_ NoRLS Verification (confirms tables + record counts)
  5. 02a_ SP Verification (confirms SPs + PASS/CHECK live queries)
  Reset: 00a_ DEVTEST Reset, then re-run from step 1.

TEST CREDENTIALS
  TenantID: F115B0A094467E7FCBA8DB16DF52242E
  MemberID: 00000000000000000000000000000001

BOOK LOOKUP ENDPOINTS (your task)
  POST /api/ral/v01/books/search
    Body: { "SearchType": "TITLE_SEARCH", "SearchText": "Martian", "Limit": 10 }
    -> ral.ral_SearchBooks_JSON

  POST /api/ral/v01/books/scan
    Body: { "ISBN13": "9780553418026", "ExternalSourceCode": "LOCAL" }
    -> ral.ral_ScanBook_JSON

ALL 16 ENDPOINTS
  GET    /api/ral/v01/reader-profile        -> ral_ReaderProfile_CRUD_JSON
  POST   /api/ral/v01/reader-profile        -> ral_ReaderProfile_CRUD_JSON
  PUT    /api/ral/v01/reader-profile        -> ral_ReaderProfile_CRUD_JSON
  GET    /api/ral/v01/authors               -> ral_Authors_CRUD_JSON
  POST   /api/ral/v01/authors               -> ral_Authors_CRUD_JSON
  GET    /api/ral/v01/authors/{authorId}    -> ral_Authors_CRUD_JSON
  PUT    /api/ral/v01/authors/{authorId}    -> ral_Authors_CRUD_JSON
  DELETE /api/ral/v01/authors/{authorId}    -> ral_Authors_CRUD_JSON
  GET    /api/ral/v01/books                 -> ral_Books_CRUD_JSON
  POST   /api/ral/v01/books                 -> ral_Books_CRUD_JSON
  POST   /api/ral/v01/books/search          -> ral_SearchBooks_JSON  **
  POST   /api/ral/v01/books/scan            -> ral_ScanBook_JSON     **
  GET    /api/ral/v01/books/{bookId}        -> ral_Books_CRUD_JSON
  PUT    /api/ral/v01/books/{bookId}        -> ral_Books_CRUD_JSON
  GET    /api/ral/v01/user-books            -> ral_UserBooks_CRUD_JSON
  POST   /api/ral/v01/user-books            -> ral_AddBookRead_JSON
  PUT    /api/ral/v01/user-books/{id}       -> ral_UpdateBookRead_JSON
  DELETE /api/ral/v01/user-books/{id}       -> ral_UserBooks_CRUD_JSON
  GET    /api/ral/v01/health  (unauthenticated)
  GET    /api/ral/v01/readiness (unauthenticated)

RUNNING LOCALLY (Windows)
  cd api
  dotnet restore
  dotnet run

RUNNING LOCALLY (Mac - Docker SQL)
  docker run -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD=YourStrong@Passw0rd \
    -p 1433:1433 --name sql-cobbled -d mcr.microsoft.com/azure-sql-edge
  Update appsettings.Development.json CobbledData to:
    Server=localhost,1433;Database=Cobbled_NoRLS;User Id=sa;Password=YourStrong@Passw0rd;TrustServerCertificate=True;
  ASPNETCORE_ENVIRONMENT=Development dotnet run

