# Vault conventions

This file is read by every AI coding agent working in this vault: Codex, Cursor,
GitHub Copilot, Amp, Devin/Windsurf and others read `AGENTS.md` natively; Claude
Code imports it from `CLAUDE.md`; Gemini CLI needs `AGENTS.md` added to its
`context.fileName` setting. It documents the conventions the agents rely on. If
you change a convention, update this file too - it is the single source of truth.

## Vault purpose

Three combined use cases:
1. **Project and task management** — active projects, deadlines, decisions
2. **Personal knowledge base (PKM)** — durable notes on concepts, research, books
3. **Work notes tied to codebases** — architecture, runbooks, post-mortems. "Codebase" covers git repos, low-code apps, scripts, spreadsheets with macros — anything you maintain code-like artefacts in.

## Work / Private split

Content lives in two parallel trees. **Which tree a note is in is its provenance** — there is no metadata field to keep in sync, and a misfiled note is visible in the path.

| Tree | Holds |
|---|---|
| `Work/` | Everything originating from work. |
| `Private/` | Everything originating from private machines and private work. |

**The split governs writing, not reading.** Search, link and draw on both trees freely — knowledge is worth having regardless of where it was learned. What the context decides is where *new* notes land.

**Which tree to write to:** read `%USERPROFILE%\.claude\machine.json`. `{"context":"private"}` means new notes go in `Private/`, `work` means `Work/`. If the file is missing, ask the user (and suggest re-running `90-Meta\Scripts\Setup-Machine.ps1`). If the user asks for the other tree, do that and don't ask again in that session.

If you only use the vault in one context, just pick one tree and stay in it — the other sits empty at no cost.

## Folder layout

Both trees use the identical skeleton:

| Folder | What goes here |
|---|---|
| `00-Inbox/` | Fast capture. Anything that doesn't have a home yet. Triage and move out regularly. |
| `10-Projects/` | Active projects with a defined outcome and end date. One subfolder per project. |
| `20-Areas/` | Ongoing responsibilities without an end date (health, finances, home, role at work). |
| `30-Knowledge/` | Durable PKM notes: concepts, research, book/article notes, reference material. |
| `40-Codebases/` | Notes about specific codebases. One subfolder per codebase. Distinguish kind via `platform:` in frontmatter, not by folder. |
| `99-Archive/` | Completed projects and notes worth keeping but out of sight. Preserve original folder when moving. |

Two folders sit at the vault root, outside both trees:

| Folder | Why it is not split |
|---|---|
| `50-Daily/` | A single day usually mixes work and private. Provenance goes in the note's `context:` frontmatter field instead. |
| `90-Meta/` | Infrastructure, not content — belongs to neither. It also **cannot move**: `90-Meta/Claude/` is the hardlink and junction target for `%USERPROFILE%\.claude\` on every machine, and Templater points at `90-Meta/Templates`. |

Each folder in `Work/` has a `_README.md` describing its scope. The `Private/` counterparts point back at those rather than duplicating the rules — keep it that way, one source of truth per convention.

## Naming

- Notes: natural, human-readable titles in Title Case. E.g. `Kubernetes Networking.md`, not `kubernetes-networking.md`. This is what `[[wiki-links]]` will display.
- Daily notes: ISO date, `2026-05-28.md`.
- Project folders: short project name in Title Case, e.g. `10-Projects/Vault Setup/`.
- Avoid characters that break filenames or wiki-links: `/ \ : * ? " < > |`.

## Frontmatter

Every non-trivial note starts with YAML frontmatter. Minimum:

```yaml
---
type: project | area | knowledge | codebase | daily | meeting | concept | template
status: active | on-hold | done | archived   # for projects only
platform: git | github | powershell | excel | lowcode | local | ...   # for codebases only
created: 2026-05-28
tags: [tag1, tag2]
---
```

Additional fields are fine. Keep field names lowercase and stable so Dataview
queries don't break.

For codebases, `platform:` is what tells you the kind. The folder
`40-Codebases/` mixes git repos, scripts, low-code apps, etc. — Dataview can
filter on `platform` when you need a kind-specific view.

## Links

- Prefer `[[wiki-links]]` over markdown links for internal references.
- Link liberally. A `[[link]]` to a non-existent note is fine — it marks the note as worth writing later.
- For ambiguous titles use a path: `[[Work/40-Codebases/my-codebase/Architecture]]`.
- For display text: `[[Kubernetes Networking|networking]]`.

## Tags

Use nested tags to scope:
- `#project/active`, `#project/on-hold`, `#project/done`
- `#area/health`, `#area/finance`
- `#codebase/<name>` for the codebase identity, `#codebase/git`, `#codebase/powershell`, etc. for platform
- `#source/book`, `#source/article`, `#source/podcast`
- `#status/draft`, `#status/needs-review`

Avoid tag explosion. If a tag is used fewer than 3 times, consider deleting it
or merging it into an existing tag.

## Templates

Live in `90-Meta/Templates/`. Available templates:
- `project.md` — new project
- `daily.md` — daily note
- `codebase-note.md` — note about a codebase
- `concept.md` — a PKM concept/knowledge note
- `meeting.md` — meeting notes

Wire these into the **Templater** community plugin when installed.

## When working in this vault

Defaults the agent follows unless told otherwise:
- Resolve the tree first (`machine.json`), then the folder. New notes go in `<Tree>/00-Inbox/` unless their home is obvious; let the user triage.
- When a project is finished, move its folder from `<Tree>/10-Projects/` to `<Tree>/99-Archive/10-Projects/` (preserve the original parent folder structure inside `99-Archive`). Archiving never moves a note between trees — provenance doesn't change.
- When asked "where should this go?", recommend a folder and explain why. If it belongs in the *other* tree than the machine's context, say so rather than filing it silently.
- Don't auto-rename existing notes; suggest renames and wait for confirmation (renames break wiki-links unless Obsidian updates them via the running app).
- Don't commit/push automatically — the user runs commits, or the Obsidian Git plugin does.

**Editing notes from a script:** never use `Get-Content`/`Set-Content` in Windows PowerShell 5.1. They assume Windows-1252 for BOM-less files and will silently corrupt every em-dash and every non-ASCII letter in the vault. Use `[System.IO.File]::ReadAllText/WriteAllText` with an explicit `UTF8Encoding($false)`, preserve any BOM the file already had, and keep the `.ps1` source itself pure ASCII — the script file is read with the same broken assumption.

**Editing anything in `90-Meta/Claude/`:** `CLAUDE.md`, `settings.json`, and the `hooks\*.ps1` scripts there are hardlinked to `%USERPROFILE%\.claude\`. Editing them with any tool that writes-and-renames — Claude Code's own file tools included — severs the link silently and the two copies drift. Verify with `fsutil hardlink list` after editing, and repair by re-running `90-Meta\Scripts\Setup-Machine.ps1`.

**Bulk-moving notes:** close Obsidian first. A running Obsidian rewrites wiki-links on filesystem moves at the same time as your script does, producing doubled prefixes, and Obsidian Git may auto-commit a half-finished state within minutes.
