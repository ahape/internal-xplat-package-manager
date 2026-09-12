#!/usr/bin/env bash
# Unix bootstrap: Debian/Ubuntu (apt) or macOS (Homebrew).
# Node comes from nvm (--lts), not a distro node-lts package.
set -euo pipefail

log_info() { printf '[INFO] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_err() { printf '[ERROR] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

append_unique() {
  # $1=file $2=line. Creates the file when missing.
  local file="$1"
  local line="$2"
  if [ ! -f "$file" ] || ! grep -F -q "$line" "$file"; then
    log_info "Writing profile hook to $file"
    printf '\n%s\n' "$line" >> "$file"
  else
    log_info "Profile hook already present in $file - skipping"
  fi
}

ensure_profile_path() {
  local snippet="$1"
  append_unique "$HOME/.profile" "$snippet"
  if [ -f "$HOME/.bashrc" ]; then
    append_unique "$HOME/.bashrc" "$snippet"
  else
    log_info "$HOME/.bashrc not found - skipping brew hook there"
  fi
  if [ -f "$HOME/.zshrc" ]; then
    append_unique "$HOME/.zshrc" "$snippet"
  else
    log_info "$HOME/.zshrc not found - skipping brew hook there"
  fi
}

ensure_brew() {
  if have brew; then
    log_info "brew already on PATH - skipping Homebrew install"
    return 0
  fi
  log_info "Homebrew not found - installing"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /opt/homebrew/bin/brew ]; then
    log_info "Detected Apple Silicon Homebrew at /opt/homebrew - adding to PATH and profiles"
    eval "$(/opt/homebrew/bin/brew shellenv)"
    ensure_profile_path 'eval "$(/opt/homebrew/bin/brew shellenv)"'
  elif [ -x /usr/local/bin/brew ]; then
    log_info "Detected Intel Homebrew at /usr/local - adding to PATH and profiles"
    eval "$(/usr/local/bin/brew shellenv)"
    ensure_profile_path 'eval "$(/usr/local/bin/brew shellenv)"'
  elif have brew; then
    log_info "Homebrew installed - evaluating brew shellenv for this session"
    eval "$(brew shellenv)"
  else
    log_err 'Homebrew installed but brew is not on PATH. Open a new terminal and re-run.'
    exit 1
  fi
}

install_pwsh_lts_macos() {
  if have pwsh; then
    log_info "pwsh already on PATH - skipping PowerShell LTS install"
    return 0
  fi
  # Cask tracks current stable pwsh, which is the active LTS train.
  # The powershell/tap powershell-lts formula can lag on the previous LTS.
  log_info "Installing PowerShell LTS via Homebrew cask powershell"
  brew install --cask powershell
}

install_pwsh_lts_linux() {
  if have pwsh; then
    log_info "pwsh already on PATH - skipping PowerShell LTS install"
    return 0
  fi

  log_info "Installing apt prerequisites for the Microsoft package repo"
  sudo apt-get install -y wget apt-transport-https software-properties-common ca-certificates gnupg
  # packages.microsoft.com layout is ID/VERSION_ID (ubuntu/24.04, debian/12).
  # shellcheck disable=SC1091
  . /etc/os-release
  log_info "Registering packages.microsoft.com for ${ID} ${VERSION_ID}"
  local prod_deb="/tmp/packages-microsoft-prod.deb"
  if curl -fsSL -o "$prod_deb" "https://packages.microsoft.com/config/${ID}/${VERSION_ID}/packages-microsoft-prod.deb"; then
    sudo dpkg -i "$prod_deb" >/dev/null
    sudo apt-get update
    if apt-cache show powershell-lts >/dev/null 2>&1; then
      log_info "Installing PowerShell LTS via apt package powershell-lts"
      sudo apt-get install -y powershell-lts
      return 0
    fi
    if apt-cache show powershell >/dev/null 2>&1; then
      log_info "powershell-lts not in this repo - installing apt package powershell"
      sudo apt-get install -y powershell
      return 0
    fi
    log_info "Microsoft apt repo has no powershell package - falling back to GitHub LTS .deb"
  else
    log_info "Could not download packages-microsoft-prod.deb - falling back to GitHub LTS .deb"
  fi

  install_pwsh_lts_from_github_deb
}

latest_pwsh_lts_tag() {
  # PowerShell LTS follows even-numbered minors (7.4, 7.6). GitHub lists newest first.
  # aka.ms/powershell-release?tag=lts can still advertise the previous LTS line.
  curl -fsSL 'https://api.github.com/repos/PowerShell/PowerShell/releases?per_page=30' |
    jq -r '[.[] | select(.prerelease|not) | .tag_name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))] | map(select((split(".")[1] | tonumber) % 2 == 0)) | .[0]'
}

install_pwsh_lts_from_github_deb() {
  local tag arch deb tmp
  log_info "Resolving current PowerShell LTS tag from GitHub"
  tag="$(latest_pwsh_lts_tag)"
  if [ -z "$tag" ] || [ "$tag" = "null" ]; then
    log_err 'Could not resolve the current PowerShell LTS tag from GitHub.'
    return 1
  fi
  log_info "PowerShell LTS tag is $tag"
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      log_err "No PowerShell LTS .deb for architecture $(uname -m)."
      return 1
      ;;
  esac
  deb="powershell_${tag#v}-1.deb_${arch}.deb"
  tmp="/tmp/${deb}"
  log_info "Installing PowerShell LTS from GitHub package $deb"
  curl -fsSL -o "$tmp" "https://github.com/PowerShell/PowerShell/releases/download/${tag}/${deb}"
  sudo dpkg -i "$tmp" || sudo apt-get install -f -y
}

