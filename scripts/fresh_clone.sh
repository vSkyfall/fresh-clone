#!/usr/bin/env bash
# fresh_clone.sh: clone a repo into a throwaway directory and print the facts
# a README should agree with. Read-only with respect to the source repo.
#
# Usage: fresh_clone.sh <git-url | owner/repo | local-path>

set -uo pipefail

src="${1:-.}"

# owner/repo shorthand -> GitHub URL (only when it isn't an existing local path)
if [[ ! -e "$src" && "$src" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  src="https://github.com/$src.git"
fi

# Local path: resolve to the repo root so we clone committed state, and warn
# about uncommitted work that won't be part of the test.
if [[ -e "$src" ]]; then
  root="$(git -C "$src" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "error: $src is not inside a git repository" >&2; exit 1; }
  src="$root"
  if [[ -n "$(git -C "$src" status --porcelain 2>/dev/null)" ]]; then
    echo "note: $src has uncommitted changes; they are NOT included in this test"
  fi
fi

tmpbase="${TMPDIR:-/tmp}"
tmp="$(mktemp -d "${tmpbase%/}/fresh-clone.XXXXXX")"
dest="$tmp/repo"

if ! git clone --quiet --depth 50 "$src" "$dest" 2>"$tmp/clone.err"; then
  # --depth is ignored/unsupported for some local clones; retry without it
  rm -rf "$dest"
  git clone --quiet "$src" "$dest" 2>"$tmp/clone.err" || {
    echo "error: clone failed:" >&2; cat "$tmp/clone.err" >&2; exit 1; }
fi

cd "$dest" || exit 1

section() { printf '\n## %s\n' "$1"; }
# Exact-case check against git's index, so README.md and readme.md aren't
# conflated on case-insensitive filesystems (macOS, Windows).
has() { git ls-files --error-unmatch -- "$1" >/dev/null 2>&1 || [[ -d "$1" && -n "$(git ls-files -- "$1")" ]]; }
list_or_none() { if [[ -n "$1" ]]; then printf '%s\n' "$1"; else echo "(none)"; fi; }

echo "# fresh-clone facts"
echo "clone_path: $dest"
echo "temp_root:  $tmp   (delete this when done)"
echo "commit:     $(git rev-parse --short HEAD) ($(git log -1 --format=%cs))"
echo "os:         $(uname -s) $(uname -m)"
# The clone's origin is the source we cloned from; report the source repo's own
# remote instead, since that's the URL the README's clone step should match.
if [[ -n "${root:-}" ]]; then
  remote="$(git -C "$root" remote get-url origin 2>/dev/null)"
else
  remote="$src"
fi
echo "remote:     ${remote:-(none: the source repo has no origin remote)}"

section "Docs a new user reads"
for f in README.md README.rst README readme.md CONTRIBUTING.md INSTALL.md docs/getting-started.md docs/README.md; do
  has "$f" && echo "$f  (last changed $(git log -1 --format=%cs -- "$f" 2>/dev/null || echo '?'))"
done

section "Translated READMEs (compare against the main one)"
found=""
while IFS= read -r f; do
  [[ -n "$f" ]] && found+="$f  (last changed $(git log -1 --format=%cs -- "$f"))"$'\n'
done < <(git ls-files | grep -E '(^|/)README[._-][A-Za-z]{2}([_-][A-Za-z]{2,4})?\.(md|rst)$' \
         | grep -viE '^README\.(md|rst)$')
list_or_none "${found%$'\n'}"

section "Languages / package managers / lockfiles"
for f in package.json package-lock.json pnpm-lock.yaml yarn.lock bun.lockb bun.lock \
         pyproject.toml requirements.txt requirements-dev.txt Pipfile poetry.lock uv.lock setup.py \
         go.mod Cargo.toml Gemfile composer.json pom.xml build.gradle build.gradle.kts \
         mix.exs pubspec.yaml Package.swift deno.json; do
  has "$f" && echo "$f"
done

section "Version pins"
for f in .nvmrc .node-version .python-version .ruby-version .tool-versions rust-toolchain rust-toolchain.toml; do
  has "$f" && echo "$f: $(head -c 200 "$f" | tr '\n' ' ')"
done
if has package.json; then
  flat="$(tr -d '\n' < package.json | tr -s ' ')"
  eng="$(grep -oE '"engines"[[:space:]]*:[[:space:]]*\{[^}]*\}' <<<"$flat")"
  [[ -n "$eng" ]] && echo "package.json $eng"
  pm="$(grep -oE '"packageManager"[[:space:]]*:[[:space:]]*"[^"]*"' <<<"$flat")"
  [[ -n "$pm" ]] && echo "package.json $pm"
fi
has pyproject.toml && grep -E '^[[:space:]]*requires-python' pyproject.toml
has go.mod && grep -E '^go [0-9]' go.mod

section "Runnable scripts / targets"
if has package.json; then
  echo "package.json scripts:"
  tr -d '\n' < package.json | grep -oE '"scripts"[[:space:]]*:[[:space:]]*\{[^}]*\}' \
    | grep -oE '"[^"]+"[[:space:]]*:' | sed -E 's/"([^"]+)".*/\1/' | grep -v '^scripts$' | sed 's/^/  - /'
fi
if has Makefile; then
  echo "Makefile targets:"
  grep -oE '^[A-Za-z0-9_.-]+:' Makefile | grep -v '^\.' | tr -d ':' | sort -u | sed 's/^/  - /'
fi
if has justfile; then
  echo "justfile recipes:"
  grep -oE '^[A-Za-z0-9_-]+' justfile | sort -u | sed 's/^/  - /'
fi
if has pyproject.toml; then
  s="$(sed -n '/^\[project.scripts\]/,/^\[/p' pyproject.toml | grep '=')"
  [[ -n "$s" ]] && { echo "pyproject [project.scripts]:"; echo "$s" | sed 's/^/  /'; }
fi

section "Env / config templates"
list_or_none "$(find . -maxdepth 3 -not -path './node_modules/*' -not -path './.git/*' \
  \( -name '.env.example' -o -name '.env.sample' -o -name '.env.template' -o -name '.env.dist' \
     -o -name 'example.env' -o -name '*.example.yml' -o -name '*.example.yaml' -o -name 'config.example.*' \) 2>/dev/null)"

section "Env vars read in code (compare with README)"
# Heuristic grep across common languages; dedupe and cap output.
vars="$(grep -rhoE \
  "process\.env\.[A-Z][A-Z0-9_]+|process\.env\[['\"][A-Z][A-Z0-9_]+|import\.meta\.env\.[A-Z][A-Z0-9_]+|os\.environ(\.get)?\(?\[?['\"][A-Z][A-Z0-9_]+|os\.getenv\(['\"][A-Z][A-Z0-9_]+|os\.Getenv\(\"[A-Z][A-Z0-9_]+|env::var\(\"[A-Z][A-Z0-9_]+|ENV\[['\"][A-Z][A-Z0-9_]+" \
  --include='*.js' --include='*.mjs' --include='*.cjs' --include='*.ts' --include='*.tsx' --include='*.jsx' \
  --include='*.py' --include='*.go' --include='*.rs' --include='*.rb' --include='*.vue' --include='*.svelte' \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build --exclude-dir=vendor \
  --exclude-dir=.venv --exclude-dir=venv --exclude-dir=target . 2>/dev/null \
  | grep -oE '[A-Z][A-Z0-9_]+$' | grep -vE '^(NODE_ENV|HOME|PATH|PWD|USER|CI|DEBUG|TZ|LANG|TERM|SHELL)$' | sort -u | head -60)"
list_or_none "$vars"

section "Containers"
list_or_none "$(ls -1 Dockerfile* docker-compose*.y*ml compose*.y*ml .devcontainer/devcontainer.json 2>/dev/null)"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  echo "docker: usable (clean-machine run possible)"
elif command -v docker >/dev/null 2>&1; then
  echo "docker: installed but not running (start your Docker engine, e.g. Docker Desktop, OrbStack or 'colima start', for a clean-machine run)"
else
  echo "docker: not installed"
fi

section "CI workflows (what the project actually runs)"
if [[ -d .github/workflows ]]; then
  for f in .github/workflows/*.y*ml; do
    [[ -e "$f" ]] || continue
    echo "$f"
    grep -E '^[[:space:]]*(-[[:space:]]*)?run:' "$f" | sed -E 's/^[[:space:]]*(-[[:space:]]*)?run:[[:space:]]*/    run: /' | head -12
    grep -E 'runs-on:|node-version|python-version|go-version' "$f" | sed -E 's/^[[:space:]]*/    /' | sort -u | head -6
  done
else
  echo "(none)"
fi
for f in .gitlab-ci.yml .circleci/config.yml .travis.yml azure-pipelines.yml; do has "$f" && echo "$f"; done

section "Other files a README usually points to"
found=""
for f in LICENSE LICENSE.md LICENSE.txt CONTRIBUTING.md CODE_OF_CONDUCT.md CHANGELOG.md SECURITY.md; do
  has "$f" && found+="$f"$'\n'
done
list_or_none "${found%$'\n'}"

section "Local links in README that don't resolve"
readme=""
for f in README.md readme.md README.rst README; do has "$f" && { readme="$f"; break; }; done
if [[ -n "$readme" ]]; then
  broken=""
  while IFS= read -r link; do
    target="${link%%#*}"; target="${target%%\?*}"
    [[ -z "$target" ]] && continue
    [[ -e "$target" ]] || broken+="$link"$'\n'
  done < <(grep -oE '\]\([^)]+\)' "$readme" | sed -E 's/^\]\(//; s/\)$//; s/[[:space:]].*$//' \
           | grep -vE '^(https?:|mailto:|#|data:)')
  list_or_none "${broken%$'\n'}"
else
  echo "(no README found)"
fi

echo
echo "done. work inside: $dest"
