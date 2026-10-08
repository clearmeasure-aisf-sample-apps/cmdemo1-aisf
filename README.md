# cmdemo1-aisf

The AI Software Factory for the cmdemo1 system: one always-on container that watches the GitHub
board of `cmdemo1-workorders` (project 679) and works it with Cursor cloud agents.

It is composed from the `Aisf.*` NuGet packages published by `ClearMeasureLabs/AISoftwareFactory`.
The packages are licensed under the PolyForm Internal Use License 1.0.0 (Clear Measure, Inc.): free to use
for a company's own internal operations, not to distribute. Each package carries the terms as `LICENSE.md`.
`Program.cs` is the whole composition; everything specific to this system is in `appsettings.json`.

Status: prepared and tested locally, **not yet deployed**. See "Before the first deployment".

**Source of truth:** this folder, `samples/cmdemo1-aisf/` in `ClearMeasureLabs/AISoftwareFactory`. Point the
kit's `add-demo-deployable.ps1 -Source` at a checkout of this folder; `/home/jeffrey/Projects/cmdemo1-aisf`
is only a working copy, so carry any change made there back here.

## What is here

| File | Purpose |
|---|---|
| `Program.cs` | `AddAisfFactory(factory => factory.UseGitHubWorkTracking().AddCursorWorker())`, and `GET /_build` |
| `Factory.csproj` | Two references: `Aisf.Hosting`, and the messaging provider `Aisf.Messaging.NServiceBus` |
| `appsettings.json` | The board, the three columns the factory works, the CI checks that gate a pull request |
| `NuGet.Config` | nuget.org plus the private `Aisf.*` feed |
| `Dockerfile` | The image: port 8080, health at `/health`, non-root |
| `scripts/write-build-facts.sh` | Run by the image build: writes `build-facts.json`, which `/_build` answers |
| `deployable.json` | The entry for `add-demo-deployable.ps1 -Definition` (kit PR #1) |

To change a Cursor prompt, add `Prompts/cursor/cursor-<column>.md` here; it replaces the packaged
one of the same name. Give those files `CopyToOutputDirectory` in `Factory.csproj`.

## What the container was built from

`GET /_build` answers without sign-in, from any origin, with the document every app of the system serves
(the same property names; what does not apply is `null`):

- `version`, `commit`, `commitUrl`, `buildUrl`: the Build workflow passes them to the image build as the
  build arguments `VERSION`, `COMMIT`, `REPOSITORY` and `RUN_ID`, which the `Dockerfile` declares;
- `builtAt`: when the image was built;
- `code`: non-blank lines per language of the source files the image is built from (the build context);
- `tests`, `coverage`, `complexity`, `crap`, `analysis`: `null`. This repository composes packages and has
  no tests or analysis of its own;
- `packages`: name and version of each `Aisf.*` package the restore resolved. `Factory.csproj` references
  `0.1.0-alpha.*`, so this is what says which factory a container runs.

The `Dockerfile` runs `scripts/write-build-facts.sh` after the publish, and the file lands next to the
executable. A build without it (`dotnet run`, `dotnet publish`) answers 404.

## Run it locally

```bash
ASPNETCORE_ENVIRONMENT=Development GitHub__UseStub=true CursorAgent__SimulateLocal=true dotnet run
```

Restoring needs `NuGetPackageSourceCredentials_aisf="Username=aisf;Password=<token with read:packages>"`.

## Before the first deployment

These need a person; none could be done unattended.

1. **A token that can read the packages.** The feed is private to `ClearMeasureLabs`, and this
   repository is in another organization. Create a token with only `read:packages` and store it
   as the Actions secret `AISF_PACKAGES_TOKEN` with the kit's `set-demo-build-secret.ps1`. The
   deployable is added with `-BuildSecret aisf_packages_token=AISF_PACKAGES_TOKEN`, which makes
   the image build pass it to the Dockerfile as a build secret (kit PR #1).
2. **The factory's GitHub App.** `aisf-board` can move cards but cannot comment, push or open pull
   requests. The factory needs Contents, Pull requests and Issues read/write, Actions and Checks
   read, and organization Projects read/write. Put its app id and installation id in
   `deployable.json`, and its private key in the vault as `github-app-private-key`.
3. **Cursor.** Install Cursor's GitHub App on `cmdemo1-workorders` (it is not installed on the
   organization), and put a Cursor Cloud Agent API key in the vault as `cursor-api-key`.
4. **Entra app registration: done (2026-10-05).** "cmdemo1 AI Software Factory (tdd)", app id
   `f111fb18-3749-4a5c-abde-19c507ae8338`, single tenant, owned by the operator identity
   `cm-ai-ops`. Redirect URI
   `https://ca-cmdemo1-tdd-aisf.graybush-19a6e13b.southcentralus.azurecontainerapps.io/signin-oidc`,
   ID tokens enabled, no client secret. The tenant and client ids are in `deployable.json`. Sign-in
   without a client secret has not been tried against the live tenant yet; if it needs the
   authorization-code flow, add a secret to the registration and
   `{ "name": "entra-client-secret", "env": "AzureAd__ClientSecret" }` to `secrets`.
5. **Board columns and labels.** Project 679 has only Todo, In Progress and Done. Add three Status
   options between In Progress and Done, in this order: Technical Design, Development, Functional
   Testing. Create the labels `AI Factory`, `Ready To Move` and `Auto Merge` in `cmdemo1-workorders`.
   A person hands an item to the factory by adding the `AI Factory` label; see "From a tagged item to
   production".
6. **Webhooks**, with content type `application/json` and the value stored as
   `github-webhook-secret`:
   - organization hook, event "Project v2 items", to `https://<host>/api/webhooks/projects/`
     (needs `admin:org_hook`, which the operator's token does not have);
   - repository hook on `cmdemo1-workorders`, events Issues, Workflow runs and Releases, to
     `https://<host>/api/github/webhooks/issues/`;
   - repository hook on `cmdemo1-workorders`, event Workflow jobs, to
     `https://<host>/api/github/webhooks/deployments/`, once the deploy jobs are named in
     `appsettings.json` (below).

Then follow the runbook in kit PR #1 (`add-demo-deployable.ps1 -Name aisf -Container ...`).

## From a tagged item to production

`ItemToProductionTests` drives this whole path against this host, built from the packages, with GitHub,
Cursor and the application's pipeline played by the test.

1. **Tag it.** Add the `AI Factory` label to an issue that is on the board. The factory ignores an item
   without the label, even one a person moves into a column it works. From a column the factory does
   not work (Todo, In Progress) it moves the item forward itself until it reaches one it does.
2. **Design, development, validation.** In each column of `AIWorkers:AiToolColumns` the factory launches
   Cursor with that column's prompt and moves the item on when the agent reports completion. In
   Development the agent must have opened a pull request that changes product files. In Functional
   Testing the agent posts a pass or fail verdict.
3. **Merge.** The packages leave merging off; this host turns it on (`AIWorkers:DisableFactoryAutoMerge`
   is `false` in `appsettings.json`). The item must also carry the `Auto Merge` label; the factory then
   approves and squash-merges the pull request on a PASS verdict. Without the label it comments that
   validation passed and waits for a person to merge.
4. **Build and release candidate.** After the merge the factory waits for the default branch to go green
   at the merge commit, then for a GitHub release tagged `rc-<version>` whose notes carry a table with
   `| commit | <sha> |` and `| image (GitHub) | <image> |` rows. With no such release within 20 minutes
   (`AIWorkers:ReleaseCandidateTimeoutMinutes`) it parks the item for a person.
5. **Deployments.** The factory follows the deploy jobs it has been given the names of:
   `GitHub:DeployWorkflowName`, `GitHub:DeployJobTdd`, `GitHub:DeployJobUat` and `GitHub:DeployJobProd`.
   It comments on the item when a job succeeds, and on a production success moves the item to Done and
   closes it. It does not start a deployment.

**Not yet true for cmdemo1.** As of 2026-10-06 the `cmdemo1-workorders` pipeline is `Build` then
`Release`, which creates an Octopus release; Octopus deploys it. It publishes no `rc-*` GitHub release
and has no GitHub deploy job. A merged item therefore parks at step 4 with a "no release candidate"
comment, and the factory does not see any deployment. Until that changes, a first run on cmdemo1 ends
at the merge. Either the pipeline reports those two things to GitHub, or the factory learns to
hear them from Octopus; that decision is open.

More columns (Conceptual Definition, UX Design, Test Design, UX Testing, Release Queue) are added in
`AIWorkers:AiToolColumns` and on the board. With the packaged prompts UX Testing is a human gate: the
agent records a demo and a person moves the card on.

## Tests

CI keeps this host honest: on every push, the `fullsystem-githubcursorfactory` job packs the `Aisf.*`
packages from that commit, builds this folder from them alone (the packed feed replaces `NuGet.Config`
for the run) and runs the factory's full-system suite against the published `Cmdemo1.Factory.dll`. A
change to the packages that breaks this host fails that build. To run the same locally from the
repository root:

```bash
pwsh ./scripts/Test-PackagedFactory.ps1 -HostDirectory samples/cmdemo1-aisf
```

Against the packages on the private feed instead:

```bash
dotnet publish Factory.csproj -c Release -o /tmp/cmdemo1-aisf
AISF_FST_HOST_PATH=/tmp/cmdemo1-aisf/Cmdemo1.Factory.dll \
  dotnet test <AISoftwareFactory>/AISoftwareFactory3-21.FullSystemTests.GitHubCursorFactory
```
