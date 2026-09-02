<#
.SYNOPSIS
  Creates a new vault note in the correct tree and folder, from the matching
  template, with real frontmatter values instead of Templater tags.

.DESCRIPTION
  Resolves the vault path and the Work/ vs Private/ tree from
  %USERPROFILE%\.claude\machine.json (override with -VaultPath / -Tree), picks
  the folder and template from -Kind, substitutes the Templater placeholders,
  and writes UTF-8 without BOM. Refuses to overwrite an existing note.

  The script only scaffolds the file - open it afterwards and write the content.

.EXAMPLE
  .\New-VaultNote.ps1 -Kind codebase -Title "Signing Pipeline" -Codebase MyApp -Platform git

.EXAMPLE
  .\New-VaultNote.ps1 -Kind concept -Title "Kubernetes Networking" -Tags k8s,networking -WhatIf

.NOTES
  ASCII-ONLY SOURCE. Windows PowerShell 5.1 reads BOM-less .ps1 files as
  Windows-1252, so any non-ASCII literal here would be silently corrupted.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('codebase', 'concept', 'project', 'meeting', 'daily', 'inbox')]
  [string]$Kind,

  # Note title in Title Case. Not needed for -Kind daily (the ISO date is used).
  [string]$Title,

  # Codebase folder name, required for -Kind codebase.
  [string]$Codebase,

  # git | github | powershell | excel | lowcode | local | ...
  [string]$Platform,

  # Repo URL or local path, for codebase notes.
  [string]$Repo,

  # Places a meeting note under 10-Projects\<Project>\ instead of 00-Inbox\.
  [string]$Project,

  [string[]]$Tags,

  [ValidateSet('work', 'private')]
  [string]$Tree,

  # Defaults to the vaultPath recorded in %USERPROFILE%\.claude\machine.json.
  [string]$VaultPath
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$today = Get-Date -Format 'yyyy-MM-dd'

function Fail($m) { throw $m }

# ---------- machine.json ----------
$machine = $null
$machineFile = "$env:USERPROFILE\.claude\machine.json"
if (Test-Path $machineFile) {
  $machine = [System.IO.File]::ReadAllText($machineFile) | ConvertFrom-Json
}

# ---------- vault ----------
if (-not $VaultPath -and $machine) { $VaultPath = $machine.vaultPath }
if (-not $VaultPath) { Fail 'Vault path unknown. Pass -VaultPath, or run 90-Meta\Scripts\Setup-Machine.ps1 first.' }
if (-not (Test-Path $VaultPath)) { Fail "Vault not found at '$VaultPath'." }
$templates = Join-Path $VaultPath '90-Meta\Templates'
if (-not (Test-Path $templates)) { Fail "Templates not found at '$templates'. Is '$VaultPath' the vault?" }

# ---------- tree ----------
if (-not $Tree) {
  if ($machine -and $machine.context -in @('work', 'private')) { $Tree = $machine.context }
  if (-not $Tree) {
    $Tree = 'work'
    Write-Warning "machine.json missing or unreadable - assumed context 'work'. Pass -Tree private if that is wrong."
  }
}
$treeDir = (Get-Culture).TextInfo.ToTitleCase($Tree)   # work -> Work

# ---------- title ----------
if ($Kind -eq 'daily') {
  if ($Title) { Write-Warning "-Title is ignored for -Kind daily; using the ISO date." }
  $Title = $today
}
if (-not $Title) { Fail "-Title is required for -Kind $Kind." }
$badChars = '/\:*?"<>|'
foreach ($c in $badChars.ToCharArray()) {
  if ($Title.Contains($c)) { Fail "Title contains '$c', which breaks filenames and wiki-links." }
}

