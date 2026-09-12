@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Windows cmd entrypoint. Native Windows PowerShell is used only to
rem bootstrap Chocolatey; the rest of the install is choco from cmd.
rem PowerShell LTS is installed as the powershell-core package (pwsh).

call :log_info "Starting Windows bootstrap (cmd.exe)"
call :log_info "Detected platform: Windows"

where powershell >nul 2>&1
if errorlevel 1 (
  call :log_err "Native Windows PowerShell is required to bootstrap Chocolatey."
  echo It ships with Windows and must be the shell that can run install.ps1.
  exit /b 1
)
call :log_info "Native Windows PowerShell is available"

where choco >nul 2>&1
if errorlevel 1 (
  call :log_info "choco not found - installing Chocolatey"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
  if errorlevel 1 (
    call :log_err "Chocolatey install failed."
    exit /b 1
  )
  call :log_info "Chocolatey install finished"
) else (
  call :log_info "choco already on PATH - skipping Chocolatey install"
)

call :ensure_choco_path

where choco >nul 2>&1
if errorlevel 1 (
  call :log_err "choco is still not on PATH. Open a new Command Prompt and re-run install.cmd."
  exit /b 1
)

rem powershell-core is the Chocolatey id for pwsh; current stable is the LTS train.
rem fnm is installed here; Node/npm via fnm is a later manual step.
set "CHOCO_PKGS="
call :queue_choco jq jq
call :queue_choco rg ripgrep
call :queue_choco gh gh
call :queue_choco az azure-cli
call :queue_choco dotnet dotnet-sdk
call :queue_choco pwsh powershell-core
call :queue_choco fnm fnm

if defined CHOCO_PKGS (
  call :log_info "Installing Chocolatey packages:!CHOCO_PKGS!"
  choco install -y !CHOCO_PKGS!
  set "CHOCO_EXIT=!ERRORLEVEL!"
  if not "!CHOCO_EXIT!"=="0" if not "!CHOCO_EXIT!"=="3010" (
    call :log_err "choco install failed with exit !CHOCO_EXIT!."
    exit /b !CHOCO_EXIT!
  )
  call :log_info "Chocolatey package install finished (exit !CHOCO_EXIT!)"
) else (
  call :log_info "All Chocolatey packages already on PATH - skipping choco install"
)

call :ensure_choco_path

where fnm >nul 2>&1
if errorlevel 1 (
  call :log_err "fnm is still not on PATH. Open a new Command Prompt and re-run install.cmd."
  exit /b 1
)
call :log_info "fnm is on PATH - not configuring it (no Node install, no profile hooks)"

call :log_info "Verifying tools on PATH"
set "MISSING="
for %%C in (jq rg gh az dotnet fnm pwsh) do (
  where %%C >nul 2>&1
  if errorlevel 1 (
    call :log_info "%%C - missing"
    set "MISSING=!MISSING! %%C"
  ) else (
    call :log_info "%%C - ok"
  )
)

where node >nul 2>&1
if errorlevel 1 (
  call :log_info "node - not configured yet (fnm is installed; set it up later)"
) else (
  call :log_info "node - ok (already present; this script does not configure fnm)"
)
where npm >nul 2>&1
if errorlevel 1 (
  call :log_info "npm - not configured yet (fnm is installed; set it up later)"
) else (
  call :log_info "npm - ok (already present; this script does not configure fnm)"
)

if defined MISSING (
  call :log_warn "Not on PATH yet (a new shell often fixes this):!MISSING!"
) else (
  call :log_info "Required tools installed and on PATH. Node/npm come after you configure fnm."
)

call :log_info "Next steps on a fresh system:"
echo.
echo   az login
echo   gh auth login
echo.
echo   Configure Node later with configure-fnm.ps1 (not done by this script).
echo.
echo   Open a new shell if any required tool is missing from PATH.
echo.

call :log_info "Windows cmd bootstrap finished"
endlocal
exit /b 0

:log_info
echo [INFO] %*
exit /b 0

:log_warn
echo [WARN] %*
exit /b 0

:log_err
echo [ERROR] %*
exit /b 0

:ensure_choco_path
if exist "%ALLUSERSPROFILE%\chocolatey\bin\" (
  echo ;%PATH%; | find /I ";%ALLUSERSPROFILE%\chocolatey\bin;" >nul
  if errorlevel 1 (
    call :log_info "Adding Chocolatey bin to this session PATH"
    set "PATH=%ALLUSERSPROFILE%\chocolatey\bin;%PATH%"
  ) else (
    call :log_info "Chocolatey bin already on PATH - skipping prepend"
  )
) else (
  call :log_info "Chocolatey bin directory not found yet - skipping PATH prepend"
)
exit /b 0

:queue_choco
rem %1 = command name, %2 = Chocolatey package id
where %1 >nul 2>&1
if errorlevel 1 (
  call :log_info "Queuing Chocolatey package %2 (provides %1)"
  set "CHOCO_PKGS=!CHOCO_PKGS! %2"
) else (
  call :log_info "%1 already on PATH - skipping Chocolatey package %2"
)
exit /b 0
