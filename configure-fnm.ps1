#Requires -Version 5.1
# Replace Chocolatey/MSI Node with fnm and wire shells. install.ps1 / install.cmd
# only place the fnm binary; this script is the configure path.
# Native Windows PowerShell 5.1 is enough; pwsh is not required.

$ErrorActionPreference = 'Stop'

# TLS 1.2 is off by default on some Windows PowerShell 5.1 hosts.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Write-Info {
  param([Parameter(Mandatory = $true)][string]$Message)
  Write-Host "[INFO] $Message"
}

function Write-WarnInfo {
  param([Parameter(Mandatory = $true)][string]$Message)
  Write-Warning $Message
}

function Test-IsWindowsOs {
  if ($PSVersionTable.PSVersion.Major -ge 6) {
    return [bool]$IsWindows
  }
  return $true
}

if (-not (Test-IsWindowsOs)) {
  throw 'configure-fnm.ps1 is for Windows. Unix bootstrap uses nvm via install.sh.'
}

function Test-Command {
  param([Parameter(Mandatory = $true)][string]$Name)
  return [bool](Get-Command $Name -ErrorAction Ignore)
}

function Test-IsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-NativeExitCode {
  param(
    [string]$CommandName,
    [int[]]$SuccessCodes = @(0, 3010)
  )
  if ($SuccessCodes -notcontains $LASTEXITCODE) {
    throw "$CommandName failed with exit $LASTEXITCODE"
  }
}

function Import-ChocolateyEnvironment {
  $chocoBin = Join-Path $env:ALLUSERSPROFILE 'chocolatey\bin'
  if (Test-Path $chocoBin) {
    if ($env:PATH -notlike "*$chocoBin*") {
      Write-Info "Adding Chocolatey bin to this session PATH"
      $env:PATH = "$chocoBin;$env:PATH"
    }
    else {
      Write-Info "Chocolatey bin already on PATH - skipping prepend"
    }
  }
  if ($env:ChocolateyInstall) {
    $profileMod = Join-Path $env:ChocolateyInstall 'helpers\chocolateyProfile.psm1'
    if (Test-Path $profileMod) {
      Import-Module $profileMod -ErrorAction SilentlyContinue
      if (Get-Command Update-SessionEnvironment -ErrorAction Ignore) {
        Update-SessionEnvironment
      }
    }
  }
}

function Install-ChocolateyIfMissing {
  if (Test-Command 'choco') {
    Write-Info "choco already on PATH - skipping Chocolatey install"
    Import-ChocolateyEnvironment
    return
  }
  if (-not (Test-IsAdmin)) {
    throw 'choco is required to install fnm. Re-run from an elevated Windows PowerShell, or run install.ps1 first.'
  }
  Write-Info "choco not found - installing Chocolatey"
  Set-ExecutionPolicy Bypass -Scope Process -Force
  Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
  Import-ChocolateyEnvironment
  if (-not (Test-Command 'choco')) {
    throw 'choco is still not on PATH. Open a new elevated PowerShell and re-run configure-fnm.ps1.'
  }
  Write-Info "Chocolatey install finished"
}

function Test-ChocoPackageInstalled {
  param([Parameter(Mandatory = $true)][string]$Name)
  if (-not (Test-Command 'choco')) {
    return $false
  }
  $lines = & choco list --local-only --exact $Name --limit-output 2>$null
  foreach ($line in $lines) {
    if ($line -match ('^' + [regex]::Escape($Name) + '\|')) {
      return $true
    }
  }
  return $false
}

function Get-FnmDir {
  if ($env:FNM_DIR -and $env:FNM_DIR.Trim()) {
    return $env:FNM_DIR.Trim()
  }
  return (Join-Path $env:APPDATA 'fnm')
}

function Get-FnmDefaultAliasDir {
  return (Join-Path (Get-FnmDir) 'aliases\default')
}

function Get-GlobalsSnapshotPath {
  return (Join-Path $HOME 'globals.txt')
}

function Save-NpmGlobalSnapshot {
  $snapshot = Get-GlobalsSnapshotPath
  if (Test-Path $snapshot) {
    Write-Info "Global snapshot already at $snapshot - skipping (keeps the pre-fnm list)"
    return
  }
  if (-not (Test-Command 'npm')) {
    Write-Info "npm not on PATH - skipping global snapshot"
    return
  }
  Write-Info "Writing npm global snapshot to $snapshot"
  & npm ls -g --depth=0 > $snapshot 2>&1
}

