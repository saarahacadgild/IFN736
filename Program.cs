// ReadAlert Delivery 1 – Cobbled RAL module entry point.
// Follows Wayne's EDP reference pattern: single Program.cs, no middleware classes,
// no repository/service layers. SQL is called directly via static helpers.
using System.Data;
using System.IdentityModel.Tokens.Jwt;
using System.Text;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddCors(o => o.AddDefaultPolicy(p => p
    .WithOrigins(builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>()
        ?? ["http://localhost:5000", "http://localhost:5173"])
    .AllowAnyHeader().AllowAnyMethod()));

var app = builder.Build();
app.UseCors();
app.UseDefaultFiles();
app.UseStaticFiles();

var connectionString = app.Configuration.GetConnectionString("CobbledData")
    ?? throw new InvalidOperationException("ConnectionStrings:CobbledData is required.");

var standalone = app.Environment.IsDevelopment() &&
    string.Equals(app.Configuration["RalStandalone:Enabled"], "true", StringComparison.OrdinalIgnoreCase);

// ── Health / Readiness ────────────────────────────────────────────────────────
app.MapGet("/api/ral/v01/health", () =>
    Results.Ok(new { service = "ReadAlert", version = "1.0.0", status = "healthy" }));

app.MapGet("/api/ral/v01/readiness", async () =>
{
    try
    {
        await using var db = new SqlConnection(connectionString);
        await db.OpenAsync();
        var ready = Convert.ToInt32(await new SqlCommand(
            "SELECT IIF(OBJECT_ID(N'ral.ral_UserBooks_CRUD_JSON',N'P') IS NULL,0,1)", db)
            .ExecuteScalarAsync()) == 1;
        return ready ? Results.Ok(new { status = "ready" }) : Results.StatusCode(503);
    }
    catch { return Results.StatusCode(503); }
});

// ── Standalone dev harness ────────────────────────────────────────────────────
app.MapGet("/standalone", (IWebHostEnvironment env) =>
    standalone
        ? Results.File(Path.Combine(env.WebRootPath, "standalone.html"), "text/html")
        : Results.NotFound());

// Mints a real signed JWT for the standalone dev harness iframe.
app.MapPost("/standalone/context", () =>
{
    if (!standalone) return Results.NotFound();
    var key = app.Configuration["RalSecurity:SigningKeyBase64"];
    if (string.IsNullOrWhiteSpace(key))
        return Results.Problem("RalSecurity:SigningKeyBase64 is required.", statusCode: 503);

    var now = DateTime.UtcNow;
    var token = new JwtSecurityToken(
        app.Configuration["RalSecurity:Issuer"] ?? "ral-standalone",
        app.Configuration["RalSecurity:Audience"] ?? "ral-widget",
        [
            new("tenant_id", "F115B0A094467E7FCBA8DB16DF52242E"),
            new("member_id", "00000000000000000000000000000001"),
            new("permissions", "ral.reader.read"),
            new("permissions", "ral.reader.write"),
            new("permissions", "ral.books.read"),
            new("permissions", "ral.books.write"),
            new("permissions", "ral.user-books.read"),
            new("permissions", "ral.user-books.write"),
        ],
        now, now.AddHours(2),
        new SigningCredentials(
            new SymmetricSecurityKey(Convert.FromBase64String(key)),
            SecurityAlgorithms.HmacSha256));

    return Results.Ok(new { token = new JwtSecurityTokenHandler().WriteToken(token) });
});

// ── Reader Profile ────────────────────────────────────────────────────────────
app.MapGet("/api/ral/v01/reader-profile", async (HttpRequest request) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.reader.read")) return Forbidden("ral.reader.read");
    return Json(await ExecuteProcAsync(connectionString, scope, "ral.ral_ReaderProfile_CRUD_JSON", "SELECT", new { }));
});

app.MapPost("/api/ral/v01/reader-profile", async (HttpRequest request, ReaderProfileInput input) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.reader.write")) return Forbidden("ral.reader.write");
    return Json(await ExecuteProcAsync(connectionString, scope, "ral.ral_ReaderProfile_CRUD_JSON", "INSERT", new
    {
        ReaderDisplayName = input.ReaderDisplayName?.Trim(),
        PreferredGenres   = input.PreferredGenres?.Trim(),
        AlertOptIn        = input.AlertOptIn
    }), 201);
});

app.MapPut("/api/ral/v01/reader-profile", async (HttpRequest request, ReaderProfileInput input) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.reader.write")) return Forbidden("ral.reader.write");
    return Json(await ExecuteProcAsync(connectionString, scope, "ral.ral_ReaderProfile_CRUD_JSON", "UPDATE", new
    {
        ReaderDisplayName = input.ReaderDisplayName?.Trim(),
        PreferredGenres   = input.PreferredGenres?.Trim(),
        AlertOptIn        = input.AlertOptIn
    }));
});

