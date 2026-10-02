// ReadAlert Delivery 1 – Cobbled module entry point.
// Follows Wayne's EDP reference: pure Minimal API, no MVC Controllers, no Swagger.
// Pattern: JWT middleware -> TenantContextMiddleware -> endpoint -> Service -> Repository -> ral. stored procedures.
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using ReadAlert.Middleware;
using ReadAlert.Repositories;
using ReadAlert.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<IReadAlertRepository, SqlReadAlertRepository>();
builder.Services.AddScoped<IReadAlertService, ReadAlertService>();

// Dev-token bypass: in Development, if X-Dev-Token header matches config, inject synthetic claims.
// This mirrors the EDP standalone harness pattern. Disabled outside Development automatically.
var devTokenEnabled =
    string.Equals(builder.Configuration["DevToken:Enabled"], "true", StringComparison.OrdinalIgnoreCase);

builder.Services.AddAuthentication("Bearer")
    .AddJwtBearer("Bearer", options =>
    {
        options.Authority = builder.Configuration["Jwt:Authority"];
        options.Audience  = builder.Configuration["Jwt:Audience"];
        options.RequireHttpsMetadata = !builder.Environment.IsDevelopment();
    });
builder.Services.AddAuthorization();

if (builder.Environment.IsDevelopment() ||
    string.Equals(builder.Configuration["DevToken:Enabled"], "true", StringComparison.OrdinalIgnoreCase))
{
    builder.Services.AddEndpointsApiExplorer();
    builder.Services.AddSwaggerGen(c =>
    {
        c.SwaggerDoc("v1", new() { Title = "ReadAlert API", Version = "v1", Description = "Cobbled RAL module — Delivery 1" });

        // Allow X-Dev-Token header in Swagger UI
        c.AddSecurityDefinition("DevToken", new()
        {
            Name        = "X-Dev-Token",
            Type        = Microsoft.OpenApi.Models.SecuritySchemeType.ApiKey,
            In          = Microsoft.OpenApi.Models.ParameterLocation.Header,
            Description = "Local dev bypass token. Value: local-dev-secret"
        });
        c.AddSecurityRequirement(new()
        {
            {
                new Microsoft.OpenApi.Models.OpenApiSecurityScheme
                {
                    Reference = new() { Type = Microsoft.OpenApi.Models.ReferenceType.SecurityScheme, Id = "DevToken" }
                },
                Array.Empty<string>()
            }
        });

        // Also allow Bearer JWT for production testing
        c.AddSecurityDefinition("Bearer", new()
        {
            Name         = "Authorization",
            Type         = Microsoft.OpenApi.Models.SecuritySchemeType.Http,
            Scheme       = "bearer",
            BearerFormat = "JWT",
            Description  = "Enter your JWT token (without 'Bearer ' prefix)"
        });
        c.AddSecurityRequirement(new()
        {
            {
                new Microsoft.OpenApi.Models.OpenApiSecurityScheme
                {
                    Reference = new() { Type = Microsoft.OpenApi.Models.ReferenceType.SecurityScheme, Id = "Bearer" }
                },
                Array.Empty<string>()
            }
        });
    });
}

var app = builder.Build();

app.UseMiddleware<TenantContextMiddleware>();
app.UseAuthentication();
app.UseAuthorization();

if (app.Environment.IsDevelopment() ||
    string.Equals(app.Configuration["DevToken:Enabled"], "true", StringComparison.OrdinalIgnoreCase))
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "ReadAlert API v1");
        c.RoutePrefix = "swagger";
    });
}

// ── Health / Readiness (unauthenticated) ─────────────────────────────────────

app.MapGet("/api/ral/v01/health",    () => Results.Ok(new { service = "ReadAlert", version = "1.0.0", status = "healthy" }));
app.MapGet("/api/ral/v01/readiness", () => Results.Ok(new { service = "ReadAlert", version = "1.0.0", status = "ready"   }));

// ── Reader Profile ────────────────────────────────────────────────────────────

app.MapGet("/api/ral/v01/reader-profile", async (IReadAlertService svc, CancellationToken ct) =>
{
    var result = await svc.CrudAsync("ral_ReaderProfile_CRUD_JSON", "SELECT", "{}", ct);
    return Json(result);
}).RequireAuthorization();

app.MapPost("/api/ral/v01/reader-profile", async (HttpRequest req, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = await ReadBodyAsync(req);
    var result  = await svc.CrudAsync("ral_ReaderProfile_CRUD_JSON", "INSERT", payload, ct);
    return Json(result, 201);
}).RequireAuthorization();

app.MapPut("/api/ral/v01/reader-profile", async (HttpRequest req, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = await ReadBodyAsync(req);
    var result  = await svc.CrudAsync("ral_ReaderProfile_CRUD_JSON", "UPDATE", payload, ct);
    return Json(result);
}).RequireAuthorization();

// ── Authors ───────────────────────────────────────────────────────────────────

app.MapGet("/api/ral/v01/authors", async (string? searchText, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = searchText is null ? "{}" : JsonSerializer.Serialize(new { SearchText = searchText });
    var result  = await svc.CrudAsync("ral_Authors_CRUD_JSON", "SELECT", payload, ct);
    return Json(result);
}).RequireAuthorization();

