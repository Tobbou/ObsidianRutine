---
name: vault
description: >-
  Read from and write to the user's Obsidian vault correctly — decide vault vs
  per-project memory, resolve the Work/ vs Private/ tree, search both trees
  before writing, place the note in the right folder with the right template
  and frontmatter, and avoid the encoding + hardlink foot-guns. Use at the
  START of non-trivial code work (read the existing codebase/concept notes)
  and at the END (capture architecture decisions, hard-won fixes, post-mortems,
  runbooks). Also for "save this to the vault", "write it down for next time",
  "what do we know about X", "create a codebase note", "where should this note
  go", "check the vault".
---

# Obsidian vault — read and write

The vault is the durable, cross-project knowledge store. Claude's built-in
memory is per-directory and starts cold in every new codebase; the vault is
what carries architecture decisions and hard-won fixes between projects and
between machines.

**Resolve the vault path first:** read `%USERPROFILE%\.claude\machine.json` —
its `vaultPath` field is the vault root (`<Vault>` below). If the file is
missing, ask the user where the vault is and suggest re-running
`90-Meta\Scripts\Setup-Machine.ps1`.

**The vault's own `AGENTS.md` (imported by its `CLAUDE.md`) is the source of truth for conventions.** The
essentials are inlined below so a session in another project does not need a
second read. If anything here disagrees with `<Vault>\CLAUDE.md`, that file
wins — and fix this one.

## 1. Which memory does this belong in?

Two stores, one boundary. Getting this wrong is the most common failure:
durable knowledge written to a per-project memory is invisible in every other
project, and session trivia written to the vault is noise that dilutes signal.

| | Per-project `memory/` | The vault |
|---|---|---|
| **Path** | `%USERPROFILE%\.claude\projects\<slug>\memory\` | `<Tree>\30-Knowledge\`, `<Tree>\40-Codebases\`, ... |
| **Scope** | This one directory | Every project, every machine |
| **Holds** | Who the user is, feedback on how to work, current project state, pointers | Architecture decisions + *why*, non-obvious fixes, post-mortems, runbooks, concepts, codebase overviews |
| **Shape** | One fact per file + `MEMORY.md` index | A real note, prose, wiki-linked |
| **Test** | "I need this next time I open *this* folder" | "I would want this in two years, in a different repo" |

Both are git-backed through the vault (`90-Meta\Claude\projects\<slug>\memory\`
is junctioned into `~/.claude`), so this is a placement decision, not a
durability one.

**Write to neither** when the work is trivial: typo fixes, small refactors,
single-file edits easily re-derived from the code, or anything the repo already
records (code structure, git history, docs). Restraint is part of the rule.

## 2. Resolve the tree (before any write)

Content lives in two parallel trees with identical skeletons. **Which tree a
note is in *is* its provenance** — there is no metadata field to keep in sync.

```powershell
Get-Content "$env:USERPROFILE\.claude\machine.json" -Raw
```

- `{"context":"work"}` → new notes go in `Work\`
- `{"context":"private"}` → new notes go in `Private\`
- File missing → ask the user rather than guessing.
- If the user asks for the other tree, do that and don't ask again this session.

**The split governs writing, not reading.** Always search *both* trees —
knowledge is worth having regardless of where it was learned. If a note belongs
in the other tree than the machine's context, say so rather than filing it
silently.

## 3. Read before you write

Two things, always, and in this order:

1. **Existing notes on this subject.** Search both trees, not just the obvious
   folder:
   ```
   Glob:  {Work,Private}/40-Codebases/<codebase-name>/**/*.md
   Grep:  <concept or error message>   path=<Vault>
   ```
   An existing note gets **updated**, not duplicated. One fact, one home.
2. **At the start of non-trivial code work**, read
   `<Tree>\40-Codebases\<codebase-name>\` for context even if the task did not
   mention the vault. That is the whole point of having it.

## 4. Where it goes

| Folder | What goes here |
|---|---|
| `<Tree>\00-Inbox\` | Fast capture with no obvious home. Default when unsure — let the user triage. |
| `<Tree>\10-Projects\<Project>\` | Active project with a defined outcome and end date |
| `<Tree>\20-Areas\` | Ongoing responsibility, no end date |
| `<Tree>\30-Knowledge\<Concept>.md` | Durable PKM: concepts, research, book/article notes |
| `<Tree>\40-Codebases\<codebase-name>\<Note Title>.md` | Notes about one codebase — git repo, script, low-code app |
| `<Tree>\99-Archive\` | Finished work worth keeping, original folder structure preserved |
| `50-Daily\<ISO-date>.md` | **Vault root, not split** — a day mixes both. Provenance goes in `context:` frontmatter. |
| `90-Meta\` | Infrastructure, not content. **Cannot move** — it is the link target for `~/.claude`. |

Naming: natural **Title Case** (`Kubernetes Networking.md`, not
`kubernetes-networking.md`) — it is what `[[wiki-links]]` display. Avoid
`/ \ : * ? " < > |`.

