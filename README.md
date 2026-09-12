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
| Node / npm | nodejs-lts | nvm `--lts` | nvm `--lts` |
| PowerShell LTS | powershell-core | packages.microsoft.com / GitHub LTS .deb | powershell cask |

A new shell is often required before every binary is on PATH. Linux also writes `DOTNET_ROOT` to `~/.profile` when the SDK was placed in `~/.dotnet`.

## After install

```text
az login
gh auth login
```

Then continue with this repo from a shell that can see the tools.
