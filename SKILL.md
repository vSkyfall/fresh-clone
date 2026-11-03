---
name: fresh-clone
description: Tests whether a repository's README actually works by cloning the repo into a throwaway directory (optionally a clean Docker machine) and following the setup instructions exactly like a brand-new user would, running every command for real and timing it. Produces a step-by-step pass/fail report with "time to first run", a list of concrete README improvements with evidence ("add X because…", "remove Y because…"), checks translated READMEs for drift, then walks the user through each fix one at a time and can open a pull request. Use this whenever the user asks to check, test, verify, audit or improve a README, getting-started guide, installation docs or onboarding instructions; whenever they say things like "does my README still work", "would a new contributor get stuck", "my install docs are probably outdated", "someone opened an issue saying setup fails" or "clean up the README"; and before a release or open-sourcing a project. Trigger even if the word README is not used but the request is about whether setup/installation instructions are accurate.
---

# fresh-clone

A README is a promise: "follow these steps and it works." Maintainers write it once and then the project moves on: a script gets renamed, a config file moves, a new environment variable appears. Nobody notices because the maintainer never follows their own README again. The next new user does, gets stuck at step 3, and either opens an "installation doesn't work" issue or quietly leaves.

Your job with this skill is to **be that new user**, honestly, and then tell the maintainer exactly where they would have lost you and what to change.

## Core principles

1. **Really run it.** Reading the README and guessing "this looks fine" is worthless; the whole value is in executing the commands and seeing what actually happens. If a step can't be run, say so explicitly rather than assuming it works.
2. **Know nothing.** Pretend you have never seen this project. If the README says "configure the database" without saying how, a new user is stuck, even if you could figure it out from the code. Report that as a gap. Don't use knowledge you only got from reading the source to silently fill holes in the docs.
3. **Never touch the real repo without asking.** All testing happens in a fresh clone in a temporary directory. The user's working copy, branches and uncommitted changes are never modified, except for fixes the user approves one by one in Step 7.
4. **Evidence, not opinions.** Every ❌ cites the actual error output. Every "add this" or "remove this" cites a file, a command output or a commit. Suggestions without evidence get cut; style nitpicks ("make the intro more exciting") are not this skill's job.

## Asking the user

Several steps below ask the user to decide something. Ask **one decision at a time**. Use the AskUserQuestion tool when it's available: one question per call, a short question that states the change *and why*, and two options, a "Yes…" option and a "No…" option. The tool automatically adds "Other", where the user can type their own answer; treat that text as their instruction for this item (e.g. "yes but call it APP_SECRET", "put it in a Troubleshooting section instead").

If AskUserQuestion isn't available, ask the same thing in one short message and wait: *"…? (yes / no / or tell me what you'd prefer)"*.

