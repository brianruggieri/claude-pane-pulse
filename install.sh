#!/usr/bin/env bash
# install.sh - Claude Pane Pulse installer
# Installs ccp to ~/.local/share/ccp and creates a symlink in ~/bin

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="${HOME}/.local/share/ccp"
BIN_DIR="${HOME}/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Claude Pane Pulse${NC} - Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Validate source directory ─────────────────────────────────────────────────

if [[ ! -f "${SCRIPT_DIR}/bin/ccp" ]]; then
    echo -e "${RED}✗ Error:${NC} bin/ccp not found. Run from the claude-pane-pulse project root." >&2
    exit 1
fi

if [[ ! -d "${SCRIPT_DIR}/lib" ]]; then
    echo -e "${RED}✗ Error:${NC} lib/ directory not found. Run from the claude-pane-pulse project root." >&2
    exit 1
fi

# ── Install files ─────────────────────────────────────────────────────────────

echo -e "${BLUE}Installing files...${NC}"

# Create install directory structure
mkdir -p "${INSTALL_DIR}/bin"
mkdir -p "${INSTALL_DIR}/lib"

# Copy files
cp "${SCRIPT_DIR}/bin/ccp" "${INSTALL_DIR}/bin/ccp"
cp "${SCRIPT_DIR}"/lib/*.sh "${INSTALL_DIR}/lib/"
cp "${SCRIPT_DIR}"/lib/*.py "${INSTALL_DIR}/lib/" 2>/dev/null || true
chmod +x "${INSTALL_DIR}/bin/ccp"

echo -e "  ${GREEN}✓${NC} Installed to ${INSTALL_DIR}"

# ── Create ~/bin symlink ──────────────────────────────────────────────────────

mkdir -p "${BIN_DIR}"

if [[ -L "${BIN_DIR}/ccp" ]]; then
    rm "${BIN_DIR}/ccp"
fi

ln -s "${INSTALL_DIR}/bin/ccp" "${BIN_DIR}/ccp"
echo -e "  ${GREEN}✓${NC} Symlink created: ${BIN_DIR}/ccp"

# ── Update PATH in shell profile ──────────────────────────────────────────────

add_path_to_profile() {
    local profile="$1"
    # shellcheck disable=SC2016  # intentional: literal ${HOME} for user's shell profile
    local path_line='export PATH="${HOME}/bin:${PATH}"'

    if [[ -f "${profile}" ]]; then
        if ! grep -q 'HOME.*bin.*PATH\|PATH.*HOME.*bin' "${profile}" 2>/dev/null; then
            {
                echo ""
                echo "# Added by claude-pane-pulse installer"
                echo "${path_line}"
            } >> "${profile}"
            echo -e "  ${GREEN}✓${NC} Added ~/bin to PATH in ${profile}"
            return 0
        else
            echo -e "  ${BLUE}ℹ${NC} ~/bin already in PATH (${profile})"
            return 0
        fi
    fi
    return 1
}

if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    echo -e "${BLUE}Updating shell PATH...${NC}"

    # Try common shell profiles
    added=false
    for profile in "${HOME}/.zshrc" "${HOME}/.bashrc" "${HOME}/.bash_profile" "${HOME}/.profile"; do
        if add_path_to_profile "${profile}"; then
            added=true
            break
        fi
    done

    if [[ "${added}" = false ]]; then
        echo -e "  ${YELLOW}⚠${NC} Could not find a shell profile to update."
        echo "  Add this line manually to your shell profile:"
        # shellcheck disable=SC2016  # intentional: show literal ${HOME} to user
        echo '    export PATH="${HOME}/bin:${PATH}"'
    fi
else
    echo -e "  ${BLUE}ℹ${NC} ~/bin is already in your PATH"
fi

# ── Check dependencies ────────────────────────────────────────────────────────

echo ""
echo -e "${BLUE}Checking dependencies...${NC}"

if ! command -v jq &> /dev/null; then
    echo -e "  ${YELLOW}⚠${NC}  jq is not installed (required)"
    echo "     Install with: brew install jq"
else
    echo -e "  ${GREEN}✓${NC} jq is installed"
fi

if command -v claude &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} claude is installed"
elif command -v claude-code &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} claude-code is installed"
else
    echo -e "  ${YELLOW}⚠${NC}  Claude Code CLI is not installed"
    echo "     See: https://claude.ai/code"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✓ Installation complete!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Quick start:"
echo ""
echo "  # Reload your shell first (or open a new terminal)"
echo '  source ~/.zshrc'
echo ""
echo "  # Auto-detect from git branch"
echo "  ccp --auto-title"
echo ""
echo "  # Manual title"
echo '  ccp "PR #89 - Fix bug"'
echo ""
echo "  # Quick formats"
echo '  ccp --pr 89 "Fix bug"'
echo '  ccp --feature "New feature"'
echo ""
echo "  # List sessions"
echo "  ccp --list"
echo ""
echo "For help: ccp --help"
echo "Docs: https://github.com/brianruggieri/claude-pane-pulse"
echo ""
