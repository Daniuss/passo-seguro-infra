// API de teste do Passo Seguro.
// Serve so para desenvolver e testar a infraestrutura Linux (Operating Systems).
// Na entrega final, ela e substituida pela API oficial do grupo.

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// Dados de exemplo em memoria (sem banco de dados)
var ocorrencias = new List<Ocorrencia>
{
    new(1, "Calcada danificada", "Av. Paulista, 1000", "Aberta"),
    new(2, "Rampa de acesso obstruida", "Rua Augusta, 500", "Em analise"),
    new(3, "Semaforo sem sinal sonoro", "Av. Brigadeiro Faria Lima, 2000", "Resolvida")
};

app.MapGet("/", () => Results.Text(
    "Passo Seguro API (teste) - rotas: /health, /api/ocorrencias"));

app.MapGet("/health", () => Results.Ok(new
{
    status = "ok",
    servidor = Environment.MachineName,
    horario = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")
}));

app.MapGet("/api/ocorrencias", () => Results.Ok(ocorrencias));

app.MapGet("/api/ocorrencias/{id:int}", (int id) =>
    ocorrencias.FirstOrDefault(o => o.Id == id) is { } o
        ? Results.Ok(o)
        : Results.NotFound(new { erro = "Ocorrencia nao encontrada" }));

app.Run();

record Ocorrencia(int Id, string Categoria, string Local, string Status);
