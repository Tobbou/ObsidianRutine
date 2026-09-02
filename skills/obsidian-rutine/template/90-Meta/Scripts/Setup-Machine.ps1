<#
.SYNOPSIS
  Prepares a machine to work with this vault: declares the machine's context
  and (re)builds the links from %USERPROFILE%\.claude\ into 90-Meta\Claude\.

.DESCRIPTION
  Idempotent - safe to run repeatedly. Run it once after cloning the vault on
  a new machine (the ObsidianRutine skill (Install-ObsidianRutine.ps1) runs it for you on the first
  machine), and again if the vault is ever moved (which breaks the links).

  Links five things: machine.json (local, per machine), the two hardlinked
  config files, one hardlink per hook script, one junction per project memory
  dir, and one junction per vault-backed skill.

  First-run friendly: if the vault does not yet contain CLAUDE.md or
  settings.json, your existing local files are ADOPTED into the vault (and the
  vault-usage section is appended to your CLAUDE.md). Nothing of yours is
  overwritten. Memory dirs that exist only locally - which is how Claude
  creates them in a project that is new to the vault - are adopted into the
  vault so they end up in git.

  To verify the links later without rebuilding anything, use
  90-Meta\Claude\skills\vault\scripts\Test-VaultLinks.ps1.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File ".\90-Meta\Scripts\Setup-Machine.ps1" -Context work

