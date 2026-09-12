#Requires -Version 5.1
# Windows bootstrap. Runs under native Windows PowerShell 5.1 (powershell.exe);
# pwsh is not required to execute this script.
$ErrorActionPreference = 'Stop'

# TLS 1.2 is off by default on some Windows PowerShell 5.1 hosts.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

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
      $env:PATH = "$chocoBin;$env:PATH"
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

function Assert-NativeExitCode {
  param(
    [string]$CommandName,
    [int[]]$SuccessCodes = @(0, 3010)
  )
  if ($SuccessCodes -notcontains $LASTEXITCODE) {
    throw "$CommandName failed with exit $LASTEXITCODE"
  }
}

if (-not (Test-Command 'choco')) {
  Set-ExecutionPolicy Bypass -Scope Process -Force
  Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
  Import-ChocolateyEnvironment
}

if (-not (Test-Command 'choco')) {
  throw 'choco is still not on PATH. Open a new PowerShell window and re-run install.ps1.'
}

# powershell-core is the Chocolatey id for pwsh; current stable is the LTS train.
# Native command failures do not honor $ErrorActionPreference on Windows PowerShell 5.1.
choco install -y jq ripgrep gh azure-cli dotnet-sdk nodejs-lts powershell-core
Assert-NativeExitCode -CommandName 'choco install'
Import-ChocolateyEnvironment

$missing = @('jq', 'rg', 'gh', 'az', 'dotnet', 'node', 'npm', 'pwsh') | Where-Object { -not (Test-Command $_) }
if ($missing) {
  Write-Warning "Not on PATH yet (a new shell often fixes this): $($missing -join ', ')"
}
else {
  Write-Host 'All tools installed and on PATH.'
}

Write-Host 'If this was done on a fresh system, these are your next steps:'
Write-Host ''
Write-Host '  az login'
Write-Host '  gh auth login'
Write-Host ''
Write-Host '  Open a new shell if any tool is missing from PATH, then continue with this repo.'
Write-Host ''
