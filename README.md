ReadAlert – Log/Scan (Book Lookup) User Stories

Module: Log/Scan (Book Lookup)
Student: Saarah Fariheen Sayeed (12145521)
Unit: IFN736 – Industry Project (Phase 2)
Project: ReadAlert – Penta Intelligence (Group 18)

---

Overview

The Log/Scan module enables members to search for books by title, author, or ISBN, scan a physical book by its ISBN-13 barcode, and add or manage their personal reading records. All data operations are scoped by TenantID and MemberID extracted from a verified JWT. Every search and scan action is automatically logged to the book lookup log for audit and analytics purposes.

---

User Stories

US-RAL-01 — Authenticate Before Using the Widget

As a member using the ReadAlert widget,
I want to click a "Get Token" button to obtain a secure session token,
so that my book searches, scans, and reading records are linked to my member identity and tenant.

Acceptance Criteria:
A "Get Token" button is visible on the widget header.
Clicking the button calls POST /standalone/context and receives a signed JWT.
The token status changes to "Token acquired" after a successful response.
The My Books reading list loads automatically once a token is acquired.
All subsequent API calls attach the token as a Bearer header in the Authorization field.
If no token has been acquired, API calls are not attempted.

---

US-RAL-02 — Search Books by Title

As a member,
I want to search for books by entering a title keyword,
so that I can find books already in the catalogue before adding a reading record.

Acceptance Criteria:
The Search / Scan tab displays a search form with a Search Type selector and a Search Text input.
Selecting "Title" and submitting calls POST /api/ral/v01/books/search with SearchType = TITLE_SEARCH.
Results display in a table showing Title, Author, and ISBN-13.
A result count (e.g. "3 result(s)") is shown above the table.
If no books match, the message "No matches found." is displayed.
An empty search text field prevents form submission (required validation).
The search is logged to ral_BookLookupLog with LookupTypeCode = TITLE_SEARCH and a ResultStatusCode of MATCHED, MULTIPLE_MATCHES, or NOT_MATCHED.

---

US-RAL-03 — Search Books by Author

As a member,
I want to search for books by entering an author's name,
so that I can browse all books by a particular author in the catalogue.

Acceptance Criteria:
Selecting "Author" from the Search Type dropdown and submitting calls POST /api/ral/v01/books/search with SearchType = AUTHOR_SEARCH.
The stored procedure matches books where the linked author name contains the search text.
Results display Title, Author, and ISBN-13 columns.
The lookup is logged to ral_BookLookupLog with LookupTypeCode = AUTHOR_SEARCH.

---

US-RAL-04 — Search Books by ISBN

As a member,
I want to search for a specific book by entering its ISBN-10 or ISBN-13,
so that I can quickly identify an exact edition.

Acceptance Criteria:
Selecting "ISBN" from the Search Type dropdown and submitting calls POST /api/ral/v01/books/search with SearchType = ISBN_SEARCH.
The stored procedure matches books where ISBN10 or ISBN13 equals the entered value exactly.
A single exact match returns ResultStatusCode = MATCHED.
No match returns ResultStatusCode = NOT_MATCHED and shows "No matches found."
The lookup is logged to ral_BookLookupLog with the ISBN stored in the ISBN10 or ISBN13 column based on length.

---

US-RAL-05 — Scan a Book by ISBN-13

As a member,
I want to enter an ISBN-13 number into a Scan ISBN field,
so that I can quickly look up a physical book without typing its full title.

Acceptance Criteria:
The Search / Scan panel displays a separate Scan ISBN form below the search form.
Submitting calls POST /api/ral/v01/books/scan with the ISBN13 value.
The API delegates to ral.ral_ScanBook_JSON, which routes to ral_SearchBooks_JSON with SearchType = ISBN_SCAN.
Results display in the same search results table (Title, Author, ISBN-13).
The scan is logged to ral_BookLookupLog with LookupTypeCode = ISBN_SCAN.
A matched result shows one row; no match shows "No matches found."

---

US-RAL-06 — Every Search and Scan is Automatically Logged

As a system,
I want to record every book search and scan to the lookup log,
so that the platform has an audit trail and usage analytics for book discovery.

Acceptance Criteria:
Every call to POST /api/ral/v01/books/search or POST /api/ral/v01/books/scan inserts a row into ral_BookLookupLog via the stored procedure.
The log row captures: TenantID, MemberID, LookupTypeCode, SearchText, ISBN10/ISBN13 (where applicable), MatchedBookID (when exactly one match is found), ResultStatusCode, and CreatedUtc.
ResultStatusCode is one of: MATCHED (one result), MULTIPLE_MATCHES (more than one), NOT_MATCHED (zero).
MatchedBookID is only populated when ResultStatusCode = MATCHED.
Logging is handled entirely within the stored procedure — no application-side logging code is required.

