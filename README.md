# ObsidianRutine

**Teach your AI agent one skill, and it sets up your whole knowledge routine** — Obsidian installed and configured, a vault with a proven structure, git backup, and Claude Code wired in so that it keeps pushing new knowledge and project notes into the vault from every project you work on.

> **Lær denne skill: https://github.com/Tobbou/ObsidianRutine**
> *(Learn this skill: …)* — that sentence, given to Claude Code, is the whole installation.

## What you say, what happens

**1. Learn the skill** — pick one:

```powershell
# a) the skills CLI (works for Claude Code and other agents)
npx skills add Tobbou/ObsidianRutine

# b) as a Claude Code plugin
/plugin marketplace add Tobbou/ObsidianRutine
/plugin install obsidian-rutine@obsidian-rutine

# c) no tooling at all - just tell Claude Code:
#    "Learn this skill and install it: https://github.com/Tobbou/ObsidianRutine"
#    (it clones the repo and follows skills/obsidian-rutine/SKILL.md)
```

**2. Say the word** — in Claude Code, in any folder:

> *Install ObsidianRutine* — or in Danish: *Sæt ObsidianRutine op*

Claude picks sensible defaults (vault at `%USERPROFILE%\Obsidian`, context `work`), runs the installer, and reports back.

**3. Read the checklist.** Claude ends with exactly what is in place and what is still yours to do. Typically:

| Still to do | Why the installer could not | How |
|---|---|---|
| Connect a GitHub repo | It cannot know which repo your vault should sync to | Create an **empty private** repo (`gh repo create my-vault --private`), then tell Claude the URL — or run `Connect-VaultRemote.ps1 -RepoUrl <url>` |
| Trust community plugins in Obsidian | Obsidian asks once per vault; no file can pre-approve it | Click **"Trust author and enable plugins"** when Obsidian opens |
| Log in to Claude Code | Credentials are per machine and never scripted | Start `claude` once |

Everything else is done — and the same checklist lives in your vault at `90-Meta/Setup-Status.md`, so you (and Claude, next time) can always ask *"what's missing?"*.

## What gets installed

- **Obsidian** and **git**, if missing — per-user winget installs, **no admin rights needed**.
- **A vault** with a structure that has held up in daily use: two parallel trees (`Work/` and `Private/`) with `00-Inbox`, `10-Projects`, `20-Areas`, `30-Knowledge`, `40-Codebases`, `99-Archive`; `50-Daily/` for daily notes; `90-Meta/` for templates and machinery. Every folder explains itself in a `_README.md`.
- **Obsidian configured**: community plugins downloaded and enabled (**Obsidian Git** auto-backup every 10 minutes, **Dataview**, **Templater** wired to the templates, **Tasks**), daily notes in `50-Daily`, templates for projects, concepts, codebase notes, meetings and daily notes.
- **Git**: the vault is a repository from the first minute, committed locally. Push turns on the moment you connect a remote.
- **Claude Code wired into the vault**: your global `CLAUDE.md` and `settings.json` are adopted into the vault (nothing overwritten) and hardlinked back, Claude's per-project memory is junctioned into the vault, and the **`vault` skill** is installed — the piece that makes Claude read the vault at the start of non-trivial work and write architecture decisions, hard-won fixes, runbooks and project notes back into it at the end. Automatically. In every project.
- **A reinstall manifest** (`90-Meta/Claude/skills-manifest.md`) for the things that cannot live in a repo — third-party skills, MCP servers — and a self-test (`Test-VaultLinks.ps1`) that checks it.

Because Claude's state now lives in *your* vault repo, a new machine is: clone the vault, run `90-Meta\Scripts\Setup-Machine.ps1`, done. The runbook is in `90-Meta/Claude/_README.md`.

## Requirements

- **Windows 10/11.** The link machinery uses NTFS hardlinks and junctions, and the installer uses winget. (A macOS/Linux port would need symlinks — contributions welcome.)
- **Claude Code** — that is what learns the skill and runs the installation. (You can also run the scripts yourself, see below.)
- Internet access for winget and the plugin downloads. Vault folder on the same drive as your user profile (hardlink requirement; the default always is).
- To *learn* the skill from this repo you need read access to it. While the repo is private, that means the owner and collaborators — the skills CLI uses your git credentials, then GitHub CLI (`gh auth login`), then SSH, so access you already have just works. Make the repo public to share more widely.
- If `winget` is missing (rare on Windows 11), repair it first: `Install-Module Microsoft.WinGet.Client -Scope CurrentUser -Force; Repair-WinGetPackageManager -Force -Latest` — or install git and Obsidian by hand and re-run; the installer detects them.

## Other AI agents

The routine is not Claude-only. The vault's conventions live in `AGENTS.md` at the vault root — the file Codex, Cursor, GitHub Copilot, Amp, Devin/Windsurf, Zed and others read natively (Claude Code imports it via `CLAUDE.md`; Gemini CLI needs `AGENTS.md` added to `context.fileName`). The installer skill itself follows the open Agent Skills format, so `npx skills add Tobbou/ObsidianRutine -a codex` (or any agent the skills CLI supports) installs it there too; the scripts are plain PowerShell and run the same way. What stays Claude Code-specific is the deep integration — hardlinking `~/.claude` into the vault and the `vault` skill's automatic capture — because that is where Claude keeps its state.

## Without an agent

The scripts are plain PowerShell 5.1 and run on their own:

```powershell
git clone https://github.com/Tobbou/ObsidianRutine "$env:TEMP\ObsidianRutine"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\ObsidianRutine\skills\obsidian-rutine\scripts\Install-ObsidianRutine.ps1" -Context work   # or: private
# later, when you have an empty repo for the vault:
powershell -ExecutionPolicy Bypass -File "$env:TEMP\ObsidianRutine\skills\obsidian-rutine\scripts\Connect-VaultRemote.ps1" -RepoUrl git@github.com:you/my-vault.git
# any time:
powershell -ExecutionPolicy Bypass -File "$env:TEMP\ObsidianRutine\skills\obsidian-rutine\scripts\Get-RutineStatus.ps1"
```

`Install-ObsidianRutine.ps1` accepts `-VaultPath`, `-Context work|private`, `-RepoUrl` (an empty repo to clone first), `-SkipPrerequisites`, `-SkipPlugins`, `-NoOpen`. It is idempotent: re-running on an existing vault repairs links, fetches missing plugins and commits whatever changed.

## Repository layout

```
skills/obsidian-rutine/
  SKILL.md              the installer skill Claude follows
  scripts/              Install-ObsidianRutine.ps1, Install-ObsidianPlugins.ps1,
                        Connect-VaultRemote.ps1, Get-RutineStatus.ps1
  template/             the vault that gets created (folders, templates, .obsidian settings,
                        90-Meta with Setup-Machine.ps1 and the vault skill)
.claude-plugin/         marketplace + plugin manifests for /plugin install
Docs/Architecture.md    design: local-first, record-don't-abort, the link machinery, foot-guns
```

The vault template is shared with [obsidian-claude-starter](https://github.com/Tobbou/obsidian-claude-starter) — the same brain, installed by a prompting PowerShell script instead of an agent.

## Security notes

- The scripts touch only the vault folder and `%USERPROFILE%\.claude\`, never elevate, and contain no credentials. Read them before running; they are short.
- Your vault repo will hold your notes, Claude's memory of your projects and your Claude settings. **Keep it private.**
- Plugins are downloaded from their official GitHub releases at install time; nothing is vendored here.

## License

MIT — see [LICENSE](LICENSE).
