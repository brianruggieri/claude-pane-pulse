#!/usr/bin/env bash
# install.sh - Claude Code Pulse installer
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
echo -e "${GREEN}Claude Code Pulse${NC} - Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Validate source directory ─────────────────────────────────────────────────

if [[ ! -f "${SCRIPT_DIR}/bin/ccp" ]]; then
    echo -e "${RED}✗ Error:${NC} bin/ccp not found. Run from the claude-code-pulse project root." >&2
    exit 1
fi

if [[ ! -d "${SCRIPT_DIR}/lib" ]]; then
    echo -e "${RED}✗ Error:${NC} lib/ directory not found. Run from the claude-code-pulse project root." >&2
    exit 1
fi

# ── Install files ─────────────────────────────────────────────────────────────

echo -e "${BLUE}Installing files...${NC}"

# Create install directory structure
mkdir -p "${INSTALL_DIR}/bin"
mkdir -p "${INSTALL_DIR}/lib"

# Copy files
cp "${SCRIPT_DIR}/bin/ccp" "${INSTALL_DIR}/bin/ccp"
cp "${SCRIPT_DIR}/bin/ccp-watch" "${INSTALL_DIR}/bin/ccp-watch"
cp "${SCRIPT_DIR}"/lib/*.sh "${INSTALL_DIR}/lib/"
chmod +x "${INSTALL_DIR}/bin/ccp"
chmod +x "${INSTALL_DIR}/bin/ccp-watch"
chmod +x "${INSTALL_DIR}/lib/hook_runner.sh"

echo -e "  ${GREEN}✓${NC} Installed to ${INSTALL_DIR}"

# ── Create ~/bin symlink ──────────────────────────────────────────────────────

mkdir -p "${BIN_DIR}"

if [[ -L "${BIN_DIR}/ccp" ]]; then
    rm "${BIN_DIR}/ccp"
fi
if [[ -L "${BIN_DIR}/ccp-watch" ]]; then
    rm "${BIN_DIR}/ccp-watch"
fi

ln -s "${INSTALL_DIR}/bin/ccp" "${BIN_DIR}/ccp"
ln -s "${INSTALL_DIR}/bin/ccp-watch" "${BIN_DIR}/ccp-watch"
echo -e "  ${GREEN}✓${NC} Symlinks created: ${BIN_DIR}/ccp, ${BIN_DIR}/ccp-watch"

# ── PATH reminder ─────────────────────────────────────────────────────────────

if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    echo -e "${YELLOW}  ⚠  ~/bin is not in your PATH.${NC}"
    echo "     Add this line to your shell profile (~/.zshrc, ~/.bashrc, etc.):"
    echo ""
    # shellcheck disable=SC2016  # intentional: show literal ${HOME} to user
    echo '       export PATH="${HOME}/bin:${PATH}"'
    echo ""
    echo "     Then open a new terminal (or source the file you edited)."
else
    echo -e "  ${BLUE}ℹ${NC}  ~/bin is already in your PATH"
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
echo "Docs: https://github.com/brianruggieri/claude-code-pulse"
echo ""
