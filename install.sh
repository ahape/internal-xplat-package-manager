#!/usr/bin/env bash
# Unix bootstrap: Debian/Ubuntu (apt) or macOS (Homebrew).
# Node comes from nvm (--lts), not a distro node-lts package.
set -euo pipefail

say() { printf '%s\n' "$*"; }
say_err() { printf 'ERROR: %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

append_unique() {
  # $1=file $2=line. Creates the file when missing.
  local file="$1"
  local line="$2"
  if [ ! -f "$file" ] || ! grep -F -q "$line" "$file"; then
    printf '\n%s\n' "$line" >> "$file"
  fi
}

ensure_profile_path() {
  local snippet="$1"
  append_unique "$HOME/.profile" "$snippet"
  if [ -f "$HOME/.bashrc" ]; then
    append_unique "$HOME/.bashrc" "$snippet"
  fi
  if [ -f "$HOME/.zshrc" ]; then
    append_unique "$HOME/.zshrc" "$snippet"
  fi
}

ensure_brew() {
  if have brew; then
    return 0
  fi
  say 'Homebrew not found; installing...'
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    ensure_profile_path 'eval "$(/opt/homebrew/bin/brew shellenv)"'
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
    ensure_profile_path 'eval "$(/usr/local/bin/brew shellenv)"'
  elif have brew; then
    eval "$(brew shellenv)"
  else
    say_err 'Homebrew installed but brew is not on PATH. Open a new terminal and re-run.'
    exit 1
  fi
}

install_pwsh_lts_macos() {
  if have pwsh; then
    return 0
  fi
  # Cask tracks current stable pwsh, which is the active LTS train.
  # The powershell/tap powershell-lts formula can lag on the previous LTS.
  brew install --cask powershell
}

install_pwsh_lts_linux() {
  if have pwsh; then
    return 0
  fi

  sudo apt-get install -y wget apt-transport-https software-properties-common ca-certificates gnupg
  # packages.microsoft.com layout is ID/VERSION_ID (ubuntu/24.04, debian/12).
  # shellcheck disable=SC1091
  . /etc/os-release
  local prod_deb="/tmp/packages-microsoft-prod.deb"
  if curl -fsSL -o "$prod_deb" "https://packages.microsoft.com/config/${ID}/${VERSION_ID}/packages-microsoft-prod.deb"; then
    sudo dpkg -i "$prod_deb" >/dev/null
    sudo apt-get update
    if apt-cache show powershell-lts >/dev/null 2>&1; then
      sudo apt-get install -y powershell-lts
      return 0
    fi
    if apt-cache show powershell >/dev/null 2>&1; then
      sudo apt-get install -y powershell
      return 0
    fi
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
  tag="$(latest_pwsh_lts_tag)"
  if [ -z "$tag" ] || [ "$tag" = "null" ]; then
    say_err 'Could not resolve the current PowerShell LTS tag from GitHub.'
    return 1
  fi
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      say_err "No PowerShell LTS .deb for architecture $(uname -m)."
      return 1
      ;;
  esac
  deb="powershell_${tag#v}-1.deb_${arch}.deb"
  tmp="/tmp/${deb}"
  curl -fsSL -o "$tmp" "https://github.com/PowerShell/PowerShell/releases/download/${tag}/${deb}"
  sudo dpkg -i "$tmp" || sudo apt-get install -f -y
}

install_nvm_node_lts() {
  # Official installer updates profile files; pin the release so the URL is stable.
  local nvm_version="v0.40.7"
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh" | bash
  fi
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm alias default 'lts/*'
}

install_macos() {
  ensure_brew
  brew update
  # brew install is skip-if-present for already-installed formulae/casks.
  brew install jq ripgrep gh azure-cli
  if ! have dotnet; then
    brew install --cask dotnet-sdk
  fi
  install_pwsh_lts_macos
  install_nvm_node_lts
}

install_linux() {
  if ! have apt-get; then
    say_err 'This script supports Debian/Ubuntu Linux (apt) and macOS (brew) only.'
    exit 1
  fi
  sudo apt-get update
  sudo apt-get install -y curl ca-certificates jq ripgrep gh
  # InstallAzureCLIDeb rewrites Microsoft apt keys/sources on every run.
  if ! have az; then
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  fi
  if ! have dotnet; then
    curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS
  fi
  export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
  if [ -x "$HOME/.dotnet/dotnet" ]; then
    export PATH="$HOME/.dotnet:$PATH"
    if ! grep -F -q 'DOTNET_ROOT' "$HOME/.profile" 2>/dev/null; then
      printf '\nexport DOTNET_ROOT="$HOME/.dotnet"\nexport PATH="$DOTNET_ROOT:$PATH"\n' >> "$HOME/.profile"
    fi
  fi
  install_pwsh_lts_linux
  install_nvm_node_lts
}

check_path() {
  # nvm must be sourced for node/npm. pwsh-lts covers hosts that used the tap formula.
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
  fi

  local missing=""
  local cmd
  for cmd in jq rg gh az dotnet node npm; do
    if ! have "$cmd"; then
      missing="${missing} ${cmd}"
    fi
  done
  if ! have pwsh && ! have pwsh-lts; then
    missing="${missing} pwsh"
  fi
  if [ -n "$missing" ]; then
    say "WARNING: Not on PATH yet (a new shell often fixes this):${missing}"
  else
    say 'All tools installed and on PATH.'
  fi
}

print_next_steps() {
  say 'If this was done on a fresh system, these are your next steps:'
  say ''
  say '  az login'
  say '  gh auth login'
  say ''
  say '  Open a new shell if any tool is missing from PATH, then continue with this repo.'
  say ''
}

uname_s="$(uname -s)"
case "$uname_s" in
  Darwin) install_macos ;;
  Linux) install_linux ;;
  *)
    say_err 'This script supports macOS (brew) and Debian/Ubuntu Linux (apt) only.'
    exit 1
    ;;
esac

check_path
print_next_steps
