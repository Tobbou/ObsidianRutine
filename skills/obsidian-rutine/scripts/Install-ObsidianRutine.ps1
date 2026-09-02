<#
.SYNOPSIS
  Installs the ObsidianRutine end to end: prerequisites, vault structure,
  Obsidian plugins + settings, and the Claude Code links - then reports
  exactly what is still missing.

.DESCRIPTION
  Local-first and idempotent. No GitHub repo is required to start: the vault
  is created and committed locally, and connecting a remote is the one step
  that needs your input (Connect-VaultRemote.ps1 -RepoUrl <url>), because the
  installer cannot know which repository you want to sync to.

  Steps:
    1. Prerequisites  - git and Obsidian via winget (per-user installs; no admin)
    2. Vault          - scaffold from the bundled template (or clone -RepoUrl first)
    3. Git            - init (the commit happens at the end of the run)
    4. Obsidian       - download community plugins; settings come with the template
    5. Claude         - Setup-Machine.ps1 links ~/.claude into the vault and installs the vault skill
    6. Status         - open the vault in Obsidian, print the missing-steps checklist,
                        then commit everything (+ push when a remote exists)

  Every step records its outcome instead of aborting the run, so one failure
  (e.g. offline) leaves you with a working partial setup and a precise to-do
  list in <vault>\90-Meta\Setup-Status.md.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Install-ObsidianRutine.ps1

.EXAMPLE
  .\Install-ObsidianRutine.ps1 -VaultPath D:\Notes\Vault -Context private -RepoUrl git@github.com:me/vault.git

.NOTES
  ASCII-ONLY SOURCE (Windows PowerShell 5.1 reads BOM-less .ps1 as Windows-1252).
