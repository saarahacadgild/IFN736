// ReadAlert Delivery 1 – Cobbled module entry point.
// Follows Wayne's EDP reference: pure Minimal API, no MVC Controllers.
// Pipeline: CORS → StaticFiles → DevToken bypass → TenantContextMiddleware → JWT → endpoint → Service → Repository → ral. SPs.
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using ReadAlert.Middleware;
using ReadAlert.Repositories;
using ReadAlert.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<IReadAlertRepository, SqlReadAlertRepository>();
builder.Services.AddScoped<IReadAlertService, ReadAlertService>();

var devTokenEnabled = builder.Environment.IsDevelopment() &&
    string.Equals(builder.Configuration["DevToken:Enabled"], "true", StringComparison.OrdinalIgnoreCase);

// In Development use the local signing key; in Production use the real identity provider.
var standaloneSigningKeyBase64 = builder.Configuration["StandaloneJwt:SigningKeyBase64"];
var useStandaloneJwt = builder.Environment.IsDevelopment() && !string.IsNullOrWhiteSpace(standaloneSigningKeyBase64);

builder.Services.AddAuthentication("Bearer")
    .AddJwtBearer("Bearer", options =>
    {
        if (useStandaloneJwt)
        {
            var keyBytes = Convert.FromBase64String(standaloneSigningKeyBase64!);
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKey         = new SymmetricSecurityKey(keyBytes),
                ValidateIssuer           = true,
                ValidIssuer              = "ral-standalone",
                ValidateAudience         = true,
                ValidAudience            = "ral-widget",
                ValidateLifetime         = true,
                ClockSkew                = TimeSpan.FromSeconds(30)
            };
        }
        else
        {
            options.Authority            = builder.Configuration["Jwt:Authority"];
            options.Audience             = builder.Configuration["Jwt:Audience"];
            options.RequireHttpsMetadata = true;
        }
    });
builder.Services.AddAuthorization();

builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
    p.WithOrigins("http://localhost:5000", "http://localhost:5173")
     .AllowAnyHeader().AllowAnyMethod()));

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title       = "ReadAlert API",
        Version     = "v01",
        Description = "Cobbled RAL module — Delivery 1"
    });
    c.AddSecurityDefinition("DevToken", new OpenApiSecurityScheme
    {
        Name        = "X-Dev-Token",
        Type        = SecuritySchemeType.ApiKey,
        In          = ParameterLocation.Header,
        Description = "Local dev bypass header. Value: local-dev-secret"
    });
    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "DevToken" }
            },
            Array.Empty<string>()
        }
    });
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name         = "Authorization",
        Type         = SecuritySchemeType.Http,
        Scheme       = "bearer",
        BearerFormat = "JWT",
        Description  = "Production JWT. Enter token without 'Bearer ' prefix."
    });
    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
            },
            Array.Empty<string>()
        }
    });
});

var app = builder.Build();

app.UseCors();
app.UseStaticFiles();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "ReadAlert API v01");
        c.RoutePrefix = "swagger";
    });
}

// Dev-token header bypass — must run BEFORE UseAuthentication
if (devTokenEnabled)
{
    app.Use(async (context, next) =>
    {
        var token  = app.Configuration["DevToken:Token"];
        var header = context.Request.Headers["X-Dev-Token"].FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(header) && header == token)
        {
            var tenantId = app.Configuration["DevToken:TenantID"] ?? "F115B0A094467E7FCBA8DB16DF52242E";
            var memberId = app.Configuration["DevToken:MemberID"] ?? "00000000000000000000000000000001";
            var claims   = new[] { new Claim("TenantID", tenantId), new Claim("MemberID", memberId) };
            var identity = new ClaimsIdentity(claims, "DevToken");
            context.User = new ClaimsPrincipal(identity);
        }
        await next();
    });
}

app.UseMiddleware<TenantContextMiddleware>();
app.UseAuthentication();
app.UseAuthorization();

// ── Health / Readiness ────────────────────────────────────────────────────────
app.MapGet("/api/ral/v01/health",    () => Results.Ok(new { service = "ReadAlert", version = "1.0.0", status = "healthy" }));
app.MapGet("/api/ral/v01/readiness", () => Results.Ok(new { service = "ReadAlert", version = "1.0.0", status = "ready"   }));

// ── Standalone dev harness ────────────────────────────────────────────────────

// Serves wwwroot/standalone.html
app.MapGet("/standalone", (IWebHostEnvironment env) =>
    devTokenEnabled
        ? Results.File(Path.Combine(env.WebRootPath, "standalone.html"), "text/html")
        : Results.NotFound());

// Serves wwwroot/ral-widget/index.html inside the iframe
app.MapGet("/api/ral/v01/widget", (IWebHostEnvironment env) =>
    Results.File(Path.Combine(env.WebRootPath, "ral-widget", "index.html"), "text/html; charset=utf-8"));

// Mints a REAL signed JWT — three dot-separated parts — for the widget iframe.
// The widget sends it as: Authorization: Bearer <token>
app.MapPost("/standalone/context", () =>
{
    if (!devTokenEnabled) return Results.NotFound();

    var tenantId = app.Configuration["DevToken:TenantID"] ?? "F115B0A094467E7FCBA8DB16DF52242E";
    var memberId = app.Configuration["DevToken:MemberID"] ?? "00000000000000000000000000000001";

    // Same key used in StandaloneJwt:SigningKeyBase64 / TokenValidationParameters above
    const string signingKey = "cmVhZGFsZXJ0LWRldi1zaWduaW5nLWtleS0yMDI2LWxvY2Fs";
    var keyBytes    = Convert.FromBase64String(signingKey);
    var securityKey = new SymmetricSecurityKey(keyBytes);
    var credentials = new SigningCredentials(securityKey, SecurityAlgorithms.HmacSha256);

    var now = DateTime.UtcNow;
    var jwtToken = new JwtSecurityToken(
        issuer:   "ral-standalone",
        audience: "ral-widget",
        claims: new[]
        {
            new Claim("TenantID",    tenantId),
            new Claim("MemberID",    memberId),
            new Claim("permissions", "ral.reader.read"),
            new Claim("permissions", "ral.reader.write"),
            new Claim("permissions", "ral.books.read"),
            new Claim("permissions", "ral.books.write"),
        },
        notBefore: now,
        expires:   now.AddHours(2),
        signingCredentials: credentials);

    var token = new JwtSecurityTokenHandler().WriteToken(jwtToken);
    return Results.Ok(new { token });
});

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
