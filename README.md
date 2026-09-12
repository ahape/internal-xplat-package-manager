# Bootstrap

Install the toolchain this repo expects. Use the entrypoint for your OS.

## Windows

`install.ps1` runs under native Windows PowerShell 5.1 (`powershell.exe`). pwsh is not required to start the install.

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

`install.cmd` is the cmd.exe entrypoint. It bootstraps Chocolatey (via native Windows PowerShell), then installs the same packages including PowerShell LTS.

```bat
install.cmd
```

Windows installs Node through **fnm** (Fast Node Manager), not a direct `nodejs-lts` Chocolatey package. After `choco install fnm`, the scripts run `fnm install --lts` and add the official `fnm env --use-on-cd` hook to Windows PowerShell 5.1 and pwsh profiles. `install.cmd` also evaluates `fnm env` in the current session so `node`/`npm` are on PATH for the post-install check.

New cmd.exe windows do not load PowerShell profiles. To get the same hook in cmd, add the [fnm WinCMD snippet](https://github.com/Schniz/fnm#windows-command-prompt-aka-batch-aka-wincmd) to your cmd startup script.

## Linux and macOS

```sh
chmod +x ./install.sh
./install.sh
```

- Debian/Ubuntu: apt, plus Microsoft/dotnet installers where the distro archive does not ship the tool.
- macOS: Homebrew (the script installs brew when it is missing).
- Both Unix paths install PowerShell LTS (`pwsh`) and Node via nvm (`nvm install --lts`), not a distro node-lts package.

## Packages

| Tool | Windows (choco) | Linux (apt / installer) | macOS (brew) |
| --- | --- | --- | --- |
| jq | jq | jq | jq |
| ripgrep | ripgrep | ripgrep | ripgrep |
| GitHub CLI | gh | gh | gh |
| Azure CLI | azure-cli | InstallAzureCLIDeb | azure-cli |
| .NET SDK (LTS) | dotnet-sdk | dotnet-install.sh | dotnet-sdk cask |
| Node / npm | fnm `--lts` | nvm `--lts` | nvm `--lts` |
| PowerShell LTS | powershell-core | packages.microsoft.com / GitHub LTS .deb | powershell cask |

A new shell is often required before every binary is on PATH. Linux also writes `DOTNET_ROOT` to `~/.profile` when the SDK was placed in `~/.dotnet`.

The scripts are safe to re-run: package managers skip or no-op when a tool is already present, and profile/hook writes are guarded so they do not accumulate. Each entrypoint prints `[INFO]` lines for every major step, including skips.

## After install

```text
az login
gh auth login
```

Then continue with this repo from a shell that can see the tools.