// ── Authors ───────────────────────────────────────────────────────────────────
app.MapGet("/api/ral/v01/authors", async (HttpRequest request, string? searchText) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.books.read")) return Forbidden("ral.books.read");
    return Json(await ExecuteProcAsync(connectionString, scope, "ral.ral_Authors_CRUD_JSON", "SELECT", new
    {
        SearchText = searchText?.Trim()
    }));
});

app.MapPost("/api/ral/v01/authors", async (HttpRequest request, AuthorInput input) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.books.write")) return Forbidden("ral.books.write");
    if (string.IsNullOrWhiteSpace(input.AuthorName))
        return Results.BadRequest(new { code = "RAL_AUTHORNAME_REQUIRED" });
    return Json(await ExecuteProcAsync(connectionString, scope, "ral.ral_Authors_CRUD_JSON", "INSERT", new
    {
        AuthorName     = input.AuthorName.Trim(),
        AuthorComments = input.AuthorComments?.Trim()
    }), 201);
});

app.MapGet("/api/ral/v01/authors/{authorId}", async (HttpRequest request, string authorId) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.books.read")) return Forbidden("ral.books.read");
    if (!ValidId(authorId)) return Results.BadRequest(new { code = "RAL_AUTHOR_ID_INVALID" });
    return Json(await ExecuteProcAsync(connectionString, scope, "ral.ral_Authors_CRUD_JSON", "SELECT", new { AuthorID = authorId }));
});

app.MapPut("/api/ral/v01/authors/{authorId}", async (HttpRequest request, string authorId, AuthorInput input) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.books.write")) return Forbidden("ral.books.write");
    if (!ValidId(authorId)) return Results.BadRequest(new { code = "RAL_AUTHOR_ID_INVALID" });
    return Json(await ExecuteProcAsync(connectionString, scope, "ral.ral_Authors_CRUD_JSON", "UPDATE", new
    {
        AuthorID       = authorId,
        AuthorName     = input.AuthorName?.Trim(),
        AuthorComments = input.AuthorComments?.Trim()
    }));
});

app.MapDelete("/api/ral/v01/authors/{authorId}", async (HttpRequest request, string authorId) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.books.write")) return Forbidden("ral.books.write");
    if (!ValidId(authorId)) return Results.BadRequest(new { code = "RAL_AUTHOR_ID_INVALID" });
    return Json(await ExecuteProcAsync(connectionString, scope, "ral.ral_Authors_CRUD_JSON", "DELETE", new { AuthorID = authorId }));
});

// ── Books ─────────────────────────────────────────────────────────────────────
app.MapGet("/api/ral/v01/books", async (HttpRequest request, string? searchText) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.books.read")) return Forbidden("ral.books.read");
    return Json(await ExecuteProcAsync(connectionString, scope, "ral.ral_Books_CRUD_JSON", "SELECT", new
    {
        SearchText = searchText?.Trim()
    }));
});

app.MapPost("/api/ral/v01/books", async (HttpRequest request, BookInput input) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.books.write")) return Forbidden("ral.books.write");
    if (string.IsNullOrWhiteSpace(input.BookTitle))
        return Results.BadRequest(new { code = "RAL_BOOK_TITLE_REQUIRED" });
    return Json(await ExecuteProcAsync(connectionString, scope, "ral.ral_Books_CRUD_JSON", "INSERT", new
    {
        BookTitle = input.BookTitle.Trim(),
        ISBN13    = input.ISBN13?.Trim(),
        ISBN10    = input.ISBN10?.Trim()
    }), 201);
});

app.MapPost("/api/ral/v01/books/search", async (HttpRequest request, BookSearchInput input) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.books.read")) return Forbidden("ral.books.read");
    if (string.IsNullOrWhiteSpace(input.SearchText))
        return Results.BadRequest(new { code = "RAL_SEARCH_TEXT_REQUIRED" });
    return Json(await ExecutePayloadProcAsync(connectionString, scope, "ral.ral_SearchBooks_JSON", new
    {
        SearchType = input.SearchType ?? "TITLE_SEARCH",
        SearchText = input.SearchText.Trim(),
        Limit      = input.Limit ?? 25
    }));
});

app.MapPost("/api/ral/v01/books/scan", async (HttpRequest request, BookScanInput input) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.books.read")) return Forbidden("ral.books.read");
    if (string.IsNullOrWhiteSpace(input.ISBN13))
        return Results.BadRequest(new { code = "RAL_ISBN_REQUIRED" });
    return Json(await ExecutePayloadProcAsync(connectionString, scope, "ral.ral_ScanBook_JSON", new
    {
        ISBN13             = input.ISBN13.Trim(),
        ExternalSourceCode = input.ExternalSourceCode?.Trim()
    }));
});

