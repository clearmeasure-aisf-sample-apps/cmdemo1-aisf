using System.Text;
using AISoftwareFactory3_21.Hosting;

var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    Args = args,
    // appsettings.json and the Prompts folder sit next to the executable, wherever it is started from.
    ContentRootPath = AppContext.BaseDirectory,
});

// This system's factory: the GitHub board of cmdemo1-workorders, worked by Cursor cloud agents.
builder.AddAisfFactory(factory => factory
    .UseGitHubWorkTracking()
    .AddCursorWorker());

var app = builder.Build();

app.UseAisfFactory();

// GET /_build: what this container was built from (version, commit, build run, the Aisf.* packages it holds).
// The image build writes build-facts.json next to the executable (scripts/write-build-facts.sh); a build
// without the file answers 404. The system's dashboard reads it from another origin, so it is open like
// /health: no sign-in (the factory protects every endpoint that does not opt out), any origin, five minutes
// of cache.
var buildFactsFile = Path.Combine(AppContext.BaseDirectory, "build-facts.json");
var buildFacts = File.Exists(buildFactsFile) ? File.ReadAllText(buildFactsFile) : null;
app.MapGet("/_build", (HttpContext http) =>
{
    http.Response.Headers.AccessControlAllowOrigin = "*";
    http.Response.Headers.CacheControl = "public, max-age=300";
    return buildFacts is null ? Results.NotFound() : Results.Text(buildFacts, "application/json", Encoding.UTF8);
}).AllowAnonymous();

app.Run();
