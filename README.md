# Bootstrap

Install the toolchain this repo expects. Use the entrypoint for your OS.

## Windows

`install.ps1` runs under native Windows PowerShell 5.1 (`powershell.exe`). pwsh is not required to start the install. It does not use `$PSScriptRoot` or other on-disk script paths, so a remote one-liner works:

```powershell
# Local file
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

# One-shot (in-memory; execution policy does not apply)
iwr -useb https://raw.githubusercontent.com/ahape/internal-xplat-package-manager/HEAD/install.ps1 | iex
```

`install.cmd` is the cmd.exe entrypoint. It bootstraps Chocolatey (via native Windows PowerShell), then installs the same packages including PowerShell LTS.

```bat
install.cmd
```

Windows installs **fnm** (Fast Node Manager) via Chocolatey. It does not configure fnm: no `fnm env` hook, no default version, and no Node LTS install. Run `configure-fnm.ps1` when you need Node/npm.

### Configure Node on Windows (fnm)

`configure-fnm.ps1` is the Node path. Bootstrap only drops the fnm binary. This script snapshots existing globals, uninstalls Chocolatey/MSI Node so `C:\Program Files\nodejs` cannot shadow fnm, renames `%APPDATA%\npm` (does not delete it), wires PowerShell and Git Bash, installs even-numbered LTS, sets `fnm default`, and restores snapshot globals onto that version.

```powershell
# Local file (elevate if a machine-wide Node or a missing fnm must be installed)
powershell -NoProfile -ExecutionPolicy Bypass -File .\configure-fnm.ps1

# One-shot (in-memory; execution policy does not apply)
iwr -useb https://raw.githubusercontent.com/ahape/internal-xplat-package-manager/HEAD/configure-fnm.ps1 | iex
```

It is safe to re-run: missing uninstalls, PATH prepends, and profile hooks are skipped. Open a new shell afterward (sign out if Explorer-launched apps still miss `node`).

Gotchas:

- Stay on even LTS (`fnm install --lts`). Odd Current lines can ship npm 12, which blocks dependency `install` / `postinstall` scripts unless you opt in with `allowScripts`.
- Do not `choco install nodejs` again. That machine PATH entry shadows fnm.
- Pin repos with `.nvmrc` or `.node-version`. `fnm env --use-on-cd` auto-switches; no elevation.
- Globals live per Node version (including `npm link`). A pre-fnm list is written to `%USERPROFILE%\globals.txt` when npm existed.
- `%APPDATA%\fnm\aliases\default` is prepended to the **user** PATH as a stable Explorer/IDE fallback. Interactive shells still win via `fnm env`.

## Linux and macOS

```sh
# Local file
chmod +x ./install.sh
./install.sh

# One-shot (pipe-safe; the script is parsed before apt/brew run)
curl -fsSL https://raw.githubusercontent.com/ahape/internal-xplat-package-manager/HEAD/install.sh | bash
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
| Node / npm | fnm binary; `configure-fnm.ps1` later | nvm `--lts` | nvm `--lts` |
| PowerShell LTS | powershell-core | packages.microsoft.com / GitHub LTS .deb | powershell cask |

A new shell is often required before every binary is on PATH. Linux also writes `DOTNET_ROOT` to `~/.profile` when the SDK was placed in `~/.dotnet`.

The scripts are safe to re-run: package managers skip or no-op when a tool is already present, and profile/hook writes are guarded so they do not accumulate. Each entrypoint prints `[INFO]` lines for every major step, including skips.

## After install

```text
az login
gh auth login
```

On Windows, run `configure-fnm.ps1` before you need Node. Unix `install.sh` still installs Node LTS through nvm during bootstrap.

Then continue with this repo from a shell that can see the tools.
