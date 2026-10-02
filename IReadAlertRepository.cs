namespace ReadAlert.Repositories;

public interface IReadAlertRepository
{
    Task<string> ExecuteCrudAsync(string procedureName, string action, string payloadJson, CancellationToken ct);
    Task<string> ExecuteJsonAsync(string procedureName, string payloadJson, CancellationToken ct);
}