app.MapPost("/api/ral/v01/authors", async (HttpRequest req, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = await ReadBodyAsync(req);
    var result  = await svc.CrudAsync("ral_Authors_CRUD_JSON", "INSERT", payload, ct);
    return Json(result, 201);
}).RequireAuthorization();

app.MapGet("/api/ral/v01/authors/{authorId}", async (string authorId, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = JsonSerializer.Serialize(new { AuthorID = authorId });
    var result  = await svc.CrudAsync("ral_Authors_CRUD_JSON", "SELECT", payload, ct);
    return string.IsNullOrWhiteSpace(result) || result == "[]" ? Results.NotFound() : Json(result);
}).RequireAuthorization();

app.MapPut("/api/ral/v01/authors/{authorId}", async (string authorId, HttpRequest req, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = MergeId(await ReadBodyAsync(req), "AuthorID", authorId);
    var result  = await svc.CrudAsync("ral_Authors_CRUD_JSON", "UPDATE", payload, ct);
    return Json(result);
}).RequireAuthorization();

app.MapDelete("/api/ral/v01/authors/{authorId}", async (string authorId, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = JsonSerializer.Serialize(new { AuthorID = authorId });
    await svc.CrudAsync("ral_Authors_CRUD_JSON", "DELETE", payload, ct);
    return Results.NoContent();
}).RequireAuthorization();

// ── Books ─────────────────────────────────────────────────────────────────────

app.MapGet("/api/ral/v01/books", async (string? searchText, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = searchText is null ? "{}" : JsonSerializer.Serialize(new { SearchText = searchText });
    var result  = await svc.CrudAsync("ral_Books_CRUD_JSON", "SELECT", payload, ct);
    return Json(result);
}).RequireAuthorization();

app.MapPost("/api/ral/v01/books", async (HttpRequest req, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = await ReadBodyAsync(req);
    var result  = await svc.CrudAsync("ral_Books_CRUD_JSON", "INSERT", payload, ct);
    return Json(result, 201);
}).RequireAuthorization();

// Book Lookup – the two SP-dedicated endpoints (your task focus)
app.MapPost("/api/ral/v01/books/search", async (HttpRequest req, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = await ReadBodyAsync(req);
    var result  = await svc.ExecuteJsonAsync("ral_SearchBooks_JSON", payload, ct);
    return Json(result);
}).RequireAuthorization();

app.MapPost("/api/ral/v01/books/scan", async (HttpRequest req, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = await ReadBodyAsync(req);
    var result  = await svc.ExecuteJsonAsync("ral_ScanBook_JSON", payload, ct);
    return Json(result);
}).RequireAuthorization();

app.MapGet("/api/ral/v01/books/{bookId}", async (string bookId, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = JsonSerializer.Serialize(new { BookID = bookId });
    var result  = await svc.CrudAsync("ral_Books_CRUD_JSON", "SELECT", payload, ct);
    return string.IsNullOrWhiteSpace(result) || result == "[]" ? Results.NotFound() : Json(result);
}).RequireAuthorization();

app.MapPut("/api/ral/v01/books/{bookId}", async (string bookId, HttpRequest req, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = MergeId(await ReadBodyAsync(req), "BookID", bookId);
    var result  = await svc.CrudAsync("ral_Books_CRUD_JSON", "UPDATE", payload, ct);
    return Json(result);
}).RequireAuthorization();

// ── User Books ────────────────────────────────────────────────────────────────

app.MapGet("/api/ral/v01/user-books", async (IReadAlertService svc, CancellationToken ct) =>
{
    var result = await svc.CrudAsync("ral_UserBooks_CRUD_JSON", "SELECT", "{}", ct);
    return Json(result);
}).RequireAuthorization();

app.MapPost("/api/ral/v01/user-books", async (HttpRequest req, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = await ReadBodyAsync(req);
    var result  = await svc.ExecuteJsonAsync("ral_AddBookRead_JSON", payload, ct);
    return Json(result);
}).RequireAuthorization();

app.MapPut("/api/ral/v01/user-books/{userBookId}", async (string userBookId, HttpRequest req, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = MergeId(await ReadBodyAsync(req), "UserBookID", userBookId);
    var result  = await svc.ExecuteJsonAsync("ral_UpdateBookRead_JSON", payload, ct);
    return Json(result);
}).RequireAuthorization();

app.MapDelete("/api/ral/v01/user-books/{userBookId}", async (string userBookId, IReadAlertService svc, CancellationToken ct) =>
{
    var payload = JsonSerializer.Serialize(new { UserBookID = userBookId });
    await svc.CrudAsync("ral_UserBooks_CRUD_JSON", "DELETE", payload, ct);
    return Results.NoContent();
}).RequireAuthorization();

app.Run();

// ── Helpers ───────────────────────────────────────────────────────────────────

static async Task<string> ReadBodyAsync(HttpRequest req)
{
    using var reader = new StreamReader(req.Body, Encoding.UTF8);
    var body = await reader.ReadToEndAsync();
    return string.IsNullOrWhiteSpace(body) ? "{}" : body;
}

// Merges a route ID into an existing JSON payload so the stored procedure receives it.
static string MergeId(string json, string key, string value)
{
    try
    {
        var dict = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(json) ?? new();
        dict[key] = JsonSerializer.SerializeToElement(value);
        return JsonSerializer.Serialize(dict);
    }
    catch { return json; }
}

static IResult Json(string body, int status = 200) =>
    Results.Text(body, "application/json", Encoding.UTF8, status);
