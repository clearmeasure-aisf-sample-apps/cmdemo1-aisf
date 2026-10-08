#!/bin/sh
# Writes build-facts.json: what GET /_build answers about the build this image runs. Program.cs serves the file.
# The Dockerfile's build stage runs it in the source directory, after the publish:
#   sh scripts/write-build-facts.sh /app/publish/build-facts.json
#
# The document has the properties every app of the system serves, so one reader understands them all. A property
# that does not apply is null.
#   version, commit, commitUrl, buildUrl   from VERSION, COMMIT, REPOSITORY (owner/name) and RUN_ID, which the Build
#                                          workflow passes as build arguments; null in a build that has none
#   builtAt                                now
#   code                                   the source files of the build context, non-blank lines per language
#   tests, coverage, complexity, crap, analysis
#                                          null: this repository composes packages; it has no tests and no analysis
#   packages                               name and version of the Aisf.* packages the restore resolved
#                                          (obj/project.assets.json). Factory.csproj references a floating version,
#                                          so this is what says which factory the image holds. Nothing else about
#                                          the packages is written: no feed, no path.
set -eu
export LC_ALL=C

output=${1:?usage: write-build-facts.sh <output file> [project.assets.json]}
assets=${2:-obj/project.assets.json}

# The value when it is one line that matches the pattern, otherwise nothing: only what is expected reaches the
# document, so no value needs escaping.
checked() {
    if [ "$(printf '%s' "$1" | wc -l)" -eq 0 ] && printf '%s' "$1" | grep -Eqx -- "$2"; then printf '%s' "$1"; fi
}

# A JSON string, or null for nothing.
json() {
    if [ -n "$1" ]; then printf '"%s"' "$1"; else printf 'null'; fi
}

version=$(checked "${VERSION:-}" '[0-9A-Za-z][0-9A-Za-z.+-]*')
commit=$(checked "${COMMIT:-}" '[0-9a-f]{40}')
repository=$(checked "${REPOSITORY:-}" '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+')
run=$(checked "${RUN_ID:-}" '[0-9]+')
commit_url=''
build_url=''
if [ -n "$repository" ] && [ -n "$commit" ]; then commit_url="https://github.com/$repository/commit/$commit"; fi
if [ -n "$repository" ] && [ -n "$run" ]; then build_url="https://github.com/$repository/actions/runs/$run"; fi

# Code: the languages the other apps of the system count, by file extension. Build output and packages are not
# written by hand. One row per language that has files ("lines name files"), the largest first.
languages='C#:cs,csx Razor:razor,cshtml TypeScript:ts,tsx JavaScript:js,jsx,mjs,cjs CSS:css,scss,sass,less
    HTML:html,htm SQL:sql PowerShell:ps1,psm1,psd1 Shell:sh,bash Python:py YAML:yml,yaml Bicep:bicep Markdown:md'
rows=$(
    for language in $languages; do
        files=0
        lines=0
        for extension in $(printf '%s' "${language#*:}" | tr ',' ' '); do
            for count in $(find . -type f -name "*.$extension" ! -path '*/bin/*' ! -path '*/obj/*' \
                ! -path '*/node_modules/*' -exec grep -c '[^[:space:]]' {} \;); do
                files=$((files + 1))
                lines=$((lines + count))
            done
        done
        if [ "$files" -gt 0 ]; then printf '%s %s %s\n' "$lines" "${language%%:*}" "$files"; fi
    done | sort -k1,1nr -k2,2
)
code='null'
if [ -n "$rows" ]; then
    total_lines=0
    total_files=0
    while read -r lines name files; do
        total_lines=$((total_lines + lines))
        total_files=$((total_files + files))
    done <<ROWS
$rows
ROWS
    code="{
    \"linesOfCode\": $total_lines,
    \"files\": $total_files,
    \"languages\": [
$(printf '%s\n' "$rows" | sed -E 's|^([0-9]+) ([^ ]+) ([0-9]+)$|      { "name": "\2", "lines": \1, "files": \3 }|' | sed '$!s/$/,/')
    ]
  }"
fi

# Packages: the keys of the assets file are "<package>/<version>", and each package is there more than once.
packages='null'
entries=''
if [ -f "$assets" ]; then
    entries=$(grep -oE '"Aisf\.[A-Za-z0-9_.-]+/[0-9A-Za-z.+-]+" *: *\{' "$assets" | sort -u |
        sed -E 's|^"([^/]+)/([^"]+)".*$|    { "name": "\1", "version": "\2" }|' | sed '$!s/$/,/')
fi
if [ -n "$entries" ]; then
    packages="[
$entries
  ]"
else
    echo "No Aisf.* package in $assets: packages is null."
fi

cat > "$output" <<FACTS
{
  "version": $(json "$version"),
  "commit": $(json "$commit"),
  "commitUrl": $(json "$commit_url"),
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "buildUrl": $(json "$build_url"),
  "code": $code,
  "tests": null,
  "coverage": null,
  "complexity": null,
  "crap": null,
  "analysis": null,
  "packages": $packages
}
FACTS
cat "$output"