function Uninstall-ChocoNodePackages {
  $packages = @('nodejs', 'nodejs.install', 'nodejs-lts', 'nodejs-lts.install')
  if (-not (Test-Command 'choco')) {
    Write-Info "choco not on PATH - skipping Chocolatey Node uninstall"
    return
  }
  $found = @()
  foreach ($name in $packages) {
    if (Test-ChocoPackageInstalled $name) {
      $found += $name
    }
    else {
      Write-Info "Chocolatey package $name not installed - skipping"
    }
  }
  if ($found.Count -eq 0) {
    Write-Info "No Chocolatey Node packages installed - skipping choco uninstall"
    return
  }
  if (-not (Test-IsAdmin)) {
    throw "Chocolatey Node packages are installed ($($found -join ', ')). Re-run from an elevated Windows PowerShell."
  }
  Write-Info "Uninstalling Chocolatey Node packages: $($found -join ', ')"
  & choco uninstall -y @found
  Assert-NativeExitCode -CommandName 'choco uninstall'
  Import-ChocolateyEnvironment
}

function Test-IsNodeJsRuntimeDisplayName {
  param([string]$Name)
  if (-not $Name) {
    return $false
  }
  # Official MSI is "Node.js" or "Node.js 20.11.1". Skip "Node.js Tools for Visual Studio".
  return ($Name -eq 'Node.js') -or ($Name -match '^Node\.js \d')
}

function Get-MsiProductCode {
  param($App)
  if ($App.PSChildName -match '^\{[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}$') {
    return $App.PSChildName
  }
  if ($App.UninstallString -and ($App.UninstallString -match '\{[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}')) {
    return $Matches[0]
  }
  return $null
}

function Get-NodeJsMsiInstalls {
  $roots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  $found = @()
  $seen = @{}
  foreach ($root in $roots) {
    if (-not (Test-Path $root)) {
      continue
    }
    $apps = Get-ItemProperty (Join-Path $root '*') -ErrorAction SilentlyContinue
    foreach ($app in $apps) {
      if (-not (Test-IsNodeJsRuntimeDisplayName $app.DisplayName)) {
        continue
      }
      $code = Get-MsiProductCode $app
      if (-not $code) {
        Write-WarnInfo "Node.js entry '$($app.DisplayName)' has no MSI product code - skip"
        continue
      }
      if ($seen.ContainsKey($code)) {
        continue
      }
      $seen[$code] = $true
      $hive = 'HKCU'
      if ($root -like 'HKLM:*') {
        $hive = 'HKLM'
      }
      $found += [pscustomobject]@{
        DisplayName = $app.DisplayName
        ProductCode = $code
        Hive        = $hive
      }
    }
  }
  return $found
}

function Uninstall-NodeJsMsiInstalls {
  $installs = @(Get-NodeJsMsiInstalls)
  if ($installs.Count -eq 0) {
    Write-Info "No standalone Node.js MSI entries in Uninstall registry - skipping"
    return
  }
  $needsAdmin = @($installs | Where-Object { $_.Hive -eq 'HKLM' })
  if ($needsAdmin.Count -gt 0 -and -not (Test-IsAdmin)) {
    throw "Machine-wide Node.js MSI is installed ($($needsAdmin[0].DisplayName)). Re-run from an elevated Windows PowerShell."
  }
  foreach ($item in $installs) {
    Write-Info "Uninstalling $($item.DisplayName) ($($item.ProductCode)) via msiexec"
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $item.ProductCode, '/qn', '/norestart') -Wait -PassThru
    if (@(0, 1605, 3010) -notcontains $proc.ExitCode) {
      throw "msiexec /x $($item.ProductCode) failed with exit $($proc.ExitCode)"
    }
    Write-Info "msiexec finished for $($item.DisplayName) (exit $($proc.ExitCode))"
  }
}

function Hide-LegacyNpmRoamingDir {
  $npmDir = Join-Path $env:APPDATA 'npm'
  $backup = Join-Path $env:APPDATA 'npm.pre-fnm-bak'
  if (-not (Test-Path $npmDir)) {
    Write-Info "$npmDir not present - skipping rename"
    return
  }
  if (Test-Path $backup) {
    Write-Info "$backup already exists - leaving $npmDir in place"
    return
  }
  Write-Info "Renaming $npmDir -> $backup so stale global npm shims cannot shadow fnm"
  Rename-Item -Path $npmDir -NewName 'npm.pre-fnm-bak'
}

function Remove-SessionNodeShadowPaths {
  $parts = $env:PATH -split ';'
  $kept = @()
  $removed = @()
  foreach ($part in $parts) {
    if ($part -and ($part -match '(?i)(\\nodejs\\|\\nodejs$)')) {
      $removed += $part
    }
    else {
      $kept += $part
    }
  }
  if ($removed.Count -eq 0) {
    Write-Info "No Program Files nodejs entries on this session PATH - skipping strip"
    return
  }
  Write-Info "Dropping shadowed nodejs PATH entries from this session: $($removed -join '; ')"
  $env:PATH = ($kept -join ';')
}

