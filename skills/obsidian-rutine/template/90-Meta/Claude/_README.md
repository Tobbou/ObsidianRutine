---
type: meta
tags: [meta, claude]
---

# Claude config — single source of truth

This folder is the canonical location for Claude Code's persistent state for this user — the "AI brain". The actual files live here in the vault; the original `%USERPROFILE%\.claude\` paths are filesystem links that point back here.

This means:
- Editing a file here = Claude Code sees the change immediately.
- Editing a file via the `.claude\` path = it's written here.
- Vault git backup includes Claude's config, memory, hooks, and own skills.
- Switching to a new machine = clone vault, run the bootstrap below, and Claude Code picks up the same state.

## What's here

| Path | Contains | Link type |
|---|---|---|
| `CLAUDE.md` | Global rules for all Claude Code sessions (adopted from your existing file on first setup) | Hardlink at `%USERPROFILE%\.claude\CLAUDE.md` |
| `settings.json` | Claude Code settings (permissions, hooks config, enabled plugins + marketplaces, model) | Hardlink at `%USERPROFILE%\.claude\settings.json` |
| `hooks\<name>.ps1` | Hook scripts referenced by `settings.json` | Hardlink per file at `%USERPROFILE%\.claude\hooks\<name>.ps1` |
| `skills\<name>\` | Own skills (starts with `vault`) | Junction at `%USERPROFILE%\.claude\skills\<name>\` |
| `projects\<slug>\memory\` | Per-project memory (one folder per project Claude has worked in) | Junction at `%USERPROFILE%\.claude\projects\<slug>\memory\` |
| `skills-manifest.md` | Reinstall manifest: third-party skills, plugins, MCP servers | Plain file (no link) |
| `CLAUDE.vault-section.md` | The vault-usage rule appended to / seeding your global `CLAUDE.md` on first setup | Plain file (no link) |

`<slug>` is the project-path slug Claude Code uses, e.g. `c--Projects-MyApp` for `C:\Projects\MyApp`.

Third-party skills are deliberately NOT in the vault — they are other people's code with their own upstreams. [[skills-manifest]] records where each one came from and how to reinstall it, and is the file to update whenever a skill is added or removed.

## What is deliberately NOT here

These stay local in `%USERPROFILE%\.claude\` and never enter the vault:

- `.credentials.json` — auth tokens. Never in version control.
- `machine.json` — per-machine by definition (declares the Work/Private context and the vault path); recreated by `Setup-Machine.ps1`.
- `projects\<slug>\*.jsonl` — full session transcripts. Per-machine, can be megabytes each.
- `cache\`, `sessions\`, `shell-snapshots\`, `file-history\`, `backups\`, `telemetry\`, `session-env\`, `ide\` — ephemeral runtime state.
- `mcp-needs-auth-cache.json`, `policy-limits.json`, `.last-cleanup`, `history.jsonl` — runtime/local state.
- `plugins\` — marketplace registry; regenerated automatically from `settings.json` (`enabledPlugins` + `extraKnownMarketplaces`).
- `%USERPROFILE%\.claude.json` (note: the FILE next to the `.claude` folder) — machine-local Claude Code state, including MCP server registrations. Re-register MCP servers from [[skills-manifest]].

A defensive gitignore rule in the vault root also blocks `**/.credentials.json` from being committed even if it accidentally appears anywhere.

## New machine bootstrap

Goal: from empty machine to "Claude works exactly like on the old machine". Steps 1-4 are manual; from step 5 on, Claude can do the rest — open Claude Code in the vault and say: *"Follow the bootstrap in 90-Meta/Claude/_README.md"*.

1. **Prerequisites:** install git, Obsidian, and Claude Code. Vault and `%USERPROFILE%` must be on the same volume (hardlinks require it).
2. **Clone the vault:**
   ```powershell
   git clone <your-repo-url> "$env:USERPROFILE\Obsidian"
   ```
3. **Run the setup script** (idempotent — safe to re-run any time):
   ```powershell
   powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Obsidian\90-Meta\Scripts\Setup-Machine.ps1" -Context work   # or: private
   ```
   This writes `machine.json`, hardlinks `CLAUDE.md` + `settings.json` + hook scripts, and junctions every project memory dir and every vault-backed skill.
4. **Log in:** start Claude Code and log in (regenerates `.credentials.json`). Open the vault in Obsidian and accept "Trust author and enable plugins".
5. **Re-register MCP servers** — run the commands from the *MCP servers* table in [[skills-manifest]].
6. **Reinstall third-party skills** — follow the per-source install commands in [[skills-manifest]].
7. **Verify** — run the self-test and fix anything it flags:
   ```powershell
   powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Obsidian\90-Meta\Claude\skills\vault\scripts\Test-VaultLinks.ps1"
   ```
   All green = the brain is installed.

## Keeping it healthy

- **Hardlinks sever silently.** Any tool that writes-and-renames (Claude Code's own Write/Edit included) severs a hardlink and the copies drift without an error. `Test-VaultLinks.ps1` detects it and says which side is newer. Repair: copy the newer file over the older one FIRST, then re-run `Setup-Machine.ps1` (it links to the vault copy).
- **New own skills** are authored directly in `90-Meta\Claude\skills\<name>\`, then junctioned with `Test-VaultLinks.ps1 -Fix`. New third-party skills get a row in [[skills-manifest]] in the same change.
- **New project memory** starts local; `Test-VaultLinks.ps1 -Adopt` (or a `Setup-Machine.ps1` run) moves it into the vault and junctions it.

## Risks to know

- **If the vault folder is moved or deleted, the links break.** The data still lives in the vault, but `%USERPROFILE%\.claude\` will return errors when Claude Code reads through dead links. Re-run `Setup-Machine.ps1` after moving the vault.
- **Hardlinks must be on the same volume.** Keep vault and `%USERPROFILE%` on the same drive.
- **Junctions only work for directories on local volumes.** They don't traverse network shares or OneDrive sync folders cleanly. Don't put the vault on a network drive.

## How to undo

To revert to fully local Claude config:

```powershell
# For each linked path, replace the link with a real copy:
$claude = "$env:USERPROFILE\.claude"
$target = (Get-Content "$claude\machine.json" | ConvertFrom-Json).vaultPath + '\90-Meta\Claude'

# Replace hardlinks
Remove-Item "$claude\CLAUDE.md", "$claude\settings.json"
Copy-Item "$target\CLAUDE.md"     "$claude\CLAUDE.md"
Copy-Item "$target\settings.json" "$claude\settings.json"
Get-ChildItem "$target\hooks" -File -Exclude _README.md | ForEach-Object {
  Remove-Item "$claude\hooks\$($_.Name)" -ErrorAction SilentlyContinue
  Copy-Item $_.FullName "$claude\hooks\$($_.Name)"
}

# Replace junctions (skills and project memory)
Get-ChildItem "$target\skills" -Directory | ForEach-Object {
  $src = "$claude\skills\$($_.Name)"
  if ((Get-Item $src -ErrorAction SilentlyContinue).LinkType -eq "Junction") {
    (Get-Item $src).Delete()
    Copy-Item $_.FullName $src -Recurse
  }
}
Get-ChildItem "$target\projects" -Directory | ForEach-Object {
  $slug = $_.Name
  $src  = "$claude\projects\$slug\memory"
  if ((Get-Item $src -ErrorAction SilentlyContinue).LinkType -eq "Junction") {
    (Get-Item $src).Delete()
    Copy-Item "$target\projects\$slug\memory" $src -Recurse
  }
}
```

After that you can safely delete `90-Meta\Claude\` from the vault.