One decision per question, so the user can accept, reject or reshape each one. Two refinements keep this from becoming tedious:
- **Same cause, same question.** When several fixes come from one change (e.g. three README lines all broken by the rename in commit 6f2b9b3), ask once and show all of them in the question: *"Update the 3 steps that broke when 6f2b9b3 renamed things? (`.env.example` → `.env.sample`, `npm start` → `npm run dev`, drop `npm run seed`)"*. Unrelated fixes still get their own question.
- **Questions that need a value** (the right clone URL, the real port, a maintainer's choice of wording) aren't yes/no. Ask the question directly, offer the most likely concrete answers as options when you have them (e.g. the two candidate URLs), and otherwise use "Remove this line" / "Leave it for now", saying in the question that they can type the right value under "Other".

## Workflow

### Step 1: Get a fresh clone

Figure out what to test:
- A URL or `owner/repo` given by the user → clone that.
- Otherwise, the current directory → clone it **from its local path** (`git clone /path/to/repo`), which tests the committed state. Tell the user if there are uncommitted changes, since those aren't being tested.

Run the bundled helper, which clones into a temp directory and prints facts about the repo you'll need later:

```bash
bash <skill-dir>/scripts/fresh_clone.sh <repo-url-or-path>
```

It prints the clone path, the source repo's `remote:` URL, plus: detected languages and package managers, lockfiles, version pins (`.nvmrc`, `engines`, `.python-version`, `go.mod`, `rust-toolchain`), scripts/targets (package.json scripts, Makefile targets, justfile recipes), env vars referenced in code, `.env.example`-style files, Docker/compose files, CI workflow files, translated READMEs, whether Docker is usable, and README links to local files that don't exist. Keep this output: it's the ground truth you compare the README against.

### Step 2: Choose the machine (ask once)

Your machine is not a new user's machine: it probably already has Node, Python, compilers and global tools installed, so a README that forgets to mention them still "works" for you. A clean container catches that.

If the helper reports `docker: usable`, ask the user (see *Asking the user*):

> "Test on a clean machine (Docker)? It catches prerequisites your README forgets, like Node or Python, because nothing is preinstalled. Takes a bit longer."
> Options: "Yes, use a clean machine" / "No, use this computer"

If Docker isn't usable, skip the question, test locally, and mention in the report's *Not tested* section that a clean-machine run would also catch missing prerequisites.

For a clean-machine run, read **references/clean-machine.md** and use its exact commands. In short: one disposable `ubuntu:24.04` container with only `git`, `curl` and `perl`, the clone **copied** in with `docker cp` (not mounted: on macOS a mount of the temp folder silently shows up empty), every step run inside it through the step runner, and the container removed at the end.

### Step 3: Extract the new-user path

Read `README.md` (and anything it points a new user to: `CONTRIBUTING.md`, `docs/getting-started.md`, `INSTALL.md`). Turn the prose into an ordered checklist of concrete steps a new user is expected to perform, roughly:

1. Prerequisites (runtime versions, system tools, accounts)
2. Install (clone, dependency install)
3. Configure (env files, config, secrets, databases)
4. Run (dev server, CLI, build)
5. Verify ("open http://…", "you should see…", run tests)

Write this checklist down before executing anything, with the exact command for each step as the README gives it. Where the README is vague ("set up your environment"), record the step as written; vagueness is itself a finding.

If the README has multiple paths (Docker vs. local, npm vs. pnpm), test the one presented first or most prominently; mention the others as untested unless the user asked for all.

### Step 4: Run every step, and time it

Execute each step in order, in the clone, as literally as the README states it. Classify each one:

| Mark | Meaning | Counts as failure? |
|------|---------|--------------------|
| ✅ works | Ran cleanly and did what the README implies | no |
| ⚠️ misleading | Ran, but reality differs from the README (different port, deprecation warning, extra step needed, different output) | yes, soft |
| ❌ broken | Command failed, file missing, script doesn't exist | yes |
| ⏭️ needs human | Requires a real account, paid API key, sudo on the host, hardware, or interactive login | no |
| 🤷 unclear | README doesn't say enough to know what to do | yes, soft |

**Run each step through the bundled runner**, from inside the clone:

```bash
bash <skill-dir>/scripts/run_step.sh 300 '<command exactly as the README says>'
```

It applies a timeout (portable; macOS has no `timeout`), prints the command's output, and ends with `__STEP__ exit=<code> seconds=<1.23> timed_out=<0|1>`. Use those numbers for the Result and Time columns instead of timing by hand.

**Time to first run** is the headline number: the summed command time from the clone until the project first visibly works (server answers, CLI prints its output, tests pass), whichever the README's "verify" step is. It deliberately excludes the time a human spends reading, so say "commands only". It answers *"what happens to someone who follows the README literally?"*, so if a step blocks that person, the answer is **"never (blocked at step N)"**, even if you worked around it. When you did get it running through workarounds, add that in brackets so the maintainer sees what fixing it would buy: *"never (blocked at step 4; 9s with workarounds)"*. Timing makes the report comparable over time: "setup went from never to 9s after the fixes" is a great outcome to tell the user.

Practical rules, and why:
- **Long-running commands** (dev servers, watchers) never exit by themselves. Start them in the background (`run_step.sh 300 '<cmd>' > server.log 2>&1 &`), poll until the port answers or the log shows it's ready, check it, then kill the background job. Count the time until it was ready, not the timeout.
- **The README's own `git clone <url>` step**: you already cloned, so don't clone again. Check the URL is real with `git ls-remote <url> >/dev/null`, and compare it with the `remote:` line the helper printed. Dead URL, or a URL that doesn't match the remote → ❌. If the repo has no remote at all, you can't know the right URL; report the dead URL and ask the user for the right one in Step 7 (they'll answer via "Other"). Then continue with your clone.
- **Watch for files a step creates that the repo doesn't have.** `npm install` on a repo without a lockfile writes a fresh `package-lock.json`, `pip install -e .` writes egg-info, and so on. Note anything significant: it often means CI (`npm ci`) or a teammate's setup will behave differently. If you then test CI-style commands, do it after deleting those generated files, or the clone hides the problem.
- **Copying an env file isn't the same as loading it.** After `cp .env.sample .env`, check that something actually reads `.env` (dotenv, `--env-file`, a framework that loads it, docker-compose `env_file`). If nothing does, the app will behave as if the file weren't there, and that's a finding.
- **Verify "open http://…" claims for real**: `curl -sI` the URL, or use a browser tool if available, and confirm the status and roughly the content the README describes. A server that starts but 500s is a ❌.
- **On this computer, prefer local/project-scoped installs** (`npm ci`, a venv, `cargo build`). Don't install global packages, don't run `sudo`, don't run `curl … | sh` from a domain that isn't the project's own; mark those ⏭️ with a note. You're a guest on the user's machine. (Inside a clean-machine container you may install what the README tells you to; see the reference file.)
- **When a step fails, diagnose before moving on.** Look at what the README expected vs. what exists: `ls`, `git log --oneline -S"<name>" -- <path>`, package.json scripts, Makefile. Usually the answer is "renamed in commit abc123" or "file was deleted" and that's exactly the evidence the maintainer needs. Then do the minimum needed to continue (e.g. use the renamed script) so later steps can still be tested, and say that you did.
- **Secrets never get invented.** If a step needs a real key, don't fabricate one; mark ⏭️, and continue if the project runs without it. Placeholder values that the project's own sample file provides are fine.

### Step 5: Compare the README against the repo facts

Now the improvement pass. Using the helper output from Step 1 and what you saw while running, build the lists below. Each entry has the form **what → why (evidence)**. Only include items where a new user would concretely be helped or where the README is factually out of date.

**Add this, because…** Look for:
- Prerequisites the repo enforces but the README omits (an `engines`/`.nvmrc` version, a required system tool, a database). A clean-machine run proves these directly.
- Environment variables the code reads that aren't documented (compare the helper's env-var list with the README).
- A missing "how do I know it worked" step (expected URL, expected output, a smoke-test command).
- Missing "how to run tests" when a test script or CI workflow exists.
- Missing troubleshooting for any error you hit that a new user is likely to hit too.
- Missing license or contribution pointer when those files exist.

**Remove this, because…** Look for:
- Steps referencing scripts, files, flags or commands that no longer exist (you have the commit that removed them).
- Duplicate or contradictory instructions (two different install commands for the same thing).
- Badges that are broken or point to retired services; links that 404.
- Sections about platforms, versions or features the repo no longer supports (confirm with the code/CI, not a guess).
- "Coming soon" / "TODO" notes that are older than about a year (use `git log` on the README to date them).

A value that's simply wrong (a clone URL, port, file name, script name) is one item, not a remove plus an add. Put it under *Remove this* phrased as a change: **`npm start` → `npm run dev`** → renamed in 6f2b9b3. If the right value can't be known from the repo, say so in the item; the user supplies it in Step 7.

Keep each list short and ranked by impact on a new user. Five sharp items beat twenty weak ones.

Some problems can't be fixed by editing the README: a lockfile that isn't committed, so CI's `npm ci` fails; a script that should load `.env` but doesn't; a test command that runs zero tests. Put these in a separate **Repo fixes** list. Don't mix them into the README lists.

### Step 6: Check translated READMEs

If the helper lists translations (`README.tr.md`, `README.zh-CN.md`, `docs/README.ja.md`, …), check each one against the main README. Don't run them again; the commands are the same in every language, so compare what is language-independent:
- commands in code blocks, file names, script names, env var names, URLs and port numbers;
- whether a section that exists in the main README (e.g. Configuration) is missing entirely;
- the last-changed dates the helper prints for each file.

Report drift as concrete lines: *"`README.tr.md` still says `npm start` (renamed to `npm run dev` in 6f2b9b3; translation last changed 2024-01-10)."* Judge staleness by content, not by which file has the newer date: a translation edited last week can still carry commands that were renamed a year ago, and commit dates in a history aren't always in order. Remember that after the user accepts fixes to the main README, the translations will need the same fixes: offer them in Step 7 as well. You can translate the changed lines yourself; keep the translator's wording everywhere else.

### Step 7: Report, then walk through the fixes one at a time

Write the report using exactly this structure so results are scannable and comparable between runs:

```markdown
# fresh-clone report: <repo name>

Tested <commit short-sha> on <OS | "clean machine (ubuntu:24.04)">, <date>. Path tested: <e.g. "Local install (npm)">.

## Result: <N>/<M> steps work · time to first run: <1m 12s (commands only) | never (blocked at step N)>

| # | Step (as the README says it) | Result | Time | What happened |
|---|------------------------------|--------|------|---------------|
| 1 | `git clone …`                | ✅     | 2s   | ok            |
| 2 | `npm install`                | ✅     | 14s  | ok            |
| 3 | `cp .env.example .env`       | ❌     | 0s   | `.env.example` doesn't exist; renamed to `.env.sample` in a1b2c3d |
| 4 | `npm run dev`                | ⚠️     | 3s   | works, but on :5173, README says :3000 |
| 5 | "open the dashboard"         | 🤷     | –    | no URL given  |

**Where a new user gets stuck first:** step 3.

## Add this, because…
- **Node version requirement (`>=20`)** → `package.json` `engines` enforces it; a Node 18 user gets a cryptic `npm ci` error.
- **`DATABASE_URL` and `SESSION_SECRET` in the setup section** → read in `src/config.ts:12` and `src/auth.ts:40`, never mentioned; the app crashes at boot without them.

## Remove this, because…
- **`npm run seed` step** → script was removed in commit 9f8e7d6 ("drop seeding, use fixtures"); the command fails.
- **Travis CI badge** → image 404s; CI moved to GitHub Actions.

## Repo fixes (not README)
- **Commit `package-lock.json`** → CI runs `npm ci`, which fails on a fresh clone without a lockfile.

## Translations
- **`README.tr.md`** → still says `npm start` and `.env.example`; last changed 2024-01-10.

## Not tested
- Docker path (README offers it second).
- Step 6 (Stripe webhook) needs a real Stripe key: ⏭️.
```

Fill every section; write "none" rather than deleting a heading, so the reader knows you looked.

Then, instead of asking "apply all of these?", **go through the items one at a time**, in the order they appear (Add, Remove, Repo fixes, Translations), following *Asking the user*. Each question names the change and the reason in one or two short sentences, for example:

> "Add the Node 20 requirement to the README? package.json requires Node ≥20, and older versions fail with a confusing error."
> Options: "Yes, add it" / "No, skip it"

> "Remove the `npm run seed` step? That script was deleted in 9f8e7d6, so the command always fails."
> Options: "Yes, remove it" / "No, keep it"

Keep a list of what was accepted, skipped, or answered with the user's own text. Don't edit anything until you've asked about every item. If the user says something like "just do all of them", accept that and stop asking.

### Step 8: Apply the accepted fixes, and offer a pull request

Apply only the accepted items (and the user's own "Other" versions of them) to the real repo with a minimal diff. Fix broken commands, add missing items, remove stale ones, and keep the maintainer's voice and structure. Don't rewrite sections that were fine. Show the diff and a one-line summary ("5 accepted, 2 skipped").

Then ask one more question. Which one depends on the `remote:` line from the helper:

- **GitHub remote** →
  > "Open a pull request with these README fixes? I'll put them on a new branch so your current branch stays untouched."
  > Options: "Yes, open a PR" / "No, just keep the edits"
- **Other remote, or no remote** →
  > "Commit these fixes on a new branch? Your current branch stays untouched, and you can push it whenever you like."
  > Options: "Yes, make a branch" / "No, just keep the edits"
  On yes, do steps 1 and 3 below (skip pushing).

On yes to the PR:
1. Create a branch named `fresh-clone/readme-fixes` (add a date suffix if it exists) from the current HEAD, commit only the files you changed, with a message like `docs: fix README setup steps (found by fresh-clone)`.
2. Push it, and if the `gh` CLI is installed and authenticated, run `gh pr create` with the report as the body (results table, accepted fixes, skipped items). Without `gh`, push and give the user the compare URL GitHub prints, so they can open the PR in one click.
3. Switch back to the branch the user was on.

On no, leave the edits uncommitted in the working copy.

Finally, offer one quick re-test of the fixed README ("Re-run fresh-clone on the fixed version to confirm it works now?" "Yes, re-test" / "No, I'm done"). When re-testing, clone the PR branch, or the working copy if the user kept uncommitted edits (copy the working tree into a temp folder instead of cloning, since uncommitted edits aren't in git). A before/after line like *"time to first run: never → 41s"* is the best possible ending.

### Cleanup

Always delete the temp clone, kill any background servers you started, and remove any container you created. Write the literal path and name the helper printed (`rm -rf /var/folders/…/fresh-clone.Ab12Cd`, `docker rm -f fresh-clone-1793727709`) rather than a shell variable or `$(…)`: safety checks in many environments refuse to delete a target they can't see.

## Scope notes

- Monorepos: test the root README; if it just points to packages, test the package the README highlights first and say so.
- Private repos: cloning uses the user's existing git credentials; never ask for or store tokens.
- If the README is empty or has no setup section at all, skip the run and report that as the single finding, with an "Add this" list derived from the repo facts (what a minimal README for this repo needs).
- A README that works perfectly is a valid result. Say so plainly, give the time to first run, and still give the add/remove lists if there's something real; otherwise write "none".
