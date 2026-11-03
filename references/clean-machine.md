# Clean-machine runs (Docker)

Read this only when the user chose "Yes, use a clean machine" in Step 2.

The goal is to simulate a new user's laptop: an OS, `git`, `curl`, and nothing else. Every prerequisite the project needs must then come from the README. If the README doesn't mention Node and the first `npm install` fails with `npm: command not found`, that's not a test problem: it's the most valuable finding of the run.

Use literal values (the real container name and paths) in every command rather than shell variables: you'll run these across several tool calls, and some environments refuse `rm`/`docker rm` on unresolved variables.

## Start the machine

Copy the clone **into** the container with `docker cp`; don't bind-mount it. On macOS the helper's temp folder lives under `/var/folders/…`, which Colima and Docker Desktop don't share by default, so `-v <clone>:/work` silently gives you an empty `/work`. Copying also means nothing the container writes ends up root-owned on the host.

```bash
docker run -d --name fresh-clone-<unix-time> ubuntu:24.04 sleep infinity
docker exec fresh-clone-<unix-time> bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq git curl ca-certificates perl >/dev/null && mkdir /work && git config --global --add safe.directory /work'
docker cp "<clone_path>/." fresh-clone-<unix-time>:/work
docker cp "<skill-dir>/scripts/run_step.sh" fresh-clone-<unix-time>:/usr/local/bin/run_step
docker exec fresh-clone-<unix-time> bash -c 'chmod +x /usr/local/bin/run_step && ls -A /work | head'
```

**Check that last `ls` shows the repo's files.** If `/work` is empty, stop and fix it before running anything; otherwise every step fails for the wrong reason.

Use `ubuntu:24.04` unless the README explicitly targets something else (e.g. "requires Debian" → `debian:12`). Use `--platform linux/amd64` only if the project ships amd64-only binaries and you're on an ARM Mac. None of this setup counts toward time to first run, since a real user already has an OS.

## Run and time each step

Run the step runner *inside* the container, so timing measures the command and not `docker exec` overhead. Pass the README command through a quoted heredoc so quotes inside it survive untouched:

```bash
docker exec -i -w /work fresh-clone-<unix-time> bash -l <<'STEP'
run_step 300 'npm install'
STEP
```

Read the result from the `__STEP__ exit=… seconds=… timed_out=…` line, same as on the host.

**Long-running servers**: start in the background inside the container, then time "until ready" as its own measurement:

```bash
docker exec -i -w /work fresh-clone-<unix-time> bash -l <<'STEP'
nohup bash -lc 'npm run dev' > /tmp/server.log 2>&1 &
run_step 60 'until curl -s -o /dev/null http://localhost:5173; do sleep 0.1; done'
curl -sI http://localhost:5173 | head -1; tail -3 /tmp/server.log
STEP
```

The second `run_step` time is the server's startup time for the report. Stop the server afterwards with `docker exec fresh-clone-<unix-time> pkill -f '<the command>'`, or let container removal take care of it.

## Installing prerequisites

Inside the container you're root on a throwaway machine, so the "guest on the user's computer" restrictions don't apply. Install time is **not** part of time to first run (it varies with the network and is the same for every project); mention it in the step's "What happened" instead.

- **The README names a prerequisite** ("Install Node 20", "requires Python 3.12") → install it with the standard command for Ubuntu and mark the step ✅ (⚠️ if you had to guess a version):
  - Node: `curl -fsSL https://deb.nodesource.com/setup_<major>.x | bash - && apt-get install -y -qq nodejs`
  - Python: `apt-get install -y -qq python3 python3-venv python3-pip` (for another minor version: `pipx`/`uv python install <ver>`)
  - Poetry/uv/pipx tools: `apt-get install -y -qq pipx && pipx install <tool>`
  - Go: download the official tarball from go.dev/dl into `/usr/local` and add it to PATH
  - Rust: `curl -sSf https://sh.rustup.rs | sh -s -- -y`
  - Use `bash -l` for later steps so PATH changes are picked up.
- **The README doesn't name it at all** → the failure belongs to the README's missing prerequisites, not to the command that tripped over it. Add a row **"0 · Prerequisites (README lists none)"** marked ❌ with the evidence (`npm: command not found`; `engines` says `>=20`), install the version the repo pins (`engines`, `.nvmrc`, CI config), then run the command that failed again and grade *it* on its own merits. "Blocked at step 0" is then the honest headline.
- **The README pipes a third-party script into a shell (`curl … | sh`)** → fine to run here (it's the README's instruction, in a disposable container), but note the domain in the report.

## Checks that run on the host, not the container

The README's `git clone <url>` check (`git ls-remote`) and checking badge/link URLs need no container; run them on the host as in the main workflow.

## Cleanup

```bash
docker rm -f fresh-clone-<unix-time>
docker ps -a --filter name=fresh-clone-<unix-time> --format '{{.Names}}'
```

The second command should print nothing. Always remove the container, even if the run was cut short. The normal cleanup step deletes the temp clone on the host.

## Report

In the header line, write `clean machine (ubuntu:24.04)` as the OS. Don't list prerequisites under *Not tested*, since this run covered them.
