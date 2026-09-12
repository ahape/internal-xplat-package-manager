#Requires -Version 5.1
# Windows bootstrap. Runs under native Windows PowerShell 5.1 (powershell.exe);
# pwsh is not required to execute this script.
param(
  [switch]$WriteFnmProfiles
)

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
  throw 'install.ps1 is for Windows. Use install.sh on Linux or macOS.'
}

function Test-Command {
  param([Parameter(Mandatory = $true)][string]$Name)
  return [bool](Get-Command $Name -ErrorAction Ignore)
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
  else {
    Write-Info "Chocolatey bin directory not found yet - skipping PATH prepend"
  }
  if ($env:ChocolateyInstall) {
    $profileMod = Join-Path $env:ChocolateyInstall 'helpers\chocolateyProfile.psm1'
    if (Test-Path $profileMod) {
      Write-Info "Loading Chocolatey profile module"
      Import-Module $profileMod -ErrorAction SilentlyContinue
      if (Get-Command Update-SessionEnvironment -ErrorAction Ignore) {
        Update-SessionEnvironment
      }
    }
  }
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

function Add-UniqueFileLine {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Needle,
    [Parameter(Mandatory = $true)][string]$Line
  )
  $dir = Split-Path $Path -Parent
  if ($dir -and -not (Test-Path $dir)) {
    Write-Info "Creating profile directory $dir"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  if (-not (Test-Path $Path)) {
    Write-Info "Creating profile file $Path"
    New-Item -ItemType File -Path $Path -Force | Out-Null
  }
  if (-not (Select-String -Path $Path -SimpleMatch $Needle -Quiet)) {
    Write-Info "Writing fnm hook to $Path"
    Add-Content -Path $Path -Value ([Environment]::NewLine + $Line)
  }
  else {
    Write-Info "fnm hook already present in $Path - skipping"
  }
}

function Write-FnmPowerShellProfiles {
  # fnm only puts node/npm on PATH after `fnm env` is evaluated in the shell.
  Write-Info "Updating Windows PowerShell and pwsh profiles with fnm env hook"
  $hook = 'fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression'
  $profilePaths = @()
  if ($PROFILE) {
    $profilePaths += $PROFILE
  }
  $docs = [Environment]::GetFolderPath('MyDocuments')
  if ($docs) {
    $profilePaths += (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
    $profilePaths += (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1')
  }
  $profilePaths | Where-Object { $_ } | Select-Object -Unique | ForEach-Object {
    Add-UniqueFileLine -Path $_ -Needle 'fnm env' -Line $hook
  }
}

function Install-FnmNodeLts {
  Write-FnmPowerShellProfiles
  Write-Info "Evaluating fnm env for this PowerShell session"
  Invoke-Expression ((fnm env --use-on-cd --shell powershell | Out-String))
  if (Test-Command 'node') {
    Write-Info "node already on PATH - ensuring Node LTS via fnm (no-op if present)"
  }
  else {
    Write-Info "Installing Node LTS via fnm"
  }
  fnm install --lts --use --progress never
  Assert-NativeExitCode -CommandName 'fnm install --lts'
  Write-Info "Setting fnm default to LTS"
  fnm default lts-latest
  if ($LASTEXITCODE -ne 0) {
    Write-Info "fnm default lts-latest failed - using fnm current"
    $current = (fnm current | Out-String).Trim()
    if ($current) {
      fnm default $current
      Assert-NativeExitCode -CommandName 'fnm default'
    }
  }
}

function Install-ChocolateyPackages {
  $queue = @(
    @{ Command = 'jq'; Package = 'jq' },
    @{ Command = 'rg'; Package = 'ripgrep' },
    @{ Command = 'gh'; Package = 'gh' },
    @{ Command = 'az'; Package = 'azure-cli' },
    @{ Command = 'dotnet'; Package = 'dotnet-sdk' },
    @{ Command = 'pwsh'; Package = 'powershell-core' },
    @{ Command = 'fnm'; Package = 'fnm' }
  )
  $toInstall = @()
  foreach ($item in $queue) {
    if (Test-Command $item.Command) {
      Write-Info "$($item.Command) already on PATH - skipping Chocolatey package $($item.Package)"
    }
    else {
      Write-Info "Queuing Chocolatey package $($item.Package) (provides $($item.Command))"
      $toInstall += $item.Package
    }
  }
  if ($toInstall.Count -eq 0) {
    Write-Info "All Chocolatey packages already on PATH - skipping choco install"
    return
  }
  Write-Info "Installing Chocolatey packages: $($toInstall -join ', ')"
  # powershell-core is the Chocolatey id for pwsh; current stable is the LTS train.
  # Node comes from fnm (nvm-like), not the nodejs-lts Chocolatey package.
  # Native command failures do not honor $ErrorActionPreference on Windows PowerShell 5.1.
  & choco install -y @toInstall
  Assert-NativeExitCode -CommandName 'choco install'
  Write-Info "Chocolatey package install finished"
}

if ($WriteFnmProfiles) {
  Write-Info "WriteFnmProfiles mode - updating PowerShell profiles only"
  Write-FnmPowerShellProfiles
  Write-Info "Done writing fnm profile hooks"
  return
}

Write-Info "Starting Windows bootstrap (Windows PowerShell $($PSVersionTable.PSVersion))"
Write-Info "Detected platform: Windows"

if (-not (Test-Command 'choco')) {
  Write-Info "choco not found - installing Chocolatey"
  Set-ExecutionPolicy Bypass -Scope Process -Force
  Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
  Import-ChocolateyEnvironment
  Write-Info "Chocolatey install finished"
}
else {
  Write-Info "choco already on PATH - skipping Chocolatey install"
  Import-ChocolateyEnvironment
}

if (-not (Test-Command 'choco')) {
  throw 'choco is still not on PATH. Open a new PowerShell window and re-run install.ps1.'
}

Install-ChocolateyPackages
Import-ChocolateyEnvironment

if (-not (Test-Command 'fnm')) {
  throw 'fnm is still not on PATH. Open a new PowerShell window and re-run install.ps1.'
}
Write-Info "fnm is on PATH"
Install-FnmNodeLts

Write-Info "Verifying tools on PATH"
$missing = @()
foreach ($name in @('jq', 'rg', 'gh', 'az', 'dotnet', 'fnm', 'node', 'npm', 'pwsh')) {
  if (Test-Command $name) {
    Write-Info "$name - ok"
  }
  else {
    Write-Info "$name - missing"
    $missing += $name
  }
}
if ($missing) {
  Write-WarnInfo "Not on PATH yet (a new shell often fixes this): $($missing -join ', ')"
}
else {
  Write-Info "All tools installed and on PATH."
}

Write-Info "Next steps on a fresh system:"
Write-Host ''
Write-Host '  az login'
Write-Host '  gh auth login'
Write-Host ''
Write-Host '  Open a new shell if any tool is missing from PATH, then continue with this repo.'
Write-Host ''
Write-Info "Windows PowerShell bootstrap finished"
