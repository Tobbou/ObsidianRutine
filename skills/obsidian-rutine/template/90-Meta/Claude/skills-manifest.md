---
type: meta
tags: [meta, claude, skills]
---

# Skills manifest — what is installed and how to reinstall it

Single source of truth for every Claude Code skill, plugin, and MCP server
across your machines. On a new machine, [[_README|the bootstrap runbook]] uses
this file to restore everything that does not travel with the vault
automatically. `Test-VaultLinks.ps1` checks the **Third-party skills** and
**MCP servers** tables below against what is actually installed.

**Keep it current:** whenever a skill is installed, removed, or adopted into
the vault, update the matching table in the same change. A stale manifest is a
bug. (The rule in your global `CLAUDE.md` makes Claude maintain this for you.)

## Own skills (vault-backed — install themselves)

These live in `90-Meta/Claude/skills/` and are junctioned into
`%USERPROFILE%\.claude\skills\` by `Setup-Machine.ps1`. Nothing to reinstall.

| Skill | Purpose |
|---|---|
| `vault` | Read/write this Obsidian vault correctly |

## Third-party skills (reinstall from source)

Group rows by source repo, one subsection per source. First column must be the
exact folder name in backticks — the self-test parses it. Example (delete when
you add real entries):

### Example source — https://github.com/someone/some-skills

Install: `npx skills add https://github.com/someone/some-skills`

| Skill | Notes |
|---|---|
| skill-name-here (use backticks on real rows) | why you installed it |

## Plugins (reinstall themselves)

Plugins registered in `settings.json` (vault-backed) via `enabledPlugins` +
`extraKnownMarketplaces` re-fetch themselves on a new machine — list them here
for completeness only.

| Plugin | Marketplace source |
|---|---|
| | |

## MCP servers (re-register per machine)

Stored in `%USERPROFILE%\.claude.json`, which is machine-local by design.
First column is the exact server name in backticks — the self-test checks each
against `~/.claude.json`. Record the full register command; never put secrets
in it (OAuth flows are interactive on first use).

| Server | Register command |
|---|---|
| | |

## Procedure: adding a new skill

- **Own skill:** create the folder directly in `90-Meta/Claude/skills/<name>/`
  and run `Test-VaultLinks.ps1 -Fix` to junction it into
  `%USERPROFILE%\.claude\skills\`. Add a row to the Own table above.
- **Third-party skill:** install it, then add a row to the matching source
  table above (create a new source section if it is a new origin) — in the
  same change. Record the install command, not just the repo.
- **Removing a skill:** delete the row too.
