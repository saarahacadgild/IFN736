Prerequisites — What You Need Installed
You need four tools. Check each one first; install only what is missing.

1 — .NET 8 SDK
Open Command Prompt and run:



dotnet --version
You need 8.x.x. If missing or older, download from:

https://dotnet.microsoft.com/download/dotnet/8.0

Download the SDK (not just the Runtime). Run the installer, then restart Command Prompt and re-run dotnet --version to confirm.

2 — SQL Server (Local Instance)
Open SQL Server Management Studio (SSMS) and try to connect to localhost or .\SQLEXPRESS.

If you can connect → you already have SQL Server ✅
If not → download SQL Server 2022 Developer Edition (free):
https://www.microsoft.com/en-au/sql-server/sql-server-downloads

Choose Developer edition → click Download now → run the installer → choose Basic install type → accept defaults.
3 — SQL Server Management Studio (SSMS)
If SSMS is not installed:

https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms

Download and run the installer. Accept all defaults.

4 — sqlcmd
Open Command Prompt and run:



sqlcmd -?
If you see a usage message → installed ✅

If not, install the Microsoft ODBC Driver + sqlcmd tools:

https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility

Download sqlcmd for Windows → run the installer → restart Command Prompt → run sqlcmd -? to confirm.

Part 1 — Create the Database
The Cobbled_NoRLS database does not exist yet on your machine. You need to create it by running Wayne's MMS seed script first.

Step 1.1 — Open SSMS and connect
Open SQL Server Management Studio
In the Connect to Server window:
Server type: Database Engine
Server name: localhost (or .\SQLEXPRESS if you installed Express edition)
Authentication: Windows Authentication
Click Connect
You should see your server appear in Object Explorer on the left.

Step 1.2 — Create the Cobbled_NoRLS database
In SSMS, click New Query (top toolbar), paste the following, and press F5 to execute:

sql


IF DB_ID(N'Cobbled_NoRLS') IS NULL
BEGIN
    CREATE DATABASE Cobbled_NoRLS;
    PRINT 'Cobbled_NoRLS database created.';
END
ELSE
    PRINT 'Cobbled_NoRLS already exists — no action taken.';
GO
You should see Cobbled_NoRLS appear under Databases in Object Explorer (press F5 to refresh the tree if needed).

Step 1.3 — Run the MMS seed script (creates platform tables)
Wayne's MMS pack provides the platform-level tables that Cobbled_NoRLS requires before any module scripts run.

In SSMS, go to File → Open → File...
Navigate to the MMS NoRLS folder from Wayne's database pack:


NoRLS\UserApp_Module_mms_NoRLS_Build_v2.2.sql
The script has a USE statement at the top — make sure it says USE [Cobbled_NoRLS]
Press F5 to execute
Wait for Command(s) completed successfully in the Messages tab
Then run the MMS test data script:

File → Open → File... → open UserApp_Module_mms_TestData_v2.2.1.sql
Confirm the USE [Cobbled_NoRLS] line at the top
Press F5
✅ At this point Cobbled_NoRLS exists and has the MMS platform tables + seed data including TenantID F115B0A094467E7FCBA8DB16DF52242E and MemberID 00000000000000000000000000000001.

Part 2 — Install the ReadAlert Module Database
Now run your three ReadAlert SQL scripts in order. All are in your project's database\no-rls\ folder.

Option A — Using the PowerShell install script (recommended)
Open PowerShell (not Command Prompt):

powershell


# Navigate into your project's scripts folder
cd C:\path\to\ReadAlert-v3\scripts

# Run the install script using Windows Integrated Security
pwsh .\install.ps1 -IntegratedSecurity
Replace C:\path\to\ReadAlert-v3 with your actual project path.

You should see output like:



==========================================
  ReadAlert Delivery 1 - NoRLS Install
==========================================
  Target  : NoRLS
  Server  : localhost,1433
  Database: Cobbled_NoRLS

  Running: 00_ReadAlert_Delivery1_TargetDatabase_Preflight_v2.0.sql
  Running: 01b_ReadAlert_Delivery1_TestData_v2.0.sql
  Running: 02_ReadAlert_Delivery1_StoredProcedures_API_v2.0.sql

Installation complete.
Next step: run verify.ps1 to confirm all tables and stored procedures are present.
If you see an error about execution policy, run this first then retry:

powershell


Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Option B — Run each SQL file manually in SSMS
If PowerShell is not available or the script fails, run each file manually in SSMS in this exact order:

Step 1 — Tables and schema (Preflight)

File → Open → database\no-rls\00_ReadAlert_Delivery1_TargetDatabase_Preflight_v2.0.sql
Press F5
Expected output in Messages tab:


Starting ReadAlert Delivery 1 Base NoRLS table deployment v2.0...
ReadAlert Delivery 1 Base NoRLS table deployment v2.0 complete.
Step 2 — Seed test data

File → Open → database\no-rls\01b_ReadAlert_Delivery1_TestData_v2.0.sql
Press F5
Expected output:


Seeding ReadAlert Delivery 1 sample data v2.0 if not already present...
ReadAlert Delivery 1 sample data v2.0 seeded successfully.
Step 3 — Deploy stored procedures

File → Open → database\no-rls\02_ReadAlert_Delivery1_StoredProcedures_API_v2.0.sql
Press F5
Expected output:


Starting ReadAlert Delivery 1 stored procedure/API deployment v2.0...
ReadAlert Delivery 1 stored procedure/API deployment v2.0 complete.
Part 3 — Verify the Database
Run the verification scripts to confirm everything deployed correctly.

Option A — Using the PowerShell verify script
powershell


# Still in your scripts/ folder
pwsh .\verify.ps1 -IntegratedSecurity
Expected output ends with:



Verification complete. All tables and stored procedures confirmed.
Option B — Run manually in SSMS
Step 1 — Verify tables

File → Open → database\no-rls\01a_ReadAlert_Delivery1_NoRLS_Verification_v2.0.sql
Press F5
You should see a results grid with 6 rows, all showing Present:


ObjectName	ObjectStatus
ral.ral_Authors	Present
ral.ral_BookAuthors	Present
ral.ral_BookLookupLog	Present
ral.ral_Books	Present
ral.ral_ReaderProfile	Present
ral.ral_UserBooks	Present
And a second grid showing record counts (each table should have at least 1–3 rows from test data).

Step 2 — Verify stored procedures

File → Open → database\no-rls\02a_ReadAlert_Delivery1_SP_API_Verification_v2.0.sql
Press F5
You should see a grid with 10 rows all showing Present
Then several test result grids — look for PASS in the TestStatus column for each test:


TestName	TestStatus
ReaderProfile_SELECT	PASS
Authors_SELECT	PASS
SearchBooks_TITLE	PASS
ScanBook_ISBN13	PASS
AddBookRead_UPSERT	PASS
UserBooks_SELECT	PASS
✅ If all show PASS — your database layer is fully working.

⚠️ If any show CHECK — the SP ran but the expected seed data may be missing. Re-run the test data script (01b_) then re-run verification._

Part 4 — Configure the API
Step 4.1 — Check appsettings.json
Open api\appsettings.json in any text editor (Notepad, VS Code, Visual Studio). It should look like this:

json


{
  "ConnectionStrings": {
    "CobbledData": "Server=.;Database=Cobbled_NoRLS;Trusted_Connection=True;TrustServerCertificate=True;"
  },
  ...
}
The connection string Server=. means "local SQL Server using Windows Authentication". This is correct for Windows — no changes needed unless:

You installed SQL Server Express → change Server=. to Server=.\SQLEXPRESS
Your SQL Server has a named instance → change to Server=.\YOURINSTANCENAME
To find your instance name: in SSMS Object Explorer the server name shows as YOURPC\INSTANCENAME. Use that after the backslash.

Step 4.2 — Check appsettings.Development.json
Open api\appsettings.Development.json. It should look like this:

json


{
  "ConnectionStrings": {
    "CobbledData": "Server=localhost,1433;Database=Cobbled_NoRLS;User Id=sa;Password=YourStrong@Passw0rd;TrustServerCertificate=True;"
  },
  "DevToken": {
    "Enabled":  "true",
    "Token":    "local-dev-secret",
    "TenantID": "F115B0A094467E7FCBA8DB16DF52242E",
    "MemberID": "00000000000000000000000000000001"
  }
}
This file is used when ASPNETCORE_ENVIRONMENT=Development is set. On Windows with a local SQL Server, it is easier to use the base appsettings.json with Windows Auth (which is the default). The Development file is mainly needed for Docker/Mac.

