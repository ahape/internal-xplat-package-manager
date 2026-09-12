@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Windows cmd entrypoint. Native Windows PowerShell is used only to
rem bootstrap Chocolatey; the rest of the install is choco from cmd.
rem PowerShell LTS is installed as the powershell-core package (pwsh).

where powershell >nul 2>&1
if errorlevel 1 (
  echo Native Windows PowerShell is required to bootstrap Chocolatey.
  echo It ships with Windows and must be the shell that can run install.ps1.
  exit /b 1
)

where choco >nul 2>&1
if errorlevel 1 (
  echo Chocolatey not found; installing...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
  if errorlevel 1 (
    echo Chocolatey install failed.
    exit /b 1
  )
)

rem RefreshEnv.cmd uses its own setlocal and can drop delayed expansion.
if exist "%ALLUSERSPROFILE%\chocolatey\bin\" (
  set "PATH=%ALLUSERSPROFILE%\chocolatey\bin;%PATH%"
)

where choco >nul 2>&1
if errorlevel 1 (
  echo choco is still not on PATH. Open a new Command Prompt and re-run install.cmd.
  exit /b 1
)

rem powershell-core is the Chocolatey id for pwsh; current stable is the LTS train.
choco install -y jq ripgrep gh azure-cli dotnet-sdk nodejs-lts powershell-core
set "CHOCO_EXIT=%ERRORLEVEL%"
if not "%CHOCO_EXIT%"=="0" if not "%CHOCO_EXIT%"=="3010" (
  echo choco install failed with exit %CHOCO_EXIT%.
  exit /b %CHOCO_EXIT%
)

if exist "%ALLUSERSPROFILE%\chocolatey\bin\" (
  set "PATH=%ALLUSERSPROFILE%\chocolatey\bin;%PATH%"
)

set "MISSING="
for %%C in (jq rg gh az dotnet node npm pwsh) do (
  where %%C >nul 2>&1
  if errorlevel 1 set "MISSING=!MISSING! %%C"
)

if defined MISSING (
  echo WARNING: Not on PATH yet (a new shell often fixes this):!MISSING!
) else (
  echo All tools installed and on PATH.
)

echo If this was done on a fresh system, these are your next steps:
echo.
echo   az login
echo   gh auth login
echo.
echo   Open a new shell if any tool is missing from PATH, then continue with this repo.
echo.

endlocal
exit /b 0
