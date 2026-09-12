#Requires -Version 5.1
# Windows bootstrap. Runs under native Windows PowerShell 5.1 (powershell.exe);
# pwsh is not required to execute this script.
# fnm is installed via Chocolatey; Node/npm setup through fnm is a later step.

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
  # fnm is installed only; Node/npm via fnm is a later manual step.
  # Native command failures do not honor $ErrorActionPreference on Windows PowerShell 5.1.
  & choco install -y @toInstall
  Assert-NativeExitCode -CommandName 'choco install'
  Write-Info "Chocolatey package install finished"
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
Write-Info "fnm is on PATH - not configuring it (no Node install, no profile hooks)"

Write-Info "Verifying tools on PATH"
$missing = @()
foreach ($name in @('jq', 'rg', 'gh', 'az', 'dotnet', 'fnm', 'pwsh')) {
  if (Test-Command $name) {
    Write-Info "$name - ok"
  }
  else {
    Write-Info "$name - missing"
    $missing += $name
  }
}
foreach ($name in @('node', 'npm')) {
  if (Test-Command $name) {
    Write-Info "$name - ok (already present; this script does not configure fnm)"
  }
  else {
    Write-Info "$name - not configured yet (fnm is installed; set it up later)"
  }
}
if ($missing) {
  Write-WarnInfo "Not on PATH yet (a new shell often fixes this): $($missing -join ', ')"
}
else {
  Write-Info "Required tools installed and on PATH. Node/npm come after you configure fnm."
}

Write-Info "Next steps on a fresh system:"
Write-Host ''
Write-Host '  az login'
Write-Host '  gh auth login'
Write-Host ''
Write-Host '  Configure Node later with configure-fnm.ps1 (not done by this script).'
Write-Host ''
Write-Host '  Open a new shell if any required tool is missing from PATH.'
Write-Host ''
Write-Info "Windows PowerShell bootstrap finished"
