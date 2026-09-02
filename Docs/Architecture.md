# Architecture — ObsidianRutine

ObsidianRutine packages a way of working as a **skill**: a Claude Code agent learns the repo, then performs the installation itself and tells the user what is left. The parts:

| Part | Where | Role |
|---|---|---|
| Installer skill | `skills/obsidian-rutine/SKILL.md` | What the agent does: defaults, which script to run, how to report what is missing, maintenance triggers, safety rules |
| Scripts | `skills/obsidian-rutine/scripts/` | Deterministic work in PowerShell 5.1: `Install-ObsidianRutine.ps1` (end to end), `Install-ObsidianPlugins.ps1`, `Connect-VaultRemote.ps1`, `Get-RutineStatus.ps1` |
| Vault template | `skills/obsidian-rutine/template/` | The vault that gets created: folder trees, templates, `.obsidian/` settings, `90-Meta/` with the Claude link machinery and the `vault` skill |

The scripts and template live *inside* the skill folder so they travel with it when a skills installer copies the skill into `~/.claude/skills/`. The agent never has to reconstruct the vault file by file; it runs one script and reads one JSON status.

## Design decisions specific to ObsidianRutine

- **Local-first.** No GitHub repo is needed to start. The installer cannot know which repository the user wants, so it creates and commits the vault locally, keeps Obsidian Git in commit-only mode (`disablePush: true`), and reports "no remote connected" as the primary open item. `Connect-VaultRemote.ps1` closes it later and flips push on.
- **Record, don't abort.** Every step records its outcome and continues. A machine without winget, offline plugin downloads, or a missing git identity still ends with a usable partial vault and a precise to-do list, printed *and* written to `90-Meta/Setup-Status.md` so the next Claude session can read it.
- **No elevation.** Git and Obsidian are per-user winget installs. Machine-scope installs are out of scope by design; on managed machines standard users often cannot elevate at all.
- **Plugins are downloaded, not vendored.** `Install-ObsidianPlugins.ps1` fetches the latest release assets (`main.js`, `manifest.json`, `styles.css`) of Obsidian Git, Dataview, Templater and Tasks from GitHub. Their settings (`data.json`) ship with the template. Committing the downloaded plugin files into the user's vault is normal Obsidian practice and makes the vault reproducible on the next machine.
- **One commit per run.** Committing happens last, after plugins, links and status, so the first commit is the complete vault and re-runs produce a single "update setup" commit.
- **Adopt, never overwrite.** `Setup-Machine.ps1` adopts the user's existing `~/.claude/CLAUDE.md` and `settings.json` into the vault on first run and appends the vault-usage rule; only a user with no `CLAUDE.md` gets the template's.
- **Vault registration is automated when Obsidian is closed.** Obsidian keeps its vault list in `%APPDATA%\obsidian\obsidian.json` and reads it only at startup, so the installer adds the vault there (`{"<16-hex id>": {"path", "ts", "open": true}}`) when no Obsidian process is running, then launches Obsidian. If Obsidian is running, it falls back to the `obsidian://open?path=` URI and the status report tells the user to use "Open folder as vault".
- **Conventions live in `AGENTS.md`, not only `CLAUDE.md`.** The vault's `AGENTS.md` is the agent-neutral conventions file read natively by Codex, Cursor, GitHub Copilot, Amp, Devin/Windsurf and others; the vault's `CLAUDE.md` is a stub that imports it (`@AGENTS.md`). One source of truth, every agent.
- **The trust prompt stays manual.** Obsidian asks once per vault to trust community plugins; there is no file-based way to pre-approve it, so the status report lists it as a manual step rather than pretending.

## The brain architecture (shared with the vault template)

