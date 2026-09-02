<#
.SYNOPSIS
  Verifies that the links from %USERPROFILE%\.claude\ into the vault's
  90-Meta\Claude\ are intact, and reports anything that is not backed up.

.DESCRIPTION
  Checks five things:
    1. machine.json - which tree new notes go to, and where the vault is.
    2. Hardlinks    - CLAUDE.md, settings.json, and every hooks\<name>.ps1. A
                      write-and-rename by any editor severs these silently and
                      the copies then drift.
    3. Junctions    - one per vault-side skills\<name> and projects\<slug>\memory.
    4. Local-only   - memory dirs that exist under ~/.claude but have no vault
                      counterpart. Those are NOT in git: a new project's memory
                      dir is created locally by Claude and never adopted on its
                      own.
    5. Manifest     - third-party skills and MCP servers listed in
                      90-Meta\Claude\skills-manifest.md vs what is installed.

  Read-only by default.
    -Fix     recreates missing junctions for vault-side folders.
    -Adopt   moves local-only memory dirs into the vault and replaces them with
             a junction (this is what puts a new project's memory into git).

  A severed hardlink is NOT repaired here - copy the newer file over the older
  one first, then run 90-Meta\Scripts\Setup-Machine.ps1 -Context work|private.

.EXAMPLE
  .\Test-VaultLinks.ps1

.EXAMPLE
  .\Test-VaultLinks.ps1 -Adopt -Fix

.NOTES
  ASCII-ONLY SOURCE. Windows PowerShell 5.1 reads BOM-less .ps1 files as
  Windows-1252, so any non-ASCII literal here would be silently corrupted.
#>
[CmdletBinding()]
param(
  # Defaults to the vaultPath recorded in %USERPROFILE%\.claude\machine.json.
  [string]$VaultPath,
  [switch]$Fix,
  [switch]$Adopt
)

$ErrorActionPreference = 'Stop'
$claude = "$env:USERPROFILE\.claude"

if (-not $VaultPath) {
  $machineFile = "$claude\machine.json"
  if (Test-Path $machineFile) {
    $VaultPath = ([System.IO.File]::ReadAllText($machineFile) | ConvertFrom-Json).vaultPath
  }
}
if (-not $VaultPath) {
  throw 'Vault path unknown. Pass -VaultPath, or run 90-Meta\Scripts\Setup-Machine.ps1 first (it records vaultPath in machine.json).'
}
$target = "$VaultPath\90-Meta\Claude"

$problems = 0
$actions = 0
function Ok($m)   { Write-Host "  OK    $m" }
function Bad($m)  { Write-Host "  BAD   $m" -ForegroundColor Red;    $script:problems++ }
function Warn($m) { Write-Host "  WARN  $m" -ForegroundColor Yellow; $script:problems++ }
function Did($m)  { Write-Host "  FIXED $m" -ForegroundColor Green;  $script:actions++ }
function Info($m) { Write-Host "  --    $m" -ForegroundColor DarkGray }

if (-not (Test-Path $target)) { throw "'$target' missing. Is '$VaultPath' really the vault?" }

Write-Host ''
Write-Host "Test-VaultLinks  vault=$VaultPath"
Write-Host ('-' * 64)

# ---------- 1. machine context ----------
Write-Host ''
Write-Host '[1/5] machine context'
$machineFile = "$claude\machine.json"
if (Test-Path $machineFile) {
  $machine = [System.IO.File]::ReadAllText($machineFile) | ConvertFrom-Json
  $ctx = $machine.context
  if ($ctx -in @('work', 'private')) {
    Ok "machine.json -> context=$ctx  (new notes go to $((Get-Culture).TextInfo.ToTitleCase($ctx))\)"
  }
  else { Bad "machine.json has context='$ctx' - expected 'work' or 'private'" }
  if ($machine.vaultPath -and ($machine.vaultPath -ne $VaultPath)) {
    Warn "machine.json vaultPath is '$($machine.vaultPath)' but this run checks '$VaultPath'"
  }
}
else {
  Warn 'machine.json missing - run Setup-Machine.ps1.'
}

# ---------- 2. hardlinks ----------
Write-Host ''
Write-Host '[2/5] shared config and hooks (hardlinks)'
$linkPairs = @(
  foreach ($f in @('CLAUDE.md', 'settings.json')) {
    [pscustomobject]@{ Label = $f; Src = "$claude\$f"; Dst = "$target\$f" }
  }
  if (Test-Path "$target\hooks") {
    foreach ($h in (Get-ChildItem "$target\hooks" -File | Where-Object { $_.Name -ne '_README.md' })) {
      [pscustomobject]@{ Label = "hooks\$($h.Name)"; Src = "$claude\hooks\$($h.Name)"; Dst = $h.FullName }
    }
  }
)
foreach ($pair in $linkPairs) {
  $f = $pair.Label; $src = $pair.Src; $dst = $pair.Dst
  if (-not (Test-Path $dst)) { Bad "$f missing in the vault"; continue }
  if (-not (Test-Path $src)) { Bad "$f missing at $src - run Setup-Machine.ps1"; continue }

  $list = (fsutil hardlink list $src 2>$null) -join "`n"
  $linked = $list -match [regex]::Escape((Split-Path $dst -NoQualifier))
  $same = (Get-FileHash $src).Hash -eq (Get-FileHash $dst).Hash
  if ($linked) { Ok "$f hardlinked" }
  elseif ($same) { Bad "$f is NOT hardlinked but content still matches - link was severed, re-run Setup-Machine.ps1 now" }
  else {
    $newer = if ((Get-Item $src).LastWriteTime -gt (Get-Item $dst).LastWriteTime) { 'the LOCAL copy (~\.claude) is newer' } else { 'the VAULT copy is newer' }
    Bad "$f is NOT hardlinked AND the copies have DRIFTED - $newer. Copy the newer file over the older one FIRST, then run Setup-Machine.ps1 (it links to the vault copy)"
  }
}

# ---------- 3. junctions for vault-side folders ----------
Write-Host ''
Write-Host '[3/5] vault-backed folders (junctions)'

function Test-JunctionSet($vaultParent, $liveParent, $leaf, $label) {
  if (-not (Test-Path $vaultParent)) { Info "no $label in the vault yet"; return }
  $ok = 0; $missing = @(); $wrong = @()
  foreach ($d in (Get-ChildItem $vaultParent -Directory -ErrorAction SilentlyContinue)) {
    $name = $d.Name
    $dst = if ($leaf) { Join-Path $d.FullName $leaf } else { $d.FullName }
    if (-not (Test-Path $dst)) { continue }
    $src = if ($leaf) { Join-Path (Join-Path $liveParent $name) $leaf } else { Join-Path $liveParent $name }

    if (Test-Path $src) {
      $item = Get-Item $src -Force
      if ($item.LinkType -eq 'Junction') { $ok++ }
      else { $wrong += $name }
    }
    else { $missing += $name }
  }
  Ok "$label : $ok junction(s) in place"
  foreach ($n in $wrong) { Bad "$label\$n exists locally but is a REAL folder, not a junction - vault copy is being ignored" }
  foreach ($n in $missing) {
    if ($Fix) {
      $srcDir = if ($leaf) { Join-Path $liveParent $n } else { $liveParent }
      New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
      $src = if ($leaf) { Join-Path $srcDir $leaf } else { Join-Path $liveParent $n }
      $dst = if ($leaf) { Join-Path (Join-Path $vaultParent $n) $leaf } else { Join-Path $vaultParent $n }
      New-Item -ItemType Junction -Path $src -Target $dst | Out-Null
      Did "$label\$n junctioned"
    }
    else { Warn "$label\$n is in the vault but has no local junction - re-run with -Fix" }
  }
}

Test-JunctionSet "$target\skills"   "$claude\skills"   $null    'skills'
Test-JunctionSet "$target\projects" "$claude\projects" 'memory' 'project memory'

# ---------- 4. local-only (not in git) ----------
Write-Host ''
Write-Host '[4/5] local-only state (not backed up)'

$localOnly = @()
foreach ($p in (Get-ChildItem "$claude\projects" -Directory -ErrorAction SilentlyContinue)) {
  $src = Join-Path $p.FullName 'memory'
  if (-not (Test-Path $src)) { continue }
  if ((Get-Item $src -Force).LinkType -eq 'Junction') { continue }
  $localOnly += [pscustomobject]@{
    Slug  = $p.Name
    Path  = $src
    Files = @(Get-ChildItem $src -Filter *.md -File -ErrorAction SilentlyContinue).Count
  }
}

if (-not $localOnly) { Ok 'every project memory dir is vault-backed' }
foreach ($lo in $localOnly) {
  if ($Adopt) {
    $dst = "$target\projects\$($lo.Slug)\memory"
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    if ($lo.Files -gt 0) {
      Copy-Item "$($lo.Path)\*" $dst -Recurse -Force
    }
    Remove-Item $lo.Path -Recurse -Force
    New-Item -ItemType Junction -Path $lo.Path -Target $dst | Out-Null
    Did "$($lo.Slug) adopted into the vault ($($lo.Files) file(s)) and junctioned"
  }
  else {
    Warn "$($lo.Slug) memory is LOCAL ONLY ($($lo.Files) file(s), not in git) - re-run with -Adopt"
  }
}

# ---------- 5. manifest: third-party skills and MCP servers ----------
Write-Host ''
Write-Host '[5/5] skills-manifest.md (third-party skills, MCP servers)'
$manifest = "$target\skills-manifest.md"
if (-not (Test-Path $manifest)) {
  Warn 'skills-manifest.md missing from the vault'
}
else {
  $mText = [System.IO.File]::ReadAllText($manifest)

  # Names come from table rows whose first cell is a backticked name, scoped to
  # one '## ' section (### subsections do not end the scope).
  function Get-ManifestNames($text, $heading) {
    $names = @()
    $inSection = $false
    foreach ($line in ($text -split "`n")) {
      if ($line -match '^##\s') { $inSection = ($line -match [regex]::Escape($heading)) }
      elseif ($inSection -and $line -match '^\|\s*`([A-Za-z0-9_.-]+)`') { $names += $Matches[1] }
    }
    return $names
  }

  $expected = @(Get-ManifestNames $mText 'Third-party skills')
  $missing = @($expected | Where-Object { -not (Test-Path "$claude\skills\$_") })
  Ok "manifest lists $($expected.Count) third-party skill(s), $($expected.Count - $missing.Count) installed"
  foreach ($n in $missing) { Warn "skill '$n' is in the manifest but NOT installed - install command is in skills-manifest.md" }

  foreach ($d in (Get-ChildItem "$claude\skills" -Directory -ErrorAction SilentlyContinue)) {
    if ((Get-Item $d.FullName -Force).LinkType -eq 'Junction') { continue }
    if ($expected -notcontains $d.Name) { Warn "skill '$($d.Name)' is installed but NOT in the manifest - add a row to skills-manifest.md" }
  }

  $mcpExpected = @(Get-ManifestNames $mText 'MCP servers')
  if ($mcpExpected) {
    $cfgPath = "$env:USERPROFILE\.claude.json"
    $mcpKeys = $null
    if (Test-Path $cfgPath) {
      try {
        $cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json -AsHashtable
        if ($cfg['mcpServers']) { $mcpKeys = @($cfg['mcpServers'].Keys) } else { $mcpKeys = @() }
      }
      catch { $mcpKeys = $null }
    }
    if ($null -eq $mcpKeys) { Info 'could not parse ~\.claude.json - MCP check skipped (needs PowerShell 7)' }
    else {
      foreach ($m in $mcpExpected) {
        if ($mcpKeys -contains $m) { Ok "MCP server '$m' registered" }
        else { Warn "MCP server '$m' NOT registered - register command is in skills-manifest.md" }
      }
    }
  }
}

# ---------- summary ----------
Write-Host ''
Write-Host ('-' * 64)
if ($problems -eq 0) { Write-Host "All checks passed. $actions change(s) made." -ForegroundColor Green }
else { Write-Host "$problems issue(s) found, $actions change(s) made." -ForegroundColor Yellow }
Write-Host ''
exit ([int]($problems -gt 0 -and $actions -eq 0))
