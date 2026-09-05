#!/bin/bash
# ============================================================================
# Regents CLI Installer
# ============================================================================
# Installation script for macOS and Linux.
#
# Usage:
#   curl -fsSL https://regents.sh/install.sh | bash
#
# Or with options:
#   curl -fsSL https://regents.sh/install.sh | bash -s -- --skip-setup
#
# Options:
#   --skip-setup        Install the CLI but do not run the setup wizard.
#   --quick             Run setup without prompts (only missing pieces).
#   --version <v>       Install a specific @regentslabs/cli version.
#
# The canonical copy of this script lives in regents-cli/scripts/install.sh.
# The copy served at https://regents.sh/install.sh is a generated artifact
# refreshed by scripts/sync-contract-artifacts.sh; the pinned version below is
# updated as part of each CLI release.
# ============================================================================

set -e

# Pinned release. The script is the lockfile: each release republishes this
# script with the new pin. Override with REGENTS_CLI_VERSION for testing.
REGENTS_CLI_VERSION="${REGENTS_CLI_VERSION:-0.5.0}"
NODE_MIN_MAJOR=22

# Colors (disabled when stdout is not a terminal)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    RED='\033[0;31m'
    CYAN='\033[0;36m'
    NC='\033[0m'
    BOLD='\033[1m'
else
    GREEN='' YELLOW='' RED='' CYAN='' NC='' BOLD=''
fi

log_info()    { printf "${CYAN}→${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}✓${NC} %s\n" "$1"; }
log_warn()    { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
log_error()   { printf "${RED}✗${NC} %s\n" "$1" >&2; }

print_banner() {
    printf "\n"
    printf "${BOLD}┌─────────────────────────────────────────────┐${NC}\n"
    printf "${BOLD}│            Regents CLI Installer            │${NC}\n"
    printf "${BOLD}├─────────────────────────────────────────────┤${NC}\n"
    printf "${BOLD}│  Agent companies on your own machine.       │${NC}\n"
    printf "${BOLD}└─────────────────────────────────────────────┘${NC}\n"
    printf "\n"
}

usage() {
    cat <<'EOF'
Regents CLI installer

Usage:
  curl -fsSL https://regents.sh/install.sh | bash
  curl -fsSL https://regents.sh/install.sh | bash -s -- [options]

Options:
  --skip-setup     Install the CLI but do not run the setup wizard.
  --quick          Run setup without prompts (only missing pieces).
  --version <v>    Install a specific @regentslabs/cli version.
  --help           Show this help.

Uninstall:
  npm uninstall -g @regentslabs/cli
EOF
}

# Friendly failure message instead of a silent abort from `set -e`.
on_error() {
    local exit_code=$?
    printf "\n"
    log_error "Installation did not finish (exit ${exit_code})."
    log_info "Nothing partial is left running. Re-running the installer is safe."
    log_info "If this keeps happening, see https://regents.sh/learn or file: regents bug"
    exit "$exit_code"
}
trap on_error ERR

# Options
RUN_SETUP=true
QUICK_SETUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-setup)
            RUN_SETUP=false
            shift
            ;;
        --quick)
            QUICK_SETUP=true
            shift
            ;;
        --version)
            REGENTS_CLI_VERSION="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_warn "Unknown option: $1 (ignored)"
            shift
            ;;
    esac
done

detect_os() {
    case "$(uname -s)" in
        Darwin)
            OS="macos"
            log_success "Detected: macOS"
            ;;
        Linux)
            OS="linux"
            log_success "Detected: Linux"
            ;;
        *)
            log_error "Unsupported operating system: $(uname -s). Regents CLI supports macOS and Linux."
            exit 1
            ;;
    esac
}

check_node() {
    log_info "Checking Node.js ${NODE_MIN_MAJOR}+..."
    if ! command -v node >/dev/null 2>&1; then
        log_error "Node.js ${NODE_MIN_MAJOR} or newer is required but was not found."
        if [ "$OS" = "macos" ]; then
            log_info "Install it with: brew install node"
        else
            log_info "Install it from https://nodejs.org or your package manager."
        fi
        exit 1
    fi

    node_version="$(node --version)"
    node_major="${node_version#v}"
    node_major="${node_major%%.*}"
    if [ "$node_major" -lt "$NODE_MIN_MAJOR" ] 2>/dev/null; then
        log_error "Node.js ${NODE_MIN_MAJOR}+ is required (found ${node_version})."
        exit 1
    fi
    log_success "Node.js ${node_version} found"

    if ! command -v npm >/dev/null 2>&1; then
        log_error "npm is required but was not found alongside Node.js."
        exit 1
    fi
    log_success "npm $(npm --version) found"
}

