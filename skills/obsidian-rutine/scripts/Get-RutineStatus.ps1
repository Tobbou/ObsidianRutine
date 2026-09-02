<#
.SYNOPSIS
  Reports what the ObsidianRutine setup has in place and, above all, what is
  still missing and how to fix it.

.DESCRIPTION
  Read-only. Checks tools (git, Obsidian, Claude Code), the vault (structure,
  git repo, identity, remote), Obsidian (plugins, push setting, vault
  registration) and the Claude links (machine.json, hardlinks, vault skill,
  login). Prints a checklist and writes it to <vault>\90-Meta\Setup-Status.md
  so both the user and Claude can read it. -AsJson prints machine-readable
  output for agents. Never throws; always exits 0.

.EXAMPLE
  .\Get-RutineStatus.ps1

.EXAMPLE
  .\Get-RutineStatus.ps1 -AsJson

.NOTES
  ASCII-ONLY SOURCE (Windows PowerShell 5.1 reads BOM-less .ps1 as Windows-1252).
#>
[CmdletBinding()]
param(
  # Defaults to the vaultPath recorded in %USERPROFILE%\.claude\machine.json.
  [string]$VaultPath,
  [switch]$AsJson,
  [switch]$NoWrite
)

$ErrorActionPreference = 'Continue'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$claude = "$env:USERPROFILE\.claude"
$items = New-Object System.Collections.ArrayList

function Add-Check($Area, $Check, $Ok, $Detail, $Fix) {
  [void]$items.Add([pscustomobject]@{ Area = $Area; Check = $Check; Ok = $Ok; Detail = $Detail; Fix = $Fix })
}
function Invoke-GitIn($dir, [string[]]$GitArgs) {
  if (-not (Test-Path $dir)) { return $null }
  Push-Location $dir
  try {
    $out = & git @GitArgs 2>$null
    if ($LASTEXITCODE -eq 0) { return ($out -join "`n") } else { return $null }
  }
  finally { Pop-Location }
}

