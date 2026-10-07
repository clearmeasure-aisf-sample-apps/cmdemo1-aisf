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

app.Run();