check_network() {
    log_info "Checking npm registry connectivity..."
    if ! npm ping >/dev/null 2>&1; then
        log_warn "Could not reach the npm registry. Continuing — npm will retry during install."
    else
        log_success "npm registry reachable"
    fi
}

install_cli() {
    if command -v regents >/dev/null 2>&1; then
        current_version="$(npm ls -g @regentslabs/cli --depth=0 2>/dev/null | grep -o '@regentslabs/cli@[0-9][^ ]*' | head -1 | cut -d@ -f3)"
        log_info "Existing installation found (${current_version:-unknown}), updating to ${REGENTS_CLI_VERSION}..."
    else
        log_info "Installing @regentslabs/cli@${REGENTS_CLI_VERSION}..."
    fi

    if ! npm install -g "@regentslabs/cli@${REGENTS_CLI_VERSION}"; then
        # The most common global-install failure is a permissions error on the
        # npm global prefix (EACCES). Give the standard fixes instead of a
        # raw npm stack trace.
        printf "\n"
        log_error "npm could not install the package globally."
        log_info "If this was a permissions error (EACCES), either:"
        log_info "  1. Use a Node version manager (fnm, nvm, volta) and re-run this installer, or"
        log_info "  2. Point npm at a user-writable prefix:"
        log_info "       mkdir -p ~/.npm-global && npm config set prefix ~/.npm-global"
        log_info "       export PATH=\"\$HOME/.npm-global/bin:\$PATH\""
        log_info "  then re-run: curl -fsSL https://regents.sh/install.sh | bash"
        exit 1
    fi
    log_success "Regents CLI ${REGENTS_CLI_VERSION} installed"
}

check_path() {
    if command -v regents >/dev/null 2>&1; then
        log_success "regents command ready"
        return 0
    fi

    npm_bin="$(npm bin -g 2>/dev/null || true)"
    if [ -z "$npm_bin" ]; then
        npm_prefix="$(npm prefix -g 2>/dev/null || true)"
        npm_bin="${npm_prefix}/bin"
    fi
    log_warn "The regents command is not on your PATH."
    log_info "Add the npm global bin directory to PATH, for example:"
    log_info "  export PATH=\"${npm_bin}:\$PATH\""
    return 1
}

run_setup_wizard() {
    if [ "$RUN_SETUP" != true ]; then
        log_info "Skipping setup (--skip-setup). Run 'regents setup' when you're ready."
        return 0
    fi

    if [ "$QUICK_SETUP" = true ]; then
        log_info "Running quick setup (no prompts)..."
        regents setup --quick || log_warn "Quick setup reported a problem. Run 'regents setup' to review."
        return 0
    fi

    # Under `curl | bash`, stdin is the pipe — reattach to the terminal so the
    # wizard can prompt, exactly like the Hermes installer does.
    if [ -e /dev/tty ] && [ -t 1 ]; then
        log_info "Starting setup wizard..."
        regents setup </dev/tty || log_warn "Setup wizard exited early. Run 'regents setup' to finish."
    else
        log_info "No interactive terminal available."
        log_info "Run 'regents setup' to wire up your agent runtimes, or 'regents setup --quick' for the no-prompt path."
    fi
}

print_success() {
    printf "\n"
    log_success "Regents CLI is installed."
    printf "\n"
    printf "  ${BOLD}Next steps${NC}\n"
    printf "    regents setup            wire Regents into your agent runtimes\n"
    printf "    regents identity ensure  set up your Regent identity\n"
    printf "    regents doctor           check that everything is healthy\n"
    printf "    regents --help           see every command\n"
    printf "\n"
    printf "  Update later with 'regents update'. Uninstall with 'npm uninstall -g @regentslabs/cli'.\n"
    printf "\n"
}

main() {
    print_banner
    detect_os
    check_node
    check_network
    install_cli
    check_path || true
    run_setup_wizard
    print_success
}

main
