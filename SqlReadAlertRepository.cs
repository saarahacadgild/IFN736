using System.Data;
using Microsoft.Data.SqlClient;

namespace ReadAlert.Repositories;

public sealed class SqlReadAlertRepository : IReadAlertRepository
{
    private readonly string _connectionString;
    private readonly IHttpContextAccessor _httpContextAccessor;

    public SqlReadAlertRepository(IConfiguration configuration, IHttpContextAccessor httpContextAccessor)
    {
        _connectionString = configuration.GetConnectionString("CobbledData") ?? throw new InvalidOperationException("Missing CobbledData connection string.");
        _httpContextAccessor = httpContextAccessor;
    }

    public Task<string> ExecuteCrudAsync(string procedureName, string action, string payloadJson, CancellationToken ct)
        => ExecuteAsync(procedureName, action, payloadJson, isCrud: true, ct);

    public Task<string> ExecuteJsonAsync(string procedureName, string payloadJson, CancellationToken ct)
        => ExecuteAsync(procedureName, null, payloadJson, isCrud: false, ct);

    private async Task<string> ExecuteAsync(string procedureName, string? action, string payloadJson, bool isCrud, CancellationToken ct)
    {
        await using var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);
        await SetSessionContextAsync(conn, ct);

        await using var cmd = new SqlCommand($"ral.{procedureName}", conn) { CommandType = CommandType.StoredProcedure };
        if (isCrud) cmd.Parameters.Add(new SqlParameter("@Action", SqlDbType.NVarChar, 20) { Value = action ?? "SELECT" });
        cmd.Parameters.Add(new SqlParameter("@Payload", SqlDbType.NVarChar, -1) { Value = payloadJson });
        var result = new SqlParameter("@Result", SqlDbType.NVarChar, -1) { Direction = ParameterDirection.Output };
        cmd.Parameters.Add(result);
        await cmd.ExecuteNonQueryAsync(ct);
        return result.Value as string ?? "{}";
    }

    private async Task SetSessionContextAsync(SqlConnection conn, CancellationToken ct)
    {
        var user = _httpContextAccessor.HttpContext?.User;
        var tenantId = user?.FindFirst("TenantID")?.Value;
        var memberId = user?.FindFirst("MemberID")?.Value;
        if (string.IsNullOrWhiteSpace(tenantId)) throw new UnauthorizedAccessException("TenantID claim is required.");
        await using var cmd = new SqlCommand("EXEC sys.sp_set_session_context @key=N'TenantID', @value=@tenantId; EXEC sys.sp_set_session_context @key=N'MemberID', @value=@memberId;", conn);
        cmd.Parameters.AddWithValue("@tenantId", tenantId);
        cmd.Parameters.AddWithValue("@memberId", (object?)memberId ?? DBNull.Value);
        await cmd.ExecuteNonQueryAsync(ct);
    }
}