# ---------- resolve vault ----------
$machine = $null
$machineFile = "$claude\machine.json"
if (Test-Path $machineFile) { try { $machine = [System.IO.File]::ReadAllText($machineFile) | ConvertFrom-Json } catch { } }
if (-not $VaultPath -and $machine) { $VaultPath = $machine.vaultPath }
if (-not $VaultPath) { $VaultPath = Join-Path $env:USERPROFILE 'Obsidian' }
$VaultPath = $VaultPath.TrimEnd('\')

# ---------- tools ----------
$git = Get-Command git -ErrorAction SilentlyContinue
$gitDetail = 'not on PATH'; if ($git) { $gitDetail = $git.Source }
Add-Check 'Tools' 'Git installed' ([bool]$git) $gitDetail 'winget install -e --id Git.Git  (or https://git-scm.com/)'

$obsExe = Join-Path $env:LOCALAPPDATA 'Programs\Obsidian\Obsidian.exe'
$obs = (Test-Path $obsExe) -or [bool](Get-Command obsidian -ErrorAction SilentlyContinue)
$obsDetail = 'not found'; if ($obs) { $obsDetail = 'found' }
Add-Check 'Tools' 'Obsidian installed' $obs $obsDetail 'winget install -e --id Obsidian.Obsidian  (or https://obsidian.md/download)'

$cc = Get-Command claude -ErrorAction SilentlyContinue
$ccDetail = 'not on PATH'; if ($cc) { $ccDetail = $cc.Source }
Add-Check 'Tools' 'Claude Code installed' ([bool]$cc) $ccDetail 'winget install -e --id Anthropic.ClaudeCode   (or: irm https://claude.ai/install.ps1 | iex)'

# ---------- vault ----------
$hasStructure = Test-Path (Join-Path $VaultPath '90-Meta\Claude')
Add-Check 'Vault' 'Vault folder with routine structure' $hasStructure $VaultPath 'run Install-ObsidianRutine.ps1'

$isRepo = Test-Path (Join-Path $VaultPath '.git')
$repoDetail = 'no .git'; if ($isRepo) { $repoDetail = 'yes' }
Add-Check 'Vault' 'Vault is a git repository' $isRepo $repoDetail 'run Install-ObsidianRutine.ps1 (it runs git init)'

$commits = 0
if ($isRepo -and $git) { $c = Invoke-GitIn $VaultPath @('rev-list', '--count', 'HEAD'); if ($c) { $commits = [int]$c } }
Add-Check 'Vault' 'At least one commit' ($commits -gt 0) "$commits commit(s)" 'git add -A; git commit -m "Initialize vault"'

$name = $null; $email = $null
if ($git) { $name = Invoke-GitIn $VaultPath @('config', 'user.name'); $email = Invoke-GitIn $VaultPath @('config', 'user.email') }
$idDetail = 'missing'; if ($name) { $idDetail = "$name <$email>" }
Add-Check 'Vault' 'Git identity configured' ([bool]($name -and $email)) $idDetail 'git config --global user.name "Your Name"; git config --global user.email "you@example.com"'

$origin = $null
if ($isRepo -and $git) { $origin = Invoke-GitIn $VaultPath @('remote', 'get-url', 'origin') }
$originDetail = 'no remote - the installer cannot know which repo your vault should sync to'; if ($origin) { $originDetail = $origin }
Add-Check 'Vault' 'Git remote (your GitHub repo) connected' ([bool]$origin) $originDetail 'create an EMPTY private repo (gh repo create my-vault --private), then run Connect-VaultRemote.ps1 -RepoUrl <url>'

if ($origin) {
  $upstream = Invoke-GitIn $VaultPath @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
  $upDetail = 'never pushed'; if ($upstream) { $upDetail = "tracking $upstream" }
  Add-Check 'Vault' 'Branch pushed to remote' ([bool]$upstream) $upDetail 'git push -u origin HEAD'
}

# ---------- obsidian ----------
$pluginIds = @('obsidian-git', 'dataview', 'templater-obsidian', 'obsidian-tasks-plugin')
$present = @($pluginIds | Where-Object { Test-Path (Join-Path $VaultPath ".obsidian\plugins\$_\manifest.json") })
$missingPlugins = @($pluginIds | Where-Object { $present -notcontains $_ })
$plugDetail = "$($present.Count)/$($pluginIds.Count) present"
if ($missingPlugins.Count -gt 0) { $plugDetail += ' - missing: ' + ($missingPlugins -join ', ') }
Add-Check 'Obsidian' 'Community plugins downloaded' ($missingPlugins.Count -eq 0) $plugDetail 'run Install-ObsidianPlugins.ps1 -VaultPath <vault>'

$gitData = Join-Path $VaultPath '.obsidian\plugins\obsidian-git\data.json'
$pushOn = $false
if (Test-Path $gitData) { try { $cfg = [System.IO.File]::ReadAllText($gitData) | ConvertFrom-Json; $pushOn = -not [bool]$cfg.disablePush } catch { } }
if ($origin) {
  $pushDetail = 'disablePush=true'; if ($pushOn) { $pushDetail = 'push enabled' }
  Add-Check 'Obsidian' 'Obsidian Git pushes backups' $pushOn $pushDetail 'run Connect-VaultRemote.ps1 (it enables push) or toggle it in Obsidian Git settings'
}
else {
  Add-Check 'Obsidian' 'Obsidian Git pushes backups' $false 'push is off until a remote exists (commits still happen locally every 10 min)' 'connect a remote first (see above)'
}

$registered = $false
$registry = Join-Path $env:APPDATA 'obsidian\obsidian.json'
if (Test-Path $registry) {
  try {
    $reg = [System.IO.File]::ReadAllText($registry) | ConvertFrom-Json
    foreach ($v in $reg.vaults.PSObject.Properties) {
      $p = ($v.Value.path -replace '/', '\').TrimEnd('\')
      if ($p.ToLower() -eq $VaultPath.ToLower()) { $registered = $true }
    }
  } catch { }
}
$regDetail = 'not opened in Obsidian yet'; if ($registered) { $regDetail = 'listed in obsidian.json' }
Add-Check 'Obsidian' 'Vault registered in Obsidian' $registered $regDetail 'close Obsidian and re-run Install-ObsidianRutine.ps1 (it registers the vault while Obsidian is closed), or in Obsidian: Open another vault > Open folder as vault'

Add-Check 'Obsidian' 'Community plugins trusted (manual)' $null 'Obsidian asks once per vault; cannot be pre-set from files' 'on first open click "Trust author and enable plugins" (Settings > Community plugins > turn off Restricted mode)'

# ---------- claude links ----------
$mOk = $false
$mDetail = 'missing'
if ($machine) {
  $mDetail = "context=$($machine.context) vaultPath=$($machine.vaultPath)"
  if ($machine.vaultPath) { $mOk = ($machine.vaultPath.TrimEnd('\').ToLower() -eq $VaultPath.ToLower()) }
}
Add-Check 'Claude' 'machine.json points at this vault' $mOk $mDetail 'run <vault>\90-Meta\Scripts\Setup-Machine.ps1 -Context work|private'

$linked = $false
$localClaudeMd = "$claude\CLAUDE.md"
if (Test-Path $localClaudeMd) {
  $list = (fsutil hardlink list $localClaudeMd 2>$null) -join "`n"
  $linked = $list -match [regex]::Escape((Split-Path (Join-Path $VaultPath '90-Meta\Claude\CLAUDE.md') -NoQualifier))
}
$linkDetail = 'not linked'; if ($linked) { $linkDetail = 'linked' }
Add-Check 'Claude' 'Global CLAUDE.md hardlinked into vault' $linked $linkDetail 'run Setup-Machine.ps1'

$ruleOk = $false
if (Test-Path $localClaudeMd) { $ruleOk = ([System.IO.File]::ReadAllText($localClaudeMd)) -match '## Obsidian vault' }
$ruleDetail = 'missing'; if ($ruleOk) { $ruleDetail = 'present' }
Add-Check 'Claude' 'Vault-usage rule present in CLAUDE.md' $ruleOk $ruleDetail 'append <vault>\90-Meta\Claude\CLAUDE.vault-section.md to your CLAUDE.md (Setup-Machine does this on first run)'

$skill = Get-Item "$claude\skills\vault" -Force -ErrorAction SilentlyContinue
$skillOk = [bool]($skill -and $skill.LinkType -eq 'Junction')
$skillDetail = 'missing'; if ($skillOk) { $skillDetail = 'junction in place' }
Add-Check 'Claude' 'vault skill installed (junction)' $skillOk $skillDetail 'run Setup-Machine.ps1 (or Test-VaultLinks.ps1 -Fix)'

$loggedIn = Test-Path "$claude\.credentials.json"
$loginDetail = 'no credentials file'; if ($loggedIn) { $loginDetail = 'credentials present' }
Add-Check 'Claude' 'Claude Code logged in' $loggedIn $loginDetail 'start claude once and log in'

# ---------- output ----------
$done    = @($items | Where-Object { $_.Ok -eq $true })
$missing = @($items | Where-Object { $_.Ok -eq $false })
$manual  = @($items | Where-Object { $null -eq $_.Ok })

if ($AsJson) {
  [pscustomobject]@{ vaultPath = $VaultPath; done = $done.Count; missing = $missing.Count; manual = $manual.Count; items = $items } | ConvertTo-Json -Depth 5
}
else {
  Write-Host ''
  Write-Host "ObsidianRutine status  vault=$VaultPath"
  Write-Host ('-' * 64)
  foreach ($area in @('Tools', 'Vault', 'Obsidian', 'Claude')) {
    Write-Host ''
    Write-Host "[$area]"
    foreach ($i in ($items | Where-Object { $_.Area -eq $area })) {
      if ($i.Ok -eq $true) {
        Write-Host "  [x] $($i.Check) - $($i.Detail)"
      }
      elseif ($i.Ok -eq $false) {
        Write-Host "  [ ] $($i.Check) - $($i.Detail)" -ForegroundColor Yellow
        Write-Host "      fix: $($i.Fix)" -ForegroundColor DarkGray
      }
      else {
        Write-Host "  [~] $($i.Check) - $($i.Detail)" -ForegroundColor Cyan
        Write-Host "      do:  $($i.Fix)" -ForegroundColor DarkGray
      }
    }
  }
  Write-Host ''
  Write-Host ('-' * 64)
  Write-Host "$($done.Count) in place, $($missing.Count) missing, $($manual.Count) manual step(s)."
  Write-Host ''
}

# ---------- write Setup-Status.md into the vault ----------
if (-not $NoWrite -and (Test-Path (Join-Path $VaultPath '90-Meta'))) {
  $md = New-Object System.Collections.ArrayList
  [void]$md.Add('---')
  [void]$md.Add('type: meta')
  [void]$md.Add('tags: [meta, setup]')
  [void]$md.Add('---')
  [void]$md.Add('')
  [void]$md.Add('# Setup status')
  [void]$md.Add('')
  [void]$md.Add("Generated by Get-RutineStatus.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm') for the vault at ``$VaultPath``. Re-run the script (or ask Claude for the ObsidianRutine status) to refresh.")
  [void]$md.Add('')
  if ($missing.Count -gt 0 -or $manual.Count -gt 0) {
    [void]$md.Add('## Still to do')
    [void]$md.Add('')
    foreach ($i in $missing) {
      [void]$md.Add("- [ ] **$($i.Check)** - $($i.Detail)")
      [void]$md.Add("  - fix: ``$($i.Fix)``")
    }
    foreach ($i in $manual) {
      [void]$md.Add("- [ ] **$($i.Check)** (manual) - $($i.Detail)")
      [void]$md.Add("  - do: $($i.Fix)")
    }
    [void]$md.Add('')
  }
  [void]$md.Add('## In place')
  [void]$md.Add('')
  foreach ($i in $done) { [void]$md.Add("- [x] $($i.Check) - $($i.Detail)") }
  [void]$md.Add('')
  [System.IO.File]::WriteAllText((Join-Path $VaultPath '90-Meta\Setup-Status.md'), (($md -join "`n") + "`n"), $utf8)
  if (-not $AsJson) { Write-Host "Checklist written to $VaultPath\90-Meta\Setup-Status.md"; Write-Host '' }
}
exit 0
