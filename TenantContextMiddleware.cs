using System.Security.Claims;
using Microsoft.Extensions.Configuration;

namespace ReadAlert.Middleware;

public sealed class TenantContextMiddleware
{
    private readonly RequestDelegate   _next;
    private readonly IConfiguration    _config;

    public TenantContextMiddleware(RequestDelegate next, IConfiguration config)
    {
        _next   = next;
        _config = config;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // --- Dev token bypass (local development only) ---
        var devEnabled = string.Equals(
            _config["DevToken:Enabled"], "true", StringComparison.OrdinalIgnoreCase);

        if (devEnabled &&
            context.Request.Headers.TryGetValue("X-Dev-Token", out var incoming) &&
            incoming == _config["DevToken:Token"])
        {
            var tenantId = _config["DevToken:TenantID"] ?? string.Empty;
            var memberId = _config["DevToken:MemberID"] ?? string.Empty;

            var claims = new[]
            {
                new Claim("TenantID", tenantId),
                new Claim("MemberID", memberId),
            };
            var identity  = new ClaimsIdentity(claims, "DevToken");
            context.User  = new ClaimsPrincipal(identity);
            await _next(context);
            return;
        }

        // --- Normal JWT path: TenantID claim must be present ---
        if (context.User.Identity?.IsAuthenticated == true &&
            context.User.FindFirst("TenantID") is null)
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsync("TenantID claim is required.");
            return;
        }

        await _next(context);
    }
}