# ---------- folder + template ----------
switch ($Kind) {
  'codebase' {
    if (-not $Codebase) { Fail "-Codebase is required for -Kind codebase (the folder under 40-Codebases)." }
    $folder = Join-Path $VaultPath "$treeDir\40-Codebases\$Codebase"
    $template = Join-Path $templates 'codebase-note.md'
    if (-not $Platform) {
      $Platform = 'git'
      Write-Warning "-Platform not given - defaulting to 'git'. Set it explicitly so 40-Codebases stays filterable."
    }
  }
  'concept' {
    $folder = Join-Path $VaultPath "$treeDir\30-Knowledge"
    $template = Join-Path $templates 'concept.md'
  }
  'project' {
    $folder = Join-Path $VaultPath "$treeDir\10-Projects\$Title"
    $template = Join-Path $templates 'project.md'
  }
  'meeting' {
    $folder = if ($Project) { Join-Path $VaultPath "$treeDir\10-Projects\$Project" }
             else { Join-Path $VaultPath "$treeDir\00-Inbox" }
    $template = Join-Path $templates 'meeting.md'
  }
  'daily' {
    $folder = Join-Path $VaultPath '50-Daily'      # vault root - never split
    $template = Join-Path $templates 'daily.md'
  }
  'inbox' {
    $folder = Join-Path $VaultPath "$treeDir\00-Inbox"
    $template = $null                              # minimal stub, not a finished note
  }
}

$path = Join-Path $folder "$Title.md"
if (Test-Path $path) { Fail "Note already exists: $path`nUpdate that note instead of creating a duplicate." }

# ---------- build content ----------
if ($template) {
  if (-not (Test-Path $template)) { Fail "Template not found: $template" }
  $text = [System.IO.File]::ReadAllText($template)

  # Templater substitutions
  $text = $text -replace '<%\s*tp\.date\.now\("YYYY-MM-DD, dddd"\)\s*%>', (Get-Date -Format 'yyyy-MM-dd, dddd')
  $text = $text -replace '<%\s*tp\.date\.now\("YYYY-MM-DD"\)\s*%>', $today
  $text = $text.Replace('<% tp.file.title %>', $Title)
  $text = $text -replace '<%\s*tp\.system\.suggester\([^%]*%>', $Tree      # daily: context field
  if ($text -match '<%') {
    $text = $text -replace '<%[^%]*%>', ''
    Write-Warning "Unrecognized Templater tag(s) in the template were blanked - check the frontmatter."
  }

  # fill in the fields the templates leave empty
  if ($Platform) { $text = $text -replace '(?m)^platform:\s*$', "platform: $Platform" }
  if ($Repo)     { $text = $text -replace '(?m)^repo:\s*$', "repo: $Repo" }
  if ($Project -and $Kind -eq 'meeting') { $text = $text -replace '(?m)^project:\s*$', "project: $Project" }
  if ($Tags) {
    $existing = @()
    if ($text -match '(?m)^tags:\s*\[(.*)\]\s*$') {
      # @() is required: a one-item pipeline yields a STRING, and "a" + @("b")
      # is string concatenation, which silently produces tags: [ab]
      $existing = @($Matches[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    $all = @($existing) + @($Tags) | Select-Object -Unique
    $text = $text -replace '(?m)^tags:\s*\[.*\]\s*$', ("tags: [" + ($all -join ', ') + "]")
  }
}
else {
  $tagList = @('inbox') + @($Tags) | Select-Object -Unique
  $text = @(
    '---'
    'type: knowledge'
    "created: $today"
    ("tags: [" + ($tagList -join ', ') + "]")
    '---'
    ''
    "# $Title"
    ''
    '<!-- Fast capture. Move it to its real home once it has one. -->'
    ''
  ) -join "`r`n"
}

# ---------- write ----------
if ($PSCmdlet.ShouldProcess($path, 'Create vault note')) {
  New-Item -ItemType Directory -Path $folder -Force | Out-Null
  [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
  Write-Host "Created: $path"
  Write-Host "Tree:    $treeDir   (kind=$Kind)"
  Write-Host "Next:    write the content, and link it with [[wiki-links]] to related notes."
}
else {
  Write-Host "Would create: $path"
  Write-Host "Tree:         $treeDir   (kind=$Kind)"
}
