#!/usr/bin/env pwsh
#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# TODO - What needs to be different that what's already here:
# Split this into a .sh script and a .cmd script
#  - Tasks for both files
#   * include pwsh latest LTS
#  - Tasks for .sh file
#   * support MacOS variant w/in .sh path (brew)
#   * install nvm instead of node-lts
#  - Tasks for .ps1 file
#   * min req = powershell (native) as the shell executing the installation script

if ($IsWindows) {
    if (-not (Get-Command choco -ErrorAction Ignore)) {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
    choco install -y jq ripgrep gh azure-cli dotnet-sdk nodejs-lts
}
elseif ($IsLinux) {
    sudo apt-get update
    sudo apt-get install -y curl ca-certificates jq ripgrep gh          # all in the distro archive
    bash -c 'curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash'    # az: registers repo + installs
    bash -c 'curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo bash -'  # node: registers repo
    sudo apt-get install -y nodejs
    bash -c 'curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS'  # -> ~/.dotnet
    $env:DOTNET_ROOT = "$HOME/.dotnet"; $env:PATH = "$env:DOTNET_ROOT`:$env:PATH"
    if (-not (Select-String -Path "$HOME/.profile" -SimpleMatch 'DOTNET_ROOT' -Quiet -ErrorAction Ignore)) {
        Add-Content "$HOME/.profile" "`nexport DOTNET_ROOT=`"`$HOME/.dotnet`"`nexport PATH=`"`$DOTNET_ROOT:`$PATH`""
    }
}
else { throw 'This script supports Windows (choco) and Debian/Ubuntu Linux (apt) only.' }

$missing = ('jq','rg','gh','az','dotnet','node','npm').Where{ -not (Get-Command $_ -ErrorAction Ignore) }
if ($missing) { Write-Warning "Not on PATH yet (a new shell often fixes this): $($missing -join ', ')" }
else { Write-Host 'All tools installed and on PATH.' }

Write-Host 'If this was done on a fresh system, these are your next steps:'
Write-Host ''
Write-Host '  az login'
Write-Host '  gh auth login'
Write-Host ''
Write-Host '  $installer = gh api https://github.com/<owner>/<this-repo>/install.ps1 -H "Accept: application/vnd.github.raw" | Out-String'
Write-Host '  Invoke-Expression $installer'
Write-Host ''
