#!/usr/bin/env bash
# uninstall.sh - Claude Code Pulse uninstaller

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="${HOME}/.local/share/ccp"
BIN_LINK="${HOME}/bin/ccp"
BIN_WATCH_LINK="${HOME}/bin/ccp-watch"
CONFIG_DIR="${HOME}/.config/claude-code-pulse"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${RED}Claude Code Pulse${NC} - Uninstaller"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "This will remove:"
echo "  • ${BIN_LINK} (symlink)"
echo "  • ${BIN_WATCH_LINK} (symlink)"
echo "  • ${INSTALL_DIR} (program files)"
echo ""
echo -n "Continue? [y/N] "
read -r confirm

if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""

# Remove symlink
if [[ -L "${BIN_LINK}" ]]; then
    rm "${BIN_LINK}"
    echo -e "  ${GREEN}✓${NC} Removed ${BIN_LINK}"
elif [[ -f "${BIN_LINK}" ]]; then
    rm "${BIN_LINK}"
    echo -e "  ${GREEN}✓${NC} Removed ${BIN_LINK}"
else
    echo -e "  ${BLUE}ℹ${NC} ${BIN_LINK} not found (already removed?)"
fi

# Remove ccp-watch symlink
if [[ -L "${BIN_WATCH_LINK}" || -f "${BIN_WATCH_LINK}" ]]; then
    rm "${BIN_WATCH_LINK}"
    echo -e "  ${GREEN}✓${NC} Removed ${BIN_WATCH_LINK}"
fi

# Remove install directory
if [[ -d "${INSTALL_DIR}" ]]; then
    rm -rf "${INSTALL_DIR}"
    echo -e "  ${GREEN}✓${NC} Removed ${INSTALL_DIR}"
else
    echo -e "  ${BLUE}ℹ${NC} ${INSTALL_DIR} not found"
fi

# Offer to remove config/session data
if [[ -d "${CONFIG_DIR}" ]]; then
    echo ""
    echo -e "${YELLOW}Session data found:${NC} ${CONFIG_DIR}"
    echo -n "Remove session data too? [y/N] "
    read -r remove_config

    if [[ "${remove_config}" = "y" || "${remove_config}" = "Y" ]]; then
        rm -rf "${CONFIG_DIR}"
        echo -e "  ${GREEN}✓${NC} Removed ${CONFIG_DIR}"
    else
        echo -e "  ${BLUE}ℹ${NC} Session data kept at ${CONFIG_DIR}"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✓ Uninstall complete${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Note: PATH entries added to your shell profile were not removed."
echo "You can safely leave them — they won't cause any issues."
echo ""