The rest of this document describes the link architecture the template installs — identical to the [obsidian-claude-starter](https://github.com/Tobbou/obsidian-claude-starter) design.


## The problem this solves

Claude Code keeps its persistent state — global rules (`CLAUDE.md`), settings, hook scripts, per-project memory, skills — in `%USERPROFILE%\.claude\`. That directory is machine-local: switch machines and Claude starts cold; reinstall Windows and everything is gone. Meanwhile your Obsidian vault is already a git-versioned knowledge store that follows you everywhere.

This starter merges the two: **the vault repo becomes the single source of truth for both your notes and Claude's state**, and `%USERPROFILE%\.claude\` becomes nothing but filesystem links into it.

## The link map

```
%USERPROFILE%\.claude\                       <vault>\90-Meta\Claude\
├── CLAUDE.md              ── hardlink ──►   ├── CLAUDE.md
├── settings.json          ── hardlink ──►   ├── settings.json
├── hooks\
│   └── <name>.ps1         ── hardlink ──►   ├── hooks\<name>.ps1        (one per file)
├── skills\
│   └── <name>\            ── junction ──►   ├── skills\<name>\          (your own skills)
└── projects\
    └── <slug>\memory\     ── junction ──►   └── projects\<slug>\memory\ (Claude's memory)
```

Both directions are live: edit a file in the vault and Claude sees it immediately; Claude writes memory and it lands in the repo, swept up by the next commit (the Obsidian Git plugin auto-commits on an interval if you enable it).

**Why hardlinks for files and junctions for directories?** NTFS hardlinks only work for files and only within one volume (hence the same-drive requirement). Junctions are the directory equivalent that works without admin rights. Symlinks would need Developer Mode or elevation on Windows; hardlinks and junctions need neither.

## What deliberately stays machine-local

Not everything should travel. These never enter the repo:

| Local path | Why it stays local |
|---|---|
| `~/.claude/.credentials.json` | Auth tokens. Never in version control. The template `.gitignore` also blocks credential files defensively. |
| `~/.claude/machine.json` | Declares THIS machine's context (`work`/`private`) and vault path — per-machine by definition. Recreated by `Setup-Machine.ps1`. |
| `~/.claude/projects/<slug>/*.jsonl` | Full session transcripts — megabytes each, per-machine. Only the `memory/` subfolder is linked. |
| `~/.claude/cache`, `sessions`, `shell-snapshots`, ... | Ephemeral runtime state. |
| `~/.claude/plugins/` | Regenerated automatically from `settings.json` (`enabledPlugins` + `extraKnownMarketplaces`) — plugins reinstall themselves. |
| `~/.claude.json` (the FILE, next to the folder) | Machine-local Claude Code state, including MCP server registrations — re-register from the manifest. |

## The manifest: what can't travel gets a reinstall recipe

Third-party skills are other people's code with their own upstreams — vendoring them into your vault would freeze them and blur licensing. MCP registrations live in a machine-local file. Both are instead **recorded** in `90-Meta/Claude/skills-manifest.md`: name, source repo, exact install/register command.

The contract has three parts:

1. **Own skills** live in `90-Meta/Claude/skills/` (vault-backed, auto-linked — nothing to record beyond a row for completeness).
2. **Third-party skills and MCP servers** get a manifest row *in the same change* that installs them. The rule appended to your global `CLAUDE.md` makes Claude maintain this for you.
3. **`Test-VaultLinks.ps1` enforces it**: it warns about manifest entries that aren't installed *and* installed skills missing from the manifest, and checks each manifest MCP server against `~/.claude.json`.

## The two trees: Work/ and Private/

All content lives in one of two parallel trees with identical folder skeletons. **Which tree a note is in is its provenance** — no metadata to maintain, and a misfiled note is visible in its path. Each machine declares its context once (`machine.json`, written by `Setup-Machine.ps1`), and new notes land in that tree. Reading, searching, and linking span both trees freely; only *writing* is routed.

The folder skeleton inside each tree (numbers keep the sort order stable):

| Folder | Holds |
|---|---|
| `00-Inbox/` | Fast capture, triaged out regularly |
| `10-Projects/` | Active projects with an outcome and an end date |
| `20-Areas/` | Ongoing responsibilities without an end date |
| `30-Knowledge/` | Durable concepts, research, reference notes |
| `40-Codebases/` | Notes about specific codebases — one subfolder per codebase |
| `99-Archive/` | Finished work, original structure preserved |

`50-Daily/` and `90-Meta/` sit at the vault root outside both trees: a day mixes work and private (provenance goes in the note's `context:` field), and `90-Meta/` is infrastructure — it is also the link target, so it can never move.

## The vault skill

`90-Meta/Claude/skills/vault/` is what makes the brain *learn*. It teaches Claude:

- **The placement decision** — per-project memory (facts about one repo: "next time I open this folder") vs the vault (knowledge worth having in two years, in a different repo). Both are git-backed; the decision is about where knowledge is findable.
- **When to write** — proactively at the end of non-trivial work: architecture decisions and the *why*, bug fixes that cost real effort, post-mortems, runbooks, codebase overviews. And when *not* to: trivia and anything the repo already records.
- **When to read** — at the start of work in any codebase: check `40-Codebases/<name>/` and search `30-Knowledge/` before re-deriving anything.
- **The mechanics** — templates, frontmatter, wiki-links, tree resolution, and the encoding/link foot-guns below.

The trigger ("do this at the start and end of work") lives in the section appended to your global `CLAUDE.md` — a skill can't fire on its own, so the always-loaded rule points at it.

## Foot-guns (learned the hard way)

- **Write-and-rename severs hardlinks silently.** Most editors — and Claude Code's own Write/Edit tools — save by writing a temp file and renaming it over the original. That replaces the inode, the hardlink is gone, and the two copies drift with no error. `Test-VaultLinks.ps1` detects this and reports **which side is newer**; repair is copy-newer-over-older, then re-run `Setup-Machine.ps1`. Scripts that edit linked files in place should use `[System.IO.File]::WriteAllText` (same inode, link survives).
- **Windows PowerShell 5.1 corrupts UTF-8 without BOM.** `Get-Content`/`Set-Content` assume Windows-1252 for BOM-less files and silently mangle em-dashes and non-ASCII letters. All scripts here use `[System.IO.File]::ReadAllText/WriteAllText` with explicit UTF-8, and the `.ps1` sources are pure ASCII for the same reason.
- **Junctions don't survive network shares or OneDrive.** Keep the vault on a local NTFS volume, same drive as the profile.
- **Moving the vault breaks every link.** The data is safe (it's all in the vault), but `~/.claude` points at dead paths. Re-run `Setup-Machine.ps1` after a move.
- **A running Obsidian rewrites wiki-links during bulk file moves** — close it before moving many notes from a script, or the two writers race.

## Script inventory

| Script | Role |
|---|---|
| `Install-ObsidianRutine.ps1` (skill scripts) | First-machine bootstrap: clone your repo, copy template, commit/push, run Setup-Machine |
| `90-Meta/Scripts/Setup-Machine.ps1` | Idempotent link (re)builder + adopter. First run adopts your existing `CLAUDE.md`/`settings.json` into the vault; every run adopts local-only project memory into git |
| `90-Meta/Claude/skills/vault/scripts/Test-VaultLinks.ps1` | Read-only self-test (with `-Fix`/`-Adopt` repair modes): links, junctions, local-only memory, manifest vs installed |
| `90-Meta/Claude/skills/vault/scripts/New-VaultNote.ps1` | Scaffold a note in the right tree/folder from the right template, Templater tags substituted |