.NOTES
  ASCII-ONLY SOURCE. Windows PowerShell 5.1 reads BOM-less .ps1 files as
  Windows-1252, so any non-ASCII literal here would be silently corrupted.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('work', 'private')]
  [string]$Context,

  # Defaults to the vault this script lives in.
  [string]$VaultPath,

  [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'
if (-not $VaultPath) {
  $VaultPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')
}
$claude = "$env:USERPROFILE\.claude"
$target = "$VaultPath\90-Meta\Claude"
$backup = "$claude\_pre-vault-backup"
$utf8   = New-Object System.Text.UTF8Encoding($false)

function Step($m) { Write-Host "  $m" }
function Warn($m) { Write-Host "  WARNING: $m" -ForegroundColor Yellow }

Write-Host ''
Write-Host "Setup-Machine  context=$Context  vault=$VaultPath"
Write-Host ('-' * 60)

# ---------- 0. sanity ----------
if (-not (Test-Path $target)) {
  throw "'$target' missing. Is '$VaultPath' really the vault?"
}

$vaultDrive = (Split-Path $VaultPath -Qualifier)
$homeDrive  = (Split-Path $env:USERPROFILE -Qualifier)
if ($vaultDrive -ne $homeDrive) {
  throw "Hardlinks require one volume: vault is on $vaultDrive, profile on $homeDrive."
}

if ($WhatIfOnly) { Write-Host "`n(WhatIfOnly - nothing will be changed)`n" }

# ---------- 1. machine context ----------
Write-Host "`n[1/5] machine context"
$machineFile = "$claude\machine.json"
$json = [ordered]@{
  context   = $Context
  vaultPath = $VaultPath
  hostUser  = $env:USERNAME
  note      = 'Machine-local Claude config. Never committed - it must differ per machine, unlike ~/.claude/CLAUDE.md and settings.json, which are hardlinked into the vault and therefore shared. Determines which vault tree new notes are written to: Work/ or Private/.'
} | ConvertTo-Json
if (-not $WhatIfOnly) {
  New-Item -ItemType Directory -Path $claude -Force | Out-Null
  [System.IO.File]::WriteAllText($machineFile, $json, $utf8)
}
Step "$machineFile -> context=$Context"

# ---------- 2. hardlink shared config ----------
Write-Host "`n[2/5] shared Claude config (hardlinks)"
if (-not $WhatIfOnly) { New-Item -ItemType Directory -Path $backup -Force | Out-Null }
foreach ($f in @('CLAUDE.md', 'settings.json')) {
  $src = "$claude\$f"
  $dst = "$target\$f"

  # first run: the template ships no CLAUDE.md/settings.json - adopt yours,
  # or seed a minimal one if you have none
  if (-not (Test-Path $dst)) {
    if (Test-Path $src) {
      if (-not $WhatIfOnly) {
        Copy-Item $src $dst -Force
        if ($f -eq 'CLAUDE.md') {
          $sectionFile = "$target\CLAUDE.vault-section.md"
          if (Test-Path $sectionFile) {
            $cur = [System.IO.File]::ReadAllText($dst)
            $sec = [System.IO.File]::ReadAllText($sectionFile)
            if ($cur -notmatch [regex]::Escape('## Obsidian vault')) {
              [System.IO.File]::WriteAllText($dst, ($cur.TrimEnd() + "`n`n" + $sec), $utf8)
              Step 'CLAUDE.md: vault-usage section appended'
            }
          }
        }
      }
      Step "$f adopted from ~\.claude into the vault"
    }
    else {
      if (-not $WhatIfOnly) {
        if ($f -eq 'CLAUDE.md') {
          Copy-Item "$target\CLAUDE.vault-section.md" $dst -Force
        }
        else {
          [System.IO.File]::WriteAllText($dst, "{}`n", $utf8)
        }
      }
      Step "$f seeded in the vault (you had none locally)"
    }
  }

  if ((Test-Path $src) -and (Test-Path $dst)) {
    $already = (fsutil hardlink list $src 2>$null) -join "`n"
    if ($already -match [regex]::Escape((Split-Path $dst -NoQualifier))) {
      Step "$f already linked"
      continue
    }
    if (-not $WhatIfOnly) {
      Copy-Item $src "$backup\$f" -Force
      Remove-Item $src -Force
    }
    Step "$f backed up to _pre-vault-backup\"
  }
  if (-not $WhatIfOnly) { New-Item -ItemType HardLink -Path $src -Target $dst | Out-Null }
  Step "$f linked"
}

# ---------- 3. hardlink hook scripts ----------
# Hooks are per-file hardlinks (like CLAUDE.md/settings.json), not a junction:
# settings.json refers to them via %USERPROFILE%\.claude\hooks\<name>.
Write-Host "`n[3/5] hook scripts (hardlinks)"
$hookFiles = @()
if (Test-Path "$target\hooks") {
  $hookFiles = @(Get-ChildItem "$target\hooks" -File | Where-Object { $_.Name -ne '_README.md' })
}
if ($hookFiles.Count -gt 0) {
  if (-not $WhatIfOnly) { New-Item -ItemType Directory -Path "$claude\hooks" -Force | Out-Null }
  foreach ($h in $hookFiles) {
    $src = "$claude\hooks\$($h.Name)"
    $dst = $h.FullName
    if (Test-Path $src) {
      $already = (fsutil hardlink list $src 2>$null) -join "`n"
      if ($already -match [regex]::Escape((Split-Path $dst -NoQualifier))) {
        Step "$($h.Name) already linked"
        continue
      }
      if (-not $WhatIfOnly) {
        New-Item -ItemType Directory -Path "$backup\hooks" -Force | Out-Null
        Copy-Item $src "$backup\hooks\$($h.Name)" -Force
        Remove-Item $src -Force
      }
      Step "$($h.Name) backed up to _pre-vault-backup\hooks\"
    }
    if (-not $WhatIfOnly) { New-Item -ItemType HardLink -Path $src -Target $dst | Out-Null }
    Step "$($h.Name) linked"
  }
}
else {
  Step 'no hook scripts in the vault yet - nothing to link'
}

# ---------- 4. junction project memory ----------
Write-Host "`n[4/5] project memory (junctions)"
if (-not $WhatIfOnly) { New-Item -ItemType Directory -Path "$claude\projects" -Force | Out-Null }
$n = 0; $skipped = 0
foreach ($p in (Get-ChildItem "$target\projects" -Directory -ErrorAction SilentlyContinue)) {
  $slug = $p.Name
  $src  = "$claude\projects\$slug\memory"
  $dst  = "$target\projects\$slug\memory"
  if (-not (Test-Path $dst)) { continue }

  if (Test-Path $src) {
    if ((Get-Item $src -Force).LinkType -eq 'Junction') { $skipped++; continue }
    if (-not $WhatIfOnly) {
      New-Item -ItemType Directory -Path "$backup\projects\$slug" -Force | Out-Null
      Copy-Item $src "$backup\projects\$slug\memory" -Recurse -Force
      Remove-Item $src -Recurse -Force
    }
    Step "$slug - local memory backed up first"
  }
  if (-not $WhatIfOnly) {
    New-Item -ItemType Directory -Path "$claude\projects\$slug" -Force | Out-Null
    New-Item -ItemType Junction -Path $src -Target $dst | Out-Null
  }
  $n++
}
Step "$n junction(s) created, $skipped already in place"

# adopt memory dirs that exist only locally - that is how Claude creates them in
# a project the vault has not seen before, and they are not in git until adopted
$adopted = 0
foreach ($p in (Get-ChildItem "$claude\projects" -Directory -ErrorAction SilentlyContinue)) {
  $src = Join-Path $p.FullName 'memory'
  if (-not (Test-Path $src)) { continue }
  if ((Get-Item $src -Force).LinkType -eq 'Junction') { continue }

  $dst = "$target\projects\$($p.Name)\memory"
  $files = @(Get-ChildItem $src -Filter *.md -File -ErrorAction SilentlyContinue).Count
  if (-not $WhatIfOnly) {
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    if ($files -gt 0) { Copy-Item "$src\*" $dst -Recurse -Force }
    Remove-Item $src -Recurse -Force
    New-Item -ItemType Junction -Path $src -Target $dst | Out-Null
  }
  Step "$($p.Name) - local-only memory adopted into the vault ($files file(s))"
  $adopted++
}
if ($adopted -eq 0) { Step 'no local-only memory dirs to adopt' }

# ---------- 5. junction vault-backed skills ----------
Write-Host "`n[5/5] skills (junctions)"
if (Test-Path "$target\skills") {
  if (-not $WhatIfOnly) { New-Item -ItemType Directory -Path "$claude\skills" -Force | Out-Null }
  $sn = 0; $sskipped = 0
  foreach ($s in (Get-ChildItem "$target\skills" -Directory)) {
    $name = $s.Name
    $src  = "$claude\skills\$name"
    $dst  = $s.FullName

    if (Test-Path $src) {
      if ((Get-Item $src -Force).LinkType -eq 'Junction') { $sskipped++; continue }
      if (-not $WhatIfOnly) {
        New-Item -ItemType Directory -Path "$backup\skills" -Force | Out-Null
        Copy-Item $src "$backup\skills\$name" -Recurse -Force
        Remove-Item $src -Recurse -Force
      }
      Step "$name - local skill backed up first"
    }
    if (-not $WhatIfOnly) { New-Item -ItemType Junction -Path $src -Target $dst | Out-Null }
    $sn++
  }
  Step "$sn junction(s) created, $sskipped already in place"
  Step 'skills not present in the vault stay local - that is deliberate for third-party skills (record them in skills-manifest.md)'
}
else {
  Step 'no skills in the vault yet - nothing to link'
}

Write-Host ''
Write-Host ('-' * 60)
Write-Host "Done. New notes from this machine belong in: $((Get-Culture).TextInfo.ToTitleCase($Context))/"
Write-Host ''
Write-Host 'Remaining manual steps: open the vault in Obsidian and accept'
Write-Host '"Trust author and enable plugins", and see the bootstrap runbook in'
Write-Host '90-Meta\Claude\_README.md (MCP servers, third-party skills).'
Write-Host ''
