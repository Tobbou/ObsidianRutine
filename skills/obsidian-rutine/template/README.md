# Obsidian Vault

Personal Obsidian vault, initialized from [ObsidianRutine](https://github.com/Tobbou/ObsidianRutine). Used for:

- Project and task management
- Personal knowledge base (PKM)
- Work notes tied to codebases
- **Claude Code's persistent state** (rules, settings, memory, skills) — the "AI brain"

## Sync

Versioned with git. Each commit is a snapshot of the vault. The **Obsidian Git**
community plugin can auto-commit and push on an interval — recommended, so
Claude's memory writes are swept into git automatically.

## Claude as co-pilot

This vault is designed to be worked on with Claude Code as a co-pilot. See
`AGENTS.md` (imported by `CLAUDE.md`) for the conventions the agents rely on: folder layout, frontmatter
fields, link style, and naming.

## The AI brain — restore Claude on a new machine

Beyond notes, this repo carries Claude Code's persistent state under
`90-Meta/Claude/`. Cloning the vault on a new machine restores the whole brain:

1. Follow **`90-Meta/Claude/_README.md`** — the bootstrap runbook. In short:
   run `90-Meta/Scripts/Setup-Machine.ps1 -Context work|private`, log in, then
   let Claude do the rest ("Follow the bootstrap in 90-Meta/Claude/_README.md").
2. Third-party skills and MCP servers don't live in the repo; they are
   reinstalled from **`90-Meta/Claude/skills-manifest.md`**.
3. Verify with `90-Meta/Claude/skills/vault/scripts/Test-VaultLinks.ps1`.

## What is and isn't versioned

See `.gitignore`. Settings, installed plugins, and themes are versioned.
Per-machine workspace state (open tabs, pane layout), caches, and anything
credential-shaped are not.