## 5. Frontmatter, links, tags

Minimum on every non-trivial note:

```yaml
---
type: project | area | knowledge | codebase | daily | meeting | concept | template
status: active | on-hold | done | archived   # projects only
platform: git | github | powershell | excel | lowcode | local   # codebases only
created: 2026-01-01
tags: [tag1, tag2]
---
```

Keep field names lowercase and stable so Dataview queries don't break.
`platform:` is what makes `40-Codebases\` filterable by kind — never omit it on
a codebase note.

- Prefer `[[wiki-links]]` over markdown links internally. **Link liberally** —
  a link to a note that doesn't exist yet is a feature, it marks the note as
  worth writing.
- Disambiguate with a path when titles collide:
  `[[Work/40-Codebases/my-codebase/Architecture]]`.
- Nested tags: `#project/active`, `#codebase/<name>`, `#source/book`,
  `#status/draft`. A tag used fewer than 3 times should be merged or dropped.
- Templates live in `90-Meta\Templates\` (`project`, `daily`, `codebase-note`,
  `concept`, `meeting`). They contain Templater tags; when writing from a
  script or tool, substitute real values — do not leave the tags in the file.

Use the bundled helper to get folder + template + frontmatter right in one step:

```powershell
& "<Vault>\90-Meta\Claude\skills\vault\scripts\New-VaultNote.ps1" `
    -Kind codebase -Title "Signing Pipeline" -Codebase MyApp -Platform git -WhatIf
```

Drop `-WhatIf` to create it. It resolves the tree itself, refuses to overwrite,
and writes UTF-8 without BOM. Then open the file and write the actual content —
the script only scaffolds.

## 6. Writing mechanics — the foot-guns

These each cost real time to discover. They are the reason this skill exists
rather than a paragraph of rules.

- **Never `Get-Content`/`Set-Content` on a vault note in Windows PowerShell
  5.1.** They assume Windows-1252 for BOM-less files and silently corrupt every
  em-dash and every non-ASCII letter. Use:
  ```powershell
  $enc = New-Object System.Text.UTF8Encoding($false)   # $true only if the file already had a BOM
  $text = [System.IO.File]::ReadAllText($path)
  [System.IO.File]::WriteAllText($path, $text, $enc)
  ```
  Keep any `.ps1` you write for this **pure ASCII** — the script file is read
  with the same broken assumption. Claude's own Read/Write/Edit tools are UTF-8
  safe; this rule is about shell commands.
- **Don't auto-commit.** The Obsidian Git plugin auto-syncs on an interval.
  Commit manually only when something is actually wrong, and say so.
- **Close Obsidian before bulk-moving notes.** A running Obsidian rewrites
  wiki-links on filesystem moves at the same time as your script, producing
  doubled path prefixes — and Obsidian Git may auto-commit the half-finished
  state.
- **Don't auto-rename existing notes.** Renames break wiki-links unless the
  running Obsidian app updates them. Suggest the rename and wait.
- **Archiving never moves a note between trees.** Provenance doesn't change.
  `Work\10-Projects\X\` → `Work\99-Archive\10-Projects\X\`.

## 7. `90-Meta\Claude\` is linked, not copied

`90-Meta\Claude\CLAUDE.md`, `settings.json`, and each `hooks\<name>.ps1` are
**hardlinked** to `%USERPROFILE%\.claude\`, and each
`90-Meta\Claude\projects\<slug>\memory\` and `90-Meta\Claude\skills\<name>\` is
**junctioned** there. Editing them is editing live Claude config.

**Any tool that writes-and-renames severs a hardlink silently** — Claude Code's
own Write/Edit included — and the two copies then drift without any error. So
after editing `CLAUDE.md`, `settings.json`, or a hook script, either write in
place with `[System.IO.File]::WriteAllText` (same inode, link survives) or
verify and repair:

```powershell
& "<Vault>\90-Meta\Claude\skills\vault\scripts\Test-VaultLinks.ps1"
```

That reports every link's state, flags memory dirs that exist locally but not
in the vault (those are **not** backed up — a new project's memory starts
local), and checks `skills-manifest.md` against what is installed. `-Adopt`
moves local-only memory into the vault; `-Fix` recreates missing junctions.
Repair of a broken hardlink is `90-Meta\Scripts\Setup-Machine.ps1 -Context
work|private`, which also sets `machine.json` on a new machine.

## 8. Finish the job

- Write the note **on your own initiative** at the end of non-trivial work —
  autonomous writes are authorized. Then **say in chat what you wrote and
  where**, so it can be reviewed.
- A hard-won gotcha belongs in **both** the repo's docs (for colleagues) and
  the vault (for future sessions). Cross-link instead of duplicating the
  detail.
- When a new skill or MCP server is installed as part of the work, update
  `90-Meta\Claude\skills-manifest.md` in the same change.