function Install-FnmIfMissing {
  if (Test-Command 'fnm') {
    Write-Info "fnm already on PATH - skipping Chocolatey package fnm"
    return
  }
  Install-ChocolateyIfMissing
  if (-not (Test-IsAdmin)) {
    throw 'fnm is not on PATH. Re-run from an elevated Windows PowerShell so Chocolatey can install it, or run install.ps1 first.'
  }
  Write-Info "Installing Chocolatey package fnm"
  & choco install fnm -y
  Assert-NativeExitCode -CommandName 'choco install fnm'
  Import-ChocolateyEnvironment
  if (-not (Test-Command 'fnm')) {
    throw 'fnm is still not on PATH. Open a new elevated PowerShell and re-run configure-fnm.ps1.'
  }
  Write-Info "fnm install finished"
}

function Add-UserPathPrepend {
  param([Parameter(Mandatory = $true)][string]$Entry)
  $normalized = $Entry.TrimEnd('\')
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($null -eq $userPath) {
    $userPath = ''
  }
  $parts = @()
  foreach ($part in ($userPath -split ';')) {
    if ($part) {
      $parts += $part
    }
  }
  foreach ($part in $parts) {
    if ($part.TrimEnd('\') -ieq $normalized) {
      Write-Info "User PATH already has $normalized - skipping prepend"
      if ($env:PATH -notlike "*$normalized*") {
        $env:PATH = "$normalized;$env:PATH"
      }
      return
    }
  }
  # SetEnvironmentVariable writes REG_SZ (expanded literal), which Explorer and IDEs can read.
  if ($userPath) {
    $newPath = "$normalized;$userPath"
  }
  else {
    $newPath = $normalized
  }
  [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
  Write-Info "Prepended $normalized to user PATH"
  if ($env:PATH -notlike "*$normalized*") {
    $env:PATH = "$normalized;$env:PATH"
  }
}

function Add-UniqueFileLine {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Line,
    [Parameter(Mandatory = $true)][string]$Needle,
    [ValidateSet('CrLf', 'Lf')]
    [string]$Newline = 'CrLf'
  )
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path $dir)) {
    Write-Info "Creating $dir"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  $existing = ''
  if (Test-Path $Path) {
    $existing = [System.IO.File]::ReadAllText($Path)
  }
  if ($existing -and ($existing.IndexOf($Needle) -ge 0)) {
    Write-Info "Hook already present in $Path - skipping"
    return
  }
  Write-Info "Writing fnm hook to $Path"
  $nl = "`r`n"
  if ($Newline -eq 'Lf') {
    $nl = "`n"
  }
  $prefix = ''
  if ($existing -and -not ($existing.EndsWith("`n"))) {
    $prefix = $nl
  }
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::AppendAllText($Path, ($prefix + $Line + $nl), $utf8NoBom)
}

function Install-FnmShellHooks {
  $psHook = 'fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression'
  $psProfiles = @(
    (Join-Path $HOME 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1')
  )
  foreach ($profilePath in $psProfiles) {
    Add-UniqueFileLine -Path $profilePath -Line $psHook -Needle 'fnm env --use-on-cd --shell powershell' -Newline CrLf
  }

  $bashrc = Join-Path $HOME '.bashrc'
  $bashHook = 'eval "$(fnm env --use-on-cd --shell bash)"'
  Add-UniqueFileLine -Path $bashrc -Line $bashHook -Needle 'fnm env --use-on-cd --shell bash' -Newline Lf

  $bashProfile = Join-Path $HOME '.bash_profile'
  $sourceBlock = @'
if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
'@
  Add-UniqueFileLine -Path $bashProfile -Line $sourceBlock.Trim() -Needle '. "$HOME/.bashrc"' -Newline Lf
}

function Install-FnmNodeLts {
  Write-Info "Installing even-numbered Node LTS via fnm (avoids Current/odd lines that ship npm 12)"
  & fnm install --lts
  Assert-NativeExitCode -CommandName 'fnm install --lts'
  & fnm default lts-latest
  if ($LASTEXITCODE -ne 0) {
    Write-Info "lts-latest alias not available - setting default from fnm current"
    & fnm use --lts
    $current = ((& fnm current) | Out-String).Trim()
    if (-not $current) {
      throw 'fnm did not report a current version after LTS install.'
    }
    & fnm default $current
    Assert-NativeExitCode -CommandName 'fnm default'
    Write-Info "fnm default set to $current"
  }
  else {
    Write-Info "fnm default set to lts-latest"
  }
}

function Import-FnmSessionEnvironment {
  if (-not (Test-Command 'fnm')) {
    return
  }
  Write-Info "Evaluating fnm env for this session"
  $fnmEnv = & fnm env --use-on-cd --shell powershell | Out-String
  if ($fnmEnv -and $fnmEnv.Trim()) {
    Invoke-Expression $fnmEnv
  }
}

function Restore-NpmGlobalsFromSnapshot {
  $snapshot = Get-GlobalsSnapshotPath
  if (-not (Test-Path $snapshot)) {
    Write-Info "No $snapshot - skipping global restore"
    return
  }
  if (-not (Test-Command 'npm')) {
    Write-WarnInfo "npm not on PATH after fnm setup - cannot restore globals from $snapshot"
    return
  }
  $names = @()
  $seen = @{}
  foreach ($line in Get-Content -Path $snapshot) {
    if ($line -notmatch '(@?[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)?)@([0-9][A-Za-z0-9.+-]*)') {
      continue
    }
    $name = $Matches[1]
    if ($name -eq 'npm' -or $name -eq 'corepack') {
      continue
    }
    if ($seen.ContainsKey($name)) {
      continue
    }
    $seen[$name] = $true
    $names += $name
  }
  if ($names.Count -eq 0) {
    Write-Info "Snapshot $snapshot has no extra global packages to restore"
    return
  }
  Write-Info "Restoring global packages onto this fnm version: $($names -join ', ')"
  Write-Info "Globals are per Node version; npm link is per version too"
  foreach ($name in $names) {
    Write-Info "npm install -g $name"
    & npm install -g $name
    if ($LASTEXITCODE -ne 0) {
      Write-WarnInfo "npm install -g $name failed with exit $LASTEXITCODE (npm 12 needs an allowScripts opt-in)"
    }
  }
}

function Test-FnmNodeOnPath {
  Write-Info "Verifying node and npm resolve through fnm"
  $ok = $true
  foreach ($name in @('node', 'npm')) {
    $cmd = Get-Command $name -ErrorAction Ignore
    if (-not $cmd) {
      Write-WarnInfo "$name is not on PATH in this session - open a new shell"
      $ok = $false
      continue
    }
    $source = [string]$cmd.Source
    Write-Info "$name -> $source"
    if ($source -notmatch '(?i)\\fnm') {
      Write-WarnInfo "$name is not an fnm shim (machine PATH Node often shadows fnm). Do not choco install nodejs."
      $ok = $false
    }
  }
  if ($ok) {
    $nodeVer = ((& node --version) | Out-String).Trim()
    $npmVer = ((& npm --version) | Out-String).Trim()
    Write-Info "node $nodeVer / npm $npmVer come from fnm"
  }
  $legacy = @(
    (Join-Path ${env:ProgramFiles} 'nodejs'),
    (Join-Path ${env:ProgramFiles(x86)} 'nodejs')
  )
  foreach ($dir in $legacy) {
    if ($dir -and (Test-Path (Join-Path $dir 'node.exe'))) {
      Write-WarnInfo "Leftover $dir\node.exe can still shadow fnm on the machine PATH"
    }
  }
  if (Test-Command 'nvm') {
    Write-WarnInfo "nvm is still on PATH (nvm-windows). Remove it if it keeps winning over fnm."
  }
}

Write-Info "Starting fnm configure (Windows PowerShell $($PSVersionTable.PSVersion))"
Write-Info "This removes conflicting Node installs, then wires fnm and even-numbered LTS"

Save-NpmGlobalSnapshot
Uninstall-ChocoNodePackages
Uninstall-NodeJsMsiInstalls
Hide-LegacyNpmRoamingDir
Remove-SessionNodeShadowPaths
Install-FnmIfMissing
Install-FnmShellHooks
Install-FnmNodeLts
Import-FnmSessionEnvironment
$aliasDir = Get-FnmDefaultAliasDir
if (-not (Test-Path (Join-Path $aliasDir 'node.exe'))) {
  Write-WarnInfo "fnm default alias does not contain node.exe yet at $aliasDir"
}
Add-UserPathPrepend -Entry $aliasDir
Restore-NpmGlobalsFromSnapshot
Test-FnmNodeOnPath

Write-Info "Next steps:"
Write-Host ''
Write-Host '  Open a new PowerShell / Git Bash (sign out of Windows if Explorer apps still miss node).'
Write-Host '  Confirm Get-Command node,npm points under fnm, not C:\Program Files\nodejs.'
Write-Host "  Pre-fnm globals were saved at $(Get-GlobalsSnapshotPath) if npm existed."
Write-Host '  Pin repos with a .nvmrc or .node-version (fnm --use-on-cd honors both).'
Write-Host '  Do not choco install nodejs again - that machine PATH entry shadows fnm.'
Write-Host '  Stay on even LTS. Odd Current lines can ship npm 12, which blocks'
Write-Host '  dependency install scripts unless you opt in via allowScripts.'
Write-Host ''
Write-Info "fnm configure finished"
