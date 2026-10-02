using ReadAlert.Repositories;

namespace ReadAlert.Services;

public sealed class ReadAlertService : IReadAlertService
{
    private readonly IReadAlertRepository _repository;
    public ReadAlertService(IReadAlertRepository repository) => _repository = repository;
    public Task<string> CrudAsync(string procedureName, string action, string payloadJson, CancellationToken ct) => _repository.ExecuteCrudAsync(procedureName, action, payloadJson, ct);
    public Task<string> ExecuteJsonAsync(string procedureName, string payloadJson, CancellationToken ct) => _repository.ExecuteJsonAsync(procedureName, payloadJson, ct);
}