install_nvm_node_lts() {
  # Official installer updates profile files; pin the release so the URL is stable.
  local nvm_version="v0.40.7"
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    log_info "nvm not found - installing $nvm_version"
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh" | bash
  else
    log_info "nvm already installed at $NVM_DIR - skipping nvm installer"
  fi
  log_info "Loading nvm"
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  if have node; then
    log_info "node already on PATH - ensuring Node LTS via nvm (no-op if present)"
  else
    log_info "Installing Node LTS via nvm"
  fi
  nvm install --lts
  log_info "Setting nvm default alias to lts/*"
  nvm alias default 'lts/*'
}

ensure_brew_pkg() {
  local formula="$1"
  local cmd="$2"
  if have "$cmd"; then
    log_info "$cmd already on PATH - skipping Homebrew package $formula"
    return 0
  fi
  log_info "Installing $formula via Homebrew (provides $cmd)"
  brew install "$formula"
}

install_macos() {
  log_info "Using macOS path (Homebrew)"
  ensure_brew
  log_info "Updating Homebrew"
  brew update
  ensure_brew_pkg jq jq
  ensure_brew_pkg ripgrep rg
  ensure_brew_pkg gh gh
  ensure_brew_pkg azure-cli az
  if have dotnet; then
    log_info "dotnet already on PATH - skipping Homebrew cask dotnet-sdk"
  else
    log_info "Installing .NET SDK LTS via Homebrew cask dotnet-sdk"
    brew install --cask dotnet-sdk
  fi
  install_pwsh_lts_macos
  install_nvm_node_lts
}

ensure_apt_pkg() {
  local pkg="$1"
  local cmd="$2"
  if have "$cmd"; then
    log_info "$cmd already on PATH - skipping apt package $pkg"
    return 0
  fi
  log_info "Installing $pkg via apt (provides $cmd)"
  sudo apt-get install -y "$pkg"
}

install_linux() {
  log_info "Using Debian/Ubuntu path (apt)"
  if ! have apt-get; then
    log_err 'This script supports Debian/Ubuntu Linux (apt) and macOS (brew) only.'
    exit 1
  fi
  log_info "Refreshing apt package lists"
  sudo apt-get update
  log_info "Ensuring apt prerequisites (curl, ca-certificates)"
  sudo apt-get install -y curl ca-certificates
  ensure_apt_pkg jq jq
  ensure_apt_pkg ripgrep rg
  ensure_apt_pkg gh gh
  # InstallAzureCLIDeb rewrites Microsoft apt keys/sources on every run.
  if have az; then
    log_info "az already on PATH - skipping Azure CLI Deb installer"
  else
    log_info "Installing Azure CLI via InstallAzureCLIDeb"
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  fi
  if have dotnet; then
    log_info "dotnet already on PATH - skipping dotnet-install.sh"
  else
    log_info "Installing .NET SDK LTS via dotnet-install.sh"
    curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS
  fi
  export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
  if [ -x "$HOME/.dotnet/dotnet" ]; then
    log_info "Adding $HOME/.dotnet to this session PATH"
    export PATH="$HOME/.dotnet:$PATH"
    if ! grep -F -q 'DOTNET_ROOT' "$HOME/.profile" 2>/dev/null; then
      log_info "Writing DOTNET_ROOT hook to $HOME/.profile"
      printf '\nexport DOTNET_ROOT="$HOME/.dotnet"\nexport PATH="$DOTNET_ROOT:$PATH"\n' >> "$HOME/.profile"
    else
      log_info "DOTNET_ROOT already in $HOME/.profile - skipping"
    fi
  else
    log_info "No $HOME/.dotnet/dotnet on disk - skipping DOTNET_ROOT profile hook"
  fi
  install_pwsh_lts_linux
  install_nvm_node_lts
}

check_path() {
  # nvm must be sourced for node/npm. pwsh-lts covers hosts that used the tap formula.
  log_info "Verifying tools on PATH"
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    log_info "Loading nvm for PATH verification"
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
  fi

  local missing=""
  local cmd
  for cmd in jq rg gh az dotnet node npm; do
    if have "$cmd"; then
      log_info "$cmd - ok"
    else
      log_info "$cmd - missing"
      missing="${missing} ${cmd}"
    fi
  done
  if have pwsh || have pwsh-lts; then
    log_info "pwsh - ok"
  else
    log_info "pwsh - missing"
    missing="${missing} pwsh"
  fi
  if [ -n "$missing" ]; then
    log_warn "Not on PATH yet (a new shell often fixes this):${missing}"
  else
    log_info "All tools installed and on PATH."
  fi
}

print_next_steps() {
  log_info "Next steps on a fresh system:"
  printf '%s\n' ''
  printf '%s\n' '  az login'
  printf '%s\n' '  gh auth login'
  printf '%s\n' ''
  printf '%s\n' '  Open a new shell if any tool is missing from PATH, then continue with this repo.'
  printf '%s\n' ''
}

log_info "Starting Unix bootstrap"
uname_s="$(uname -s)"
log_info "Detected OS: $uname_s ($(uname -m))"
case "$uname_s" in
  Darwin) install_macos ;;
  Linux) install_linux ;;
  *)
    log_err 'This script supports macOS (brew) and Debian/Ubuntu Linux (apt) only.'
    exit 1
    ;;
esac

check_path
print_next_steps
log_info "Unix bootstrap finished"