app.MapGet("/api/ral/v01/books/{bookId}", async (HttpRequest request, string bookId) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.books.read")) return Forbidden("ral.books.read");
    if (!ValidId(bookId)) return Results.BadRequest(new { code = "RAL_BOOK_ID_INVALID" });
    return Json(await ExecuteProcAsync(connectionString, scope, "ral.ral_Books_CRUD_JSON", "SELECT", new { BookID = bookId }));
});

app.MapPut("/api/ral/v01/books/{bookId}", async (HttpRequest request, string bookId, BookInput input) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.books.write")) return Forbidden("ral.books.write");
    if (!ValidId(bookId)) return Results.BadRequest(new { code = "RAL_BOOK_ID_INVALID" });
    return Json(await ExecuteProcAsync(connectionString, scope, "ral.ral_Books_CRUD_JSON", "UPDATE", new
    {
        BookID    = bookId,
        BookTitle = input.BookTitle?.Trim(),
        ISBN13    = input.ISBN13?.Trim(),
        ISBN10    = input.ISBN10?.Trim()
    }));
});

// ── User Books ────────────────────────────────────────────────────────────────
app.MapGet("/api/ral/v01/user-books", async (HttpRequest request) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.user-books.read")) return Forbidden("ral.user-books.read");
    return Json(await ExecuteProcAsync(connectionString, scope, "ral.ral_UserBooks_CRUD_JSON", "SELECT", new { }));
});

app.MapPost("/api/ral/v01/user-books", async (HttpRequest request, UserBookInput input) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.user-books.write")) return Forbidden("ral.user-books.write");
    if (string.IsNullOrWhiteSpace(input.BookTitle))
        return Results.BadRequest(new { code = "RAL_BOOK_TITLE_REQUIRED" });
    return Json(await ExecutePayloadProcAsync(connectionString, scope, "ral.ral_AddBookRead_JSON", new
    {
        BookTitle         = input.BookTitle.Trim(),
        AuthorName        = input.AuthorName?.Trim(),
        ISBN13            = input.ISBN13?.Trim(),
        ReadingStatusCode = input.ReadingStatusCode ?? "READ",
        Rating            = input.Rating,
        ReviewText        = input.ReviewText?.Trim(),
        FinishedDate      = input.FinishedDate,
        SourceCode        = input.SourceCode ?? "MANUAL"
    }), 201);
});

app.MapPut("/api/ral/v01/user-books/{userBookId}", async (HttpRequest request, string userBookId, UserBookInput input) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.user-books.write")) return Forbidden("ral.user-books.write");
    if (!ValidId(userBookId)) return Results.BadRequest(new { code = "RAL_INPUT_INVALID" });
    return Json(await ExecutePayloadProcAsync(connectionString, scope, "ral.ral_UpdateBookRead_JSON", new
    {
        UserBookID        = userBookId,
        ReadingStatusCode = input.ReadingStatusCode,
        Rating            = input.Rating,
        ReviewText        = input.ReviewText?.Trim(),
        FinishedDate      = input.FinishedDate
    }));
});

app.MapDelete("/api/ral/v01/user-books/{userBookId}", async (HttpRequest request, string userBookId) =>
{
    var scope = await ReadScopeAsync(request, app.Configuration);
    if (scope is null) return Results.Unauthorized();
    if (!scope.Has("ral.user-books.write")) return Forbidden("ral.user-books.write");
    if (!ValidId(userBookId)) return Results.BadRequest(new { code = "RAL_INPUT_INVALID" });
    return Json(await ExecuteProcAsync(connectionString, scope, "ral.ral_UserBooks_CRUD_JSON", "DELETE", new { UserBookID = userBookId }));
});

app.Run();

// ── Static helpers ────────────────────────────────────────────────────────────

