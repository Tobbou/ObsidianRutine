# Global preferences

## Obsidian vault — shared long-term memory across projects

An Obsidian vault (path recorded in `%USERPROFILE%\.claude\machine.json` as `vaultPath`) is the
durable, cross-project knowledge store. Claude's built-in memory is per-directory and starts cold in
every new codebase; the vault is the deliberate store that carries knowledge between projects and
machines.

**Invoke the `vault` skill whenever you read from or write to it.** That skill owns the operational
detail — the vault-vs-per-project-memory decision, `Work/` vs `Private/` tree resolution, folder
placement, templates, frontmatter, wiki-links, and the encoding + hardlink foot-guns. Don't
re-derive any of it from memory.

**What is worth capturing:** architecture decisions and the reasoning behind them; non-obvious bug
fixes that cost real effort to find; cross-cutting learnings useful on future projects; post-mortems,
runbooks, decisions to revisit later; and a codebase overview note for any project worked on more
than once.

**When:**
- **At the start of non-trivial code work in any codebase:** read
  `<Tree>/40-Codebases/<codebase-name>/` for context, and search both trees' `30-Knowledge/` if the
  task touches a documented concept. Do this proactively — don't wait to be asked.
- **At the end of non-trivial code work:** write the capture on your own initiative. Autonomous
  writes are authorized. Mention in chat what you wrote and where, so it can be reviewed.
- **Skip it when the work is trivial** — typo fixes, small refactors, single-file edits easily
  re-derived from the code, or anything the repo already records. Vault noise dilutes signal;
  restraint is part of the rule.
- Work **inside** the vault directory itself is governed by the vault's own local `AGENTS.md` (imported by its `CLAUDE.md`).

## Skills, plugins, MCP: keep the AI brain reinstallable via the vault

Claude's persistent state (the "AI brain") must survive a machine switch. The vault's
`90-Meta/Claude/` is the single source of truth, and `90-Meta/Claude/_README.md` is the bootstrap
runbook that rebuilds everything on a new machine. Anything that cannot travel with the vault must
be recorded in `90-Meta/Claude/skills-manifest.md` so it can be reinstalled from there.

**How to apply:**
- **Own skills** (authored by/for the user) are created directly in `90-Meta/Claude/skills/<name>/`
  — never only in `%USERPROFILE%\.claude\skills\` — and junctioned into place with
  `Test-VaultLinks.ps1 -Fix` (in the vault skill's scripts folder). Add a row to the manifest's
  Own-skills table.
- **Third-party skills:** after installing one, add a row (source repo + install command) to the
  matching table in `skills-manifest.md` in the same change. Removing a skill deletes the row.
- **MCP servers:** `~/.claude.json` is machine-local; record every `claude mcp add` command in the
  manifest's MCP table when registering a new server.
- `Test-VaultLinks.ps1` verifies all of it (hardlinks, junctions, manifest vs installed skills,
  MCP registrations) — run it after any change to the brain's structure.
