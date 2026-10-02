namespace ReadAlert.Services;

public interface IReadAlertService
{
    Task<string> CrudAsync(string procedureName, string action, string payloadJson, CancellationToken ct);
    Task<string> ExecuteJsonAsync(string procedureName, string payloadJson, CancellationToken ct);
}