---

US-RAL-07 — View My Reading List

As a member,
I want to view all books I have logged as read, reading, or want-to-read,
so that I can track my reading history at a glance.

Acceptance Criteria:
The My Books tab calls GET /api/ral/v01/user-books on load.
The reading list displays a table with columns: Title, Status, Rating, and Finished date.
Records are returned for the authenticated member's TenantID and MemberID only.
If no records exist, the message "No books yet — add one!" is shown.
The list is re-loaded automatically after a new book is added.

---

US-RAL-08 — Add a Book to My Reading List

As a member,
I want to manually add a book to my reading list by entering its title, author, ISBN, and reading details,
so that I can log books I have read even if they are not yet in the catalogue.

Acceptance Criteria:
Clicking "+ Add Book" from the My Books tab shows an inline form with fields: Book Title (required), Author Name, ISBN-13, Reading Status, Rating (1–5), and Review.
Submitting calls POST /api/ral/v01/user-books.
The API calls ral.ral_AddBookRead_JSON, which auto-creates the book record in ral_Books if no matching ISBN or BookID is found.
If the author name is provided and does not exist, a new record is created in ral_Authors and linked in ral_BookAuthors.
If the book already exists in the member's reading list, the existing record is updated (upsert behaviour).
On success, the form is dismissed and the reading list reloads.
If Book Title is left empty, the form cannot be submitted.

---

US-RAL-09 — Update a Reading Record

As a member,
I want to update the status, rating, review, or finished date of a book I have already logged,
so that my reading record stays accurate as I progress through a book.

Acceptance Criteria:
PUT /api/ral/v01/user-books/{userBookId} accepts ReadingStatusCode, Rating, ReviewText, and FinishedDate.
The API calls ral.ral_UpdateBookRead_JSON, which delegates to ral_UserBooks_CRUD_JSON with Action = UPDATE.
Only the fields supplied in the request payload are updated; omitted fields retain their existing values.
If the UserBookID does not belong to the authenticated member, the update fails with an appropriate error.
The reading list reloads after a successful update.

---

US-RAL-10 — Remove a Book from My Reading List

As a member,
I want to remove a book from my reading list,
so that I can correct accidental entries or clean up my history.

Acceptance Criteria:
DELETE /api/ral/v01/user-books/{userBookId} is available and requires a valid JWT.
The API calls ral.ral_UserBooks_CRUD_JSON with Action = DELETE.
The record is soft-deleted (IsActive = 0) rather than permanently removed.
If the UserBookID is not found or does not belong to the authenticated member, a 404-equivalent error is returned.
The reading list reloads after successful deletion.

---

US-RAL-11 — Secure All Endpoints with JWT Authentication

As a system,
I want to reject any request that does not carry a valid signed JWT,
so that no member can read or modify another member's reading records.

Acceptance Criteria:
Every endpoint (except /api/ral/v01/health, /api/ral/v01/readiness, and /standalone/*) validates the Authorization: Bearer header before processing.
Validation is performed inline using JsonWebTokenHandler (no ASP.NET auth middleware).
The token is verified against the configured Issuer, Audience, and symmetric signing key (RalSecurity:SigningKeyBase64).
An expired, tampered, or missing token returns HTTP 401 Unauthorized.
TenantID and MemberID are extracted exclusively from the verified JWT claims and passed to SESSION_CONTEXT — they are never accepted from the request body or query string.

---

US-RAL-12 — Check Service Health and Readiness

As a developer or operator,
I want to call health and readiness endpoints,
so that I can confirm the ReadAlert API is running and its database connection is functional.

Acceptance Criteria:
GET /api/ral/v01/health returns HTTP 200 with { service: "ReadAlert", version: "1.0.0", status: "healthy" } without requiring a token.
GET /api/ral/v01/readiness opens a SQL connection and checks that ral.ral_UserBooks_CRUD_JSON exists.
If the stored procedure is present and the connection succeeds, the endpoint returns HTTP 200 with { status: "ready" }.
If the database is unreachable or the stored procedure is missing, the endpoint returns HTTP 503.
Both endpoints do not require authentication.

---

Document generated from codebase review of ReadAlert module (RAL) — Saarah Fariheen Sayeed (12145521), IFN736 Penta Intelligence Group 18.