Part 5 — Run the API
Step 5.1 — Open a terminal in the api folder
Open Command Prompt or PowerShell, then navigate to the api folder:

powershell


cd C:\path\to\ReadAlert-v3\api
Step 5.2 — Restore NuGet packages


dotnet restore
Expected output: Restore complete. with no errors.

Step 5.3 — Start the API


dotnet run
You will see output similar to:



Building...
info: Microsoft.Hosting.Lifetime[14]
      Now listening on: http://localhost:5000
info: Microsoft.Hosting.Lifetime[14]
      Now listening on: https://localhost:7001
info: Microsoft.Hosting.Lifetime[0]
      Application started. Press Ctrl+C to shut down.
✅ The API is now running. Keep this window open — closing it stops the server.

⚠️ If you see a port conflict error (address already in use), add a --urls flag:



dotnet run --urls "http://localhost:5050"
Part 6 — Test the API
With the API running, open a second Command Prompt or PowerShell window to send requests.

The dev-token header X-Dev-Token: local-dev-secret replaces JWT authentication in development. Add it to every request.

Test 1 — Health Check (no auth needed)
powershell


Invoke-WebRequest -Uri "http://localhost:5000/api/ral/v01/health" -Method GET | Select-Object -ExpandProperty Content
Expected response:

json


{"service":"ReadAlert","version":"1.0.0","status":"healthy"}
Test 2 — Readiness Check (no auth needed)
powershell


Invoke-WebRequest -Uri "http://localhost:5000/api/ral/v01/readiness" -Method GET | Select-Object -ExpandProperty Content
Expected response:

json


{"service":"ReadAlert","version":"1.0.0","status":"ready"}
Test 3 — Book Search (your Book Lookup task)
powershell


$headers = @{ "X-Dev-Token" = "local-dev-secret"; "Content-Type" = "application/json" }
$body    = '{ "SearchType": "TITLE_SEARCH", "SearchText": "Martian", "Limit": 10 }'

Invoke-WebRequest -Uri "http://localhost:5000/api/ral/v01/books/search" `
    -Method POST -Headers $headers -Body $body | Select-Object -ExpandProperty Content
Expected response (formatted for readability):

json


{
  "BookLookupLogID": "...",
  "SearchType": "TITLE_SEARCH",
  "SearchText": "Martian",
  "MatchCount": 1,
  "ResultStatusCode": "MATCHED",
  "Books": [
    {

Show 11 more lines
Test 4 — ISBN Scan (your Book Lookup task)
powershell


$headers = @{ "X-Dev-Token" = "local-dev-secret"; "Content-Type" = "application/json" }
$body    = '{ "ISBN13": "9780553418026", "ExternalSourceCode": "LOCAL" }'

Invoke-WebRequest -Uri "http://localhost:5000/api/ral/v01/books/scan" `
    -Method POST -Headers $headers -Body $body | Select-Object -ExpandProperty Content
Expected response:

json


{
  "BookLookupLogID": "...",
  "SearchType": "ISBN_SCAN",
  "SearchText": "9780553418026",
  "MatchCount": 1,
  "ResultStatusCode": "MATCHED",
  "Books": [{ "BookTitle": "The Martian", ... }]
}
Test 5 — Get Reader Profile
powershell


$headers = @{ "X-Dev-Token" = "local-dev-secret" }

Invoke-WebRequest -Uri "http://localhost:5000/api/ral/v01/reader-profile" `
    -Method GET -Headers $headers | Select-Object -ExpandProperty Content
Expected: JSON with ReaderDisplayName: "Avery Reader"

Test 6 — Author Search
powershell


$headers = @{ "X-Dev-Token" = "local-dev-secret" }

Invoke-WebRequest -Uri "http://localhost:5000/api/ral/v01/authors?searchText=Christie" `
    -Method GET -Headers $headers | Select-Object -ExpandProperty Content
Expected: JSON array containing Agatha Christie

Test 7 — User Books
powershell


$headers = @{ "X-Dev-Token" = "local-dev-secret" }

Invoke-WebRequest -Uri "http://localhost:5000/api/ral/v01/user-books" `
    -Method GET -Headers $headers | Select-Object -ExpandProperty Content
Expected: JSON array containing Murder on the Orient Express with Rating: 5

Troubleshooting
