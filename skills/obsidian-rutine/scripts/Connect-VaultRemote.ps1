<#
.SYNOPSIS
  Connects the vault to YOUR git remote (an empty GitHub repo) and turns on
  pushing in Obsidian Git.

.DESCRIPTION
  The installer cannot know which repository your vault should sync to, so it
  sets the vault up locally and leaves this as the one step you provide input
  for. Run it once with the URL of an EMPTY repo you own (private recommended).

  Steps: add/update the 'origin' remote, push the current branch, and set
  disablePush=false in .obsidian\plugins\obsidian-git\data.json so the
  Obsidian Git plugin starts pushing its automatic backups.

.EXAMPLE
  .\Connect-VaultRemote.ps1 -RepoUrl git@github.com:you/my-vault.git

.NOTES
  ASCII-ONLY SOURCE (Windows PowerShell 5.1 reads BOM-less .ps1 as Windows-1252).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$RepoUrl,

  # Defaults to the vaultPath recorded in %USERPROFILE%\.claude\machine.json.
  [string]$VaultPath
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Step($m) { Write-Host "  $m" }
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

if (-not $VaultPath) {
  $mf = "$env:USERPROFILE\.claude\machine.json"
  if (Test-Path $mf) { $VaultPath = ([System.IO.File]::ReadAllText($mf) | ConvertFrom-Json).vaultPath }
}
if (-not $VaultPath) { Die 'Vault path unknown. Pass -VaultPath.' }
if (-not (Test-Path (Join-Path $VaultPath '.git'))) { Die "'$VaultPath' is not a git repository. Run Install-ObsidianRutine.ps1 first." }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die 'git is not on PATH.' }

Write-Host ''
Write-Host "Connect-VaultRemote  vault=$VaultPath"
Write-Host ('-' * 60)

Push-Location $VaultPath
try {
  $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $existing = (& git remote get-url origin 2>$null)
  $ErrorActionPreference = $eap
  if ($existing) {
    if ($existing -ne $RepoUrl) {
      if ((Invoke-Git @('remote', 'set-url', 'origin', $RepoUrl)) -ne 0) { Die 'could not update remote origin' }
      Step "origin updated: $existing -> $RepoUrl"
    }
    else { Step "origin already set to $RepoUrl" }
  }
  else {
    if ((Invoke-Git @('remote', 'add', 'origin', $RepoUrl)) -ne 0) { Die 'could not add remote origin' }
    Step "origin added: $RepoUrl"
  }

  if ((Invoke-Git @('push', '-u', 'origin', 'HEAD')) -ne 0) {
    Die 'push failed. Is the repo empty and do you have access? Fix it, then re-run this script.'
  }
}
finally { Pop-Location }

# turn on pushing in Obsidian Git
$gitData = Join-Path $VaultPath '.obsidian\plugins\obsidian-git\data.json'
if (Test-Path $gitData) {
  $cfg = [System.IO.File]::ReadAllText($gitData) | ConvertFrom-Json
  if ($cfg.PSObject.Properties['disablePush']) { $cfg.disablePush = $false }
  else { $cfg | Add-Member -NotePropertyName disablePush -NotePropertyValue $false }
  [System.IO.File]::WriteAllText($gitData, ((($cfg | ConvertTo-Json -Depth 10) -replace "`r`n", "`n") + "`n"), $utf8)
  Step 'Obsidian Git: pushing enabled (disablePush=false) - restart Obsidian to apply'
}
else {
  Step 'Obsidian Git settings not found - plugin not installed yet; pushing stays off until it is'
}

Write-Host ''
Write-Host 'Connected. Obsidian Git will now commit AND push its automatic backups.'
Write-Host ''