#>
[CmdletBinding()]
param(
  [string]$VaultPath = (Join-Path $env:USERPROFILE 'Obsidian'),

  [ValidateSet('work', 'private')]
  [string]$Context = 'work',

  # Optional: URL of an EMPTY repo of yours. Cloned first; can also be connected later.
  [string]$RepoUrl,

  [switch]$SkipPrerequisites,
  [switch]$SkipPlugins,
  [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$template = Join-Path $PSScriptRoot '..\template'
$VaultPath = $VaultPath.TrimEnd('\')
$notes = New-Object System.Collections.ArrayList

function Step($m) { Write-Host "  $m" }
function Warn($m) { Write-Host "  WARNING: $m" -ForegroundColor Yellow; [void]$notes.Add($m) }
function Die($m)  { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }
function Invoke-Git {
  param([string[]]$GitArgs)
  $eap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & git @GitArgs 2>&1 | ForEach-Object { Step ("$_") }
  $code = $LASTEXITCODE
  $ErrorActionPreference = $eap
  return $code
}
function Invoke-Winget {
  param([string[]]$WingetArgs)
  $eap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & winget @WingetArgs 2>&1 | ForEach-Object {
    $line = "$_".Trim()
    if ($line -and $line -notmatch '^[\\|/-]+$') { Step $line }
  }
  $code = $LASTEXITCODE
  $ErrorActionPreference = $eap
  return $code
}
function Test-Obsidian {
  return ((Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\Obsidian\Obsidian.exe')) -or [bool](Get-Command obsidian -ErrorAction SilentlyContinue))
}
function Update-PathEnv {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
# Registers the vault in Obsidian's vault list (%APPDATA%\obsidian\obsidian.json) so
# Obsidian opens it on next start. Obsidian only reads that file at startup, so this
# works only while Obsidian is NOT running; returns $false otherwise.
function Register-ObsidianVault($Path) {
  if (Get-Process -Name 'Obsidian' -ErrorAction SilentlyContinue) { return $false }
  $registry = Join-Path $env:APPDATA 'obsidian\obsidian.json'
  $reg = $null
  if (Test-Path $registry) {
    try { $reg = [System.IO.File]::ReadAllText($registry) | ConvertFrom-Json } catch { $reg = $null }
  }
  if (-not $reg) { $reg = New-Object PSObject }
  if (-not $reg.PSObject.Properties['vaults']) { $reg | Add-Member -NotePropertyName vaults -NotePropertyValue (New-Object PSObject) }
  foreach ($v in $reg.vaults.PSObject.Properties) {
    $p = ("$($v.Value.path)" -replace '/', '\').TrimEnd('\')
    if ($p.ToLower() -eq $Path.ToLower()) {
      if ($v.Value.PSObject.Properties['open']) { $v.Value.open = $true } else { $v.Value | Add-Member -NotePropertyName open -NotePropertyValue $true }
      [System.IO.File]::WriteAllText($registry, ((($reg | ConvertTo-Json -Depth 6) -replace "`r`n", "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
      return $true
    }
  }
  $bytes = New-Object byte[] 8
  (New-Object System.Random).NextBytes($bytes)
  $id = ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
  $ts = [long]((Get-Date).ToUniversalTime() - (Get-Date '1970-01-01')).TotalMilliseconds
  $entry = New-Object PSObject
  $entry | Add-Member -NotePropertyName path -NotePropertyValue $Path
  $entry | Add-Member -NotePropertyName ts -NotePropertyValue $ts
  $entry | Add-Member -NotePropertyName open -NotePropertyValue $true
  $reg.vaults | Add-Member -NotePropertyName $id -NotePropertyValue $entry
  New-Item -ItemType Directory -Path (Split-Path $registry) -Force | Out-Null
  [System.IO.File]::WriteAllText($registry, ((($reg | ConvertTo-Json -Depth 6) -replace "`r`n", "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
  return $true
}

Write-Host ''
Write-Host "ObsidianRutine installer  vault=$VaultPath  context=$Context"
Write-Host ('=' * 64)
if (-not (Test-Path $template)) {
  Die "Template not found at '$template'. Run this script from the skill's scripts\ folder (clone https://github.com/Tobbou/ObsidianRutine)."
}

# ---------- 1. prerequisites ----------
Write-Host ''
Write-Host '[1/6] prerequisites'
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($SkipPrerequisites) { Step 'skipped (-SkipPrerequisites)' }
else {
  if (Get-Command git -ErrorAction SilentlyContinue) { Step 'git: present' }
  elseif ($winget) {
    Step 'git: installing (per-user)...'
    $code = Invoke-Winget @('install', '-e', '--id', 'Git.Git', '--scope', 'user', '--silent', '--accept-source-agreements', '--accept-package-agreements')
    if ($code -ne 0) { $code = Invoke-Winget @('install', '-e', '--id', 'Git.Git', '--silent', '--accept-source-agreements', '--accept-package-agreements') }
    Update-PathEnv
    if (Get-Command git -ErrorAction SilentlyContinue) { Step 'git: installed' }
    else { Warn "git could not be installed by winget (exit $code) - install it from https://git-scm.com/ and re-run" }
  }
  else { Warn 'git is missing and winget is unavailable - install git from https://git-scm.com/ and re-run' }

  if (Test-Obsidian) { Step 'Obsidian: present' }
  elseif ($winget) {
    Step 'Obsidian: installing (per-user)...'
    $code = Invoke-Winget @('install', '-e', '--id', 'Obsidian.Obsidian', '--scope', 'user', '--silent', '--accept-source-agreements', '--accept-package-agreements')
    if ($code -ne 0) { $code = Invoke-Winget @('install', '-e', '--id', 'Obsidian.Obsidian', '--silent', '--accept-source-agreements', '--accept-package-agreements') }
    if (Test-Obsidian) { Step 'Obsidian: installed' }
    else { Warn "Obsidian could not be installed by winget (exit $code) - install it from https://obsidian.md/download" }
  }
  else { Warn 'Obsidian is missing and winget is unavailable - install it from https://obsidian.md/download' }
}
$haveGit = [bool](Get-Command git -ErrorAction SilentlyContinue)

# ---------- 2. vault folder ----------
Write-Host ''
Write-Host '[2/6] vault structure'
$vaultDrive = Split-Path $VaultPath -Qualifier
$homeDrive  = Split-Path $env:USERPROFILE -Qualifier
if ($vaultDrive -ne $homeDrive) {
  Warn "vault is on $vaultDrive but your profile is on $homeDrive - the Claude hardlinks (step 5) need one volume and will be skipped"
}

$existingRutine = Test-Path (Join-Path $VaultPath '90-Meta\Claude')
$isEmpty = (-not (Test-Path $VaultPath)) -or (-not (Get-ChildItem $VaultPath -Force -ErrorAction SilentlyContinue))
if ($existingRutine) {
  Step 'existing ObsidianRutine vault found - template not re-applied'
}
elseif (-not $isEmpty) {
  Die "'$VaultPath' exists, is not empty, and is not an ObsidianRutine vault. Pick another -VaultPath (or empty the folder)."
}
else {
  if ($RepoUrl -and $haveGit) {
    Step "cloning $RepoUrl"
    if ((Invoke-Git @('clone', $RepoUrl, $VaultPath)) -ne 0) {
      Die 'git clone failed - check the URL and your access (or omit -RepoUrl and connect later).'
    }
    $allowed = @('README.md', 'LICENSE', 'LICENSE.md', '.gitignore', '.gitattributes')
    $unexpected = @(Get-ChildItem $VaultPath -Force | Where-Object { $_.Name -ne '.git' -and $allowed -notcontains $_.Name })
    if ($unexpected.Count -gt 0) {
      Die ("the repo is not empty (found: " + (($unexpected | ForEach-Object Name) -join ', ') + "). Use a fresh, empty repo.")
    }
  }
  New-Item -ItemType Directory -Path $VaultPath -Force | Out-Null
  Copy-Item (Join-Path $template '*') $VaultPath -Recurse -Force
  Step "vault scaffolded from template at $VaultPath"
}

# ---------- 3. git ----------
Write-Host ''
Write-Host '[3/6] git'
$hasOrigin = $false
$haveIdentity = $false
if (-not $haveGit) { Warn 'git unavailable - vault is not versioned yet; re-run after installing git' }
else {
  Push-Location $VaultPath
  try {
    if (-not (Test-Path '.git')) {
      if ((Invoke-Git @('init', '-b', 'main')) -ne 0) {
        [void](Invoke-Git @('init'))
        [void](Invoke-Git @('checkout', '-b', 'main'))
      }
      Step 'repository initialized'
    }
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $name = & git config user.name 2>$null
    $email = & git config user.email 2>$null
    $origin = & git remote get-url origin 2>$null
    $ErrorActionPreference = $eap
    $hasOrigin = [bool]$origin
    $haveIdentity = [bool]($name -and $email)
    if (-not $haveIdentity) {
      Warn 'git identity missing - run: git config --global user.name "Your Name"; git config --global user.email "you@example.com" - then re-run'
    }
    if ($hasOrigin) { Step "remote origin: $origin" }
    else { Step 'no remote yet - the vault stays local until you connect one (Connect-VaultRemote.ps1 -RepoUrl <url>)' }
    Step 'commit happens at the end, once plugins, links and the status report are in place'
  }
  finally { Pop-Location }
}

# ---------- 4. obsidian plugins + settings ----------
Write-Host ''
Write-Host '[4/6] Obsidian plugins and settings'
if ($SkipPlugins) { Step 'plugin download skipped (-SkipPlugins)' }
else {
  try { & (Join-Path $PSScriptRoot 'Install-ObsidianPlugins.ps1') -VaultPath $VaultPath }
  catch { Warn "plugin download failed: $($_.Exception.Message) - re-run Install-ObsidianPlugins.ps1 when online" }
}
$gitData = Join-Path $VaultPath '.obsidian\plugins\obsidian-git\data.json'
if ($hasOrigin -and (Test-Path $gitData)) {
  try {
    $cfg = [System.IO.File]::ReadAllText($gitData) | ConvertFrom-Json
    if ($cfg.PSObject.Properties['disablePush']) { $cfg.disablePush = $false }
    else { $cfg | Add-Member -NotePropertyName disablePush -NotePropertyValue $false }
    [System.IO.File]::WriteAllText($gitData, ((($cfg | ConvertTo-Json -Depth 10) -replace "`r`n", "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Step 'Obsidian Git: push enabled (remote exists)'
  }
  catch { Warn "could not update Obsidian Git settings: $($_.Exception.Message)" }
}
else { Step 'Obsidian Git: auto-commit every 10 min; push stays off until a remote is connected' }

# ---------- 5. claude links ----------
Write-Host ''
Write-Host '[5/6] Claude Code links (Setup-Machine.ps1)'
$setup = Join-Path $VaultPath '90-Meta\Scripts\Setup-Machine.ps1'
if ($vaultDrive -ne $homeDrive) { Step 'skipped - vault and profile are on different volumes' }
elseif (-not (Test-Path $setup)) { Warn 'Setup-Machine.ps1 not found in the vault - template incomplete?' }
else {
  try { & $setup -Context $Context -VaultPath $VaultPath }
  catch { Warn "Setup-Machine.ps1 failed: $($_.Exception.Message) - re-run it: $setup -Context $Context" }
}

# ---------- 6. open + status ----------
Write-Host ''
Write-Host '[6/6] open vault and report'
if (-not (Test-Obsidian)) { Step 'Obsidian not installed - open the vault folder in Obsidian once it is' }
else {
  $registered = $false
  try { $registered = Register-ObsidianVault $VaultPath } catch { Warn "could not register the vault in Obsidian: $($_.Exception.Message)" }
  if ($registered) { Step 'vault registered in Obsidian (obsidian.json)' }
  else { Step 'Obsidian is running - the vault list can only be changed while it is closed; use "Open folder as vault" in Obsidian, or close Obsidian and re-run' }
  if ($NoOpen) { Step 'not opening Obsidian (-NoOpen)' }
  else {
    try {
      if ($registered) {
        $exe = Join-Path $env:LOCALAPPDATA 'Programs\Obsidian\Obsidian.exe'
        if (Test-Path $exe) { Start-Process $exe } else { Start-Process ('obsidian://open?path=' + [uri]::EscapeDataString($VaultPath)) }
      }
      else { Start-Process ('obsidian://open?path=' + [uri]::EscapeDataString($VaultPath)) }
      Step 'Obsidian opened - accept "Trust author and enable plugins" when asked'
    }
    catch { Warn "could not launch Obsidian: $($_.Exception.Message)" }
  }
}

# ---------- commit everything this run produced ----------
# (before the status report, so the report shows the true commit/push state;
#  the report file itself is picked up by the next Obsidian Git auto-commit)
if ($haveGit -and (Test-Path (Join-Path $VaultPath '.git')) -and $haveIdentity) {
  Push-Location $VaultPath
  try {
    [void](Invoke-Git @('add', '-A'))
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & git diff --cached --quiet 2>$null
    $hasChanges = ($LASTEXITCODE -ne 0)
    & git rev-parse --verify HEAD 2>$null | Out-Null
    $hasCommits = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $eap
    if ($hasChanges) {
      $msg = 'Initialize vault from ObsidianRutine'
      if ($hasCommits) { $msg = 'ObsidianRutine: update setup' }
      if ((Invoke-Git @('commit', '-q', '-m', $msg)) -eq 0) { Step "committed: $msg" }
      else { Warn 'commit failed - see output above' }
    }
    else { Step 'nothing new to commit' }
    if ($hasOrigin) {
      if ((Invoke-Git @('push', '-u', 'origin', 'HEAD')) -eq 0) { Step 'pushed to origin' }
      else { Warn 'push to origin failed - fix access, then: git push -u origin HEAD' }
    }
  }
  finally { Pop-Location }
  Write-Host ''
}

& (Join-Path $PSScriptRoot 'Get-RutineStatus.ps1') -VaultPath $VaultPath

if ($notes.Count -gt 0) {
  Write-Host 'Warnings from this run:' -ForegroundColor Yellow
  foreach ($n in $notes) { Write-Host "  - $n" -ForegroundColor Yellow }
  Write-Host ''
}
exit 0