// Validates JWT from Authorization header and returns tenant/member scope.
// No ASP.NET auth middleware — follows Wayne's EDP inline validation pattern.
static async Task<RalScope?> ReadScopeAsync(HttpRequest request, IConfiguration configuration)
{
    try
    {
        var header = request.Headers.Authorization.ToString();
        if (!header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)) return null;
        var key = configuration["RalSecurity:SigningKeyBase64"];
        if (string.IsNullOrWhiteSpace(key)) return null;

        var result = await new JsonWebTokenHandler().ValidateTokenAsync(header[7..], new TokenValidationParameters
        {
            ValidateIssuer           = true,
            ValidIssuer              = configuration["RalSecurity:Issuer"],
            ValidateAudience         = true,
            ValidAudience            = configuration["RalSecurity:Audience"],
            ValidateLifetime         = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey         = new SymmetricSecurityKey(Convert.FromBase64String(key)),
            ClockSkew                = TimeSpan.FromSeconds(30)
        });

        if (!result.IsValid || result.ClaimsIdentity is null) return null;

        string? Claim(string name) =>
            result.ClaimsIdentity.Claims.FirstOrDefault(c => c.Type == name)?.Value;

        var tenantId = Claim("tenant_id");
        var memberId = Claim("member_id");
        if (!ValidId(tenantId) || !ValidId(memberId)) return null;

        return new RalScope(
            tenantId!,
            memberId!,
            result.ClaimsIdentity.Claims
                .Where(c => c.Type == "permissions")
                .Select(c => c.Value)
                .ToHashSet(StringComparer.OrdinalIgnoreCase));
    }
    catch { return null; }
}

// Executes a CRUD stored procedure (@Action + @Payload → @Result OUTPUT).
// Sets SESSION_CONTEXT TenantID/MemberID before every call — never from the request body.
static async Task<string> ExecuteProcAsync(
    string connectionString, RalScope scope,
    string procedureName, string action, object payload)
{
    await using var db = new SqlConnection(connectionString);
    await db.OpenAsync();

    foreach (var (key, value) in new[] { ("TenantID", scope.TenantId), ("MemberID", scope.MemberId) })
    {
        await using var ctx = new SqlCommand("EXEC sys.sp_set_session_context @key, @value", db);
        ctx.Parameters.AddWithValue("@key",   key);
        ctx.Parameters.AddWithValue("@value", value);
        await ctx.ExecuteNonQueryAsync();
    }

    await using var cmd = new SqlCommand(procedureName, db) { CommandType = CommandType.StoredProcedure };
    cmd.Parameters.AddWithValue("@Action", action);
    cmd.Parameters.Add("@Payload", SqlDbType.NVarChar, -1).Value = JsonSerializer.Serialize(payload);
    var result = cmd.Parameters.Add("@Result", SqlDbType.NVarChar, -1);
    result.Direction = ParameterDirection.Output;
    await cmd.ExecuteNonQueryAsync();
    return result.Value as string ?? "{}";
}

// Executes a payload-only stored procedure (@Payload → @Result OUTPUT).
// Used for SPs that don't take @Action (e.g. ral_SearchBooks_JSON, ral_ScanBook_JSON).
static async Task<string> ExecutePayloadProcAsync(
    string connectionString, RalScope scope,
    string procedureName, object payload)
{
    await using var db = new SqlConnection(connectionString);
    await db.OpenAsync();

    foreach (var (key, value) in new[] { ("TenantID", scope.TenantId), ("MemberID", scope.MemberId) })
    {
        await using var ctx = new SqlCommand("EXEC sys.sp_set_session_context @key, @value", db);
        ctx.Parameters.AddWithValue("@key",   key);
        ctx.Parameters.AddWithValue("@value", value);
        await ctx.ExecuteNonQueryAsync();
    }

    await using var cmd = new SqlCommand(procedureName, db) { CommandType = CommandType.StoredProcedure };
    cmd.Parameters.Add("@Payload", SqlDbType.NVarChar, -1).Value = JsonSerializer.Serialize(payload);
    var result = cmd.Parameters.Add("@Result", SqlDbType.NVarChar, -1);
    result.Direction = ParameterDirection.Output;
    await cmd.ExecuteNonQueryAsync();
    return result.Value as string ?? "{}";
}

static bool ValidId(string? value)     => value?.Length == 32;
static IResult Forbidden(string perm)  => Results.Json(new { code = "RAL_PERMISSION_REQUIRED", requiredPermission = perm }, statusCode: 403);
static IResult Json(string body, int statusCode = 200) =>
    Results.Text(body, "application/json", Encoding.UTF8, statusCode);

// ── Records ───────────────────────────────────────────────────────────────────
record RalScope(string TenantId, string MemberId, HashSet<string> Permissions)
{
    public bool Has(string permission) => Permissions.Contains(permission);
}

record ReaderProfileInput(string? ReaderDisplayName, string? PreferredGenres, bool? AlertOptIn);
record AuthorInput(string? AuthorName, string? AuthorComments);
record BookInput(string? BookTitle, string? ISBN13, string? ISBN10);
record BookSearchInput(string? SearchText, string? SearchType, int? Limit);
record BookScanInput(string? ISBN13, string? ExternalSourceCode);
record UserBookInput(
    string? BookTitle, string? AuthorName, string? ISBN13,
    string? ReadingStatusCode, int? Rating, string? ReviewText,
    string? FinishedDate, string? SourceCode);
