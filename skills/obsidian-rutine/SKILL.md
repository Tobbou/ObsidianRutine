---
name: obsidian-rutine
description: >-
  Install and maintain ObsidianRutine — an Obsidian vault set up as a portable
  AI brain for Claude Code: installs Obsidian and git if missing, creates the
  vault structure, configures Obsidian (community plugins, templates, daily
  notes, auto-backup), links Claude's config and memory into the vault, and
  installs the `vault` skill that makes Claude keep pushing new knowledge and
  project notes into the vault. Reports exactly what is still missing (e.g. the
  GitHub repo to sync to). Use for "install ObsidianRutine", "set up my
  Obsidian vault", "sæt Obsidian-rutinen op", "installer ObsidianRutine",
  "ObsidianRutine status", "hvad mangler i min Obsidian-opsætning", "connect my
  vault to GitHub", "forbind min vault til GitHub", or right after the user
  learned this skill from https://github.com/Tobbou/ObsidianRutine.
license: MIT
---

# ObsidianRutine — install and maintain the routine

You are installing a way of working, not just files: an Obsidian vault that is
also Claude Code's long-term memory. After this skill has run, Claude reads the
vault at the start of non-trivial work and writes new knowledge (architecture
decisions, hard-won fixes, runbooks, project notes) back into it at the end —
automatically, in every project, on every machine that clones the vault.

**Windows only.** The link machinery uses NTFS hardlinks and junctions and the
installer uses winget. On macOS/Linux, explain that and stop.

## 0. Locate the scripts

This skill ships `scripts/` and `template/` next to this file. Resolve the
skill root as the folder containing this SKILL.md and use
`<skillRoot>\scripts\`. If the scripts are not there (the user only pasted the
repo URL), get them:

```powershell
git clone https://github.com/Tobbou/ObsidianRutine "$env:TEMP\ObsidianRutine"
# scripts are then in: $env:TEMP\ObsidianRutine\skills\obsidian-rutine\scripts
```

All scripts are ASCII PowerShell 5.1 compatible. Run them as
`powershell -ExecutionPolicy Bypass -File <script> ...` (pwsh works too).

## 1. Install

Decide two things, then run. Ask only if the answer is not obvious from the
conversation — otherwise use the defaults and say what you chose:

| Setting | Default | Notes |
|---|---|---|
| Vault folder | `%USERPROFILE%\Obsidian` | Must be on the same drive as the user profile (hardlinks). Must be empty or not exist. |
| Context | `work` | `work` or `private` — which tree new notes go to on this machine. One-sentence explanation is enough. |

**Do not ask for a GitHub repo up front.** The routine is local-first: the vault
is created and committed locally, and connecting a remote is done later (step
3) because the installer cannot know which repo the user wants — if the user
already gave a URL to an *empty* repo, pass it as `-RepoUrl`.

```powershell
powershell -ExecutionPolicy Bypass -File "<scripts>\Install-ObsidianRutine.ps1" -VaultPath "<vault>" -Context <work|private>
```

The script needs no admin rights (git and Obsidian are per-user winget
installs). It never aborts on a single failure; it records the outcome and
continues, then prints a checklist. If winget is missing or an install fails,
relay the exact fix line it prints.

What it does, in order: prerequisites → vault scaffold from the template →
git init → download community plugins (Obsidian Git, Dataview, Templater,
Tasks) → `Setup-Machine.ps1` (adopts the user's existing `~/.claude/CLAUDE.md`
and `settings.json` into the vault, appends the vault-usage rule, hardlinks
them back, junctions the `vault` skill) → opens the vault in Obsidian → status
→ one commit (+ push if a remote exists).

## 2. Report what is missing — mandatory after every run

Run the status and read it as data:

```powershell
powershell -ExecutionPolicy Bypass -File "<scripts>\Get-RutineStatus.ps1" -VaultPath "<vault>" -AsJson
```

Present, in the user's language, a short checklist: what is in place (one
line), then every item with `Ok: false` (missing, with its `Fix`) and `Ok:
null` (manual step). Always spell out these three when they apply:

1. **No GitHub repo connected** — say *why* the installer could not do it (it
   does not know which repo), and ask for the URL of an **empty, private** repo
   when the user is ready (`gh repo create my-vault --private` creates one).
   Until then the vault is local-only; Obsidian Git still commits every 10
   minutes, push is off.
2. **Trust prompt in Obsidian** — on first open the user must click "Trust
   author and enable plugins" once. This cannot be pre-set from files.
3. **Claude Code login** if no credentials are present.

The same checklist is written to `<vault>\90-Meta\Setup-Status.md`, so both
the user and future Claude sessions can read it. Re-run the status any time
the user asks "what's missing" / "hvad mangler".

## 3. Connect the vault to the user's repo

When the user provides a repo URL:

```powershell
powershell -ExecutionPolicy Bypass -File "<scripts>\Connect-VaultRemote.ps1" -RepoUrl "<url>" -VaultPath "<vault>"
```

It adds/updates `origin`, pushes, and enables pushing in Obsidian Git. Then
re-run the status. If the push fails because the repo is not empty, explain
and ask for a fresh empty repo — never force-push, never merge unknown content.

## 4. Explain what the user now has (briefly, once)

- The **`vault` skill** is installed and the rule in their global `CLAUDE.md`
  tells Claude to read the vault at the start of non-trivial work and capture
  knowledge at the end. Nothing else to configure.
- **Obsidian**: folder structure (`Work/` and `Private/` trees, `50-Daily/`,
  `90-Meta/`), templates wired to Templater, daily notes in `50-Daily`, Obsidian
  Git auto-backup every 10 minutes.
- **Next machine**: clone the vault and run
  `90-Meta\Scripts\Setup-Machine.ps1 -Context work|private`; the runbook is
  `90-Meta\Claude\_README.md` and third-party skills/MCP servers are recorded
  in `90-Meta\Claude\skills-manifest.md`.

## 5. Maintenance triggers

| User asks | Do |
|---|---|
| status / what's missing | `Get-RutineStatus.ps1` (step 2) |
| repair / links broken / new project memory not in git | `<vault>\90-Meta\Claude\skills\vault\scripts\Test-VaultLinks.ps1 -Fix -Adopt` |
| update plugins | `Install-ObsidianPlugins.ps1 -VaultPath <vault> -Force` |
| connect / change remote | step 3 |
| move the vault | move the folder, then re-run `Setup-Machine.ps1` (links break on move) |

If the chosen folder exists, is not empty, and is not an ObsidianRutine vault,
the installer refuses. Suggest a new folder; existing notes can be moved into
the structure afterwards.

## Rules for the agent

- Never elevate (no admin prompts); never touch files outside the vault and
  `%USERPROFILE%\.claude\`.
- Never invent a repo URL; never commit or push anywhere but the vault repo.
- Summarise script output; keep the printed fix lines verbatim.
- After installing, read the vault's `CLAUDE.md` before writing notes into it —
  it holds the conventions the `vault` skill relies on.
