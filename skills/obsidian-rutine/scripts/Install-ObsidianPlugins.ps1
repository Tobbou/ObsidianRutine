<#
.SYNOPSIS
  Downloads the community plugins the routine relies on into <vault>\.obsidian\plugins\.

.DESCRIPTION
  Fetches the latest GitHub release of each plugin and saves main.js,
  manifest.json and (when present) styles.css. Existing data.json settings are
  never touched. Idempotent: a plugin whose manifest.json already exists is
  skipped unless -Force. Failures are reported, not thrown - the vault works
  without plugins, and Get-RutineStatus.ps1 shows what is missing.

  Enabling the plugins is a file the template already ships
  (.obsidian\community-plugins.json). Obsidian still asks the user once to
  "Trust author and enable plugins" on first open - that cannot be automated.

.EXAMPLE
  .\Install-ObsidianPlugins.ps1 -VaultPath "$env:USERPROFILE\Obsidian"

.NOTES
  ASCII-ONLY SOURCE (Windows PowerShell 5.1 reads BOM-less .ps1 as Windows-1252).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$VaultPath,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$plugins = @(
  @{ Id = 'obsidian-git';          Repo = 'Vinzent03/obsidian-git' }
  @{ Id = 'dataview';              Repo = 'blacksmithgu/obsidian-dataview' }
  @{ Id = 'templater-obsidian';    Repo = 'SilentVoid13/Templater' }
  @{ Id = 'obsidian-tasks-plugin'; Repo = 'obsidian-tasks-group/obsidian-tasks' }
)

$pluginRoot = Join-Path $VaultPath '.obsidian\plugins'
New-Item -ItemType Directory -Path $pluginRoot -Force | Out-Null
$headers = @{ 'User-Agent' = 'ObsidianRutine-installer' }
$ok = 0; $failed = @()

foreach ($p in $plugins) {
  $dir = Join-Path $pluginRoot $p.Id
  if ((Test-Path (Join-Path $dir 'manifest.json')) -and -not $Force) {
    Write-Host "  $($p.Id): already installed"
    $ok++
    continue
  }
  try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$($p.Repo)/releases/latest" -Headers $headers
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $got = @()
    foreach ($name in @('main.js', 'manifest.json', 'styles.css')) {
      $asset = $rel.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
      if (-not $asset) {
        if ($name -eq 'styles.css') { continue }   # optional
        throw "release $($rel.tag_name) has no asset '$name'"
      }
      Invoke-WebRequest -Uri $asset.browser_download_url -OutFile (Join-Path $dir $name) -Headers $headers -UseBasicParsing
      $got += $name
    }
    # report the version Obsidian will see (the manifest), not the release tag - they can differ
    $ver = $rel.tag_name
    try { $m = [System.IO.File]::ReadAllText((Join-Path $dir 'manifest.json')) | ConvertFrom-Json; if ($m.version) { $ver = $m.version } } catch { }
    Write-Host "  $($p.Id): v$ver ($($got -join ', '))"
    $ok++
  }
  catch {
    Write-Host "  $($p.Id): FAILED - $($_.Exception.Message)" -ForegroundColor Yellow
    $failed += $p.Id
  }
}

Write-Host "  $ok/$($plugins.Count) plugin(s) in place"
if ($failed) { Write-Host "  missing: $($failed -join ', ') - re-run this script when online" -ForegroundColor Yellow }
