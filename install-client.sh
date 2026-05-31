#!/bin/bash
# ============================================================
# Install phoned CLI on your LAPTOP
# ============================================================
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.phoned"

echo "[*] Installing phoned CLI..."

# Create install directory
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"

# Copy CLI
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/client/phoned" "$INSTALL_DIR/phoned"
chmod +x "$INSTALL_DIR/phoned"

# Create symlink for easy access
if [ ! -f "/usr/local/bin/phoned" ] 2>/dev/null; then
    sudo ln -sf "$INSTALL_DIR/phoned" /usr/local/bin/phoned 2>/dev/null || {
        echo "[*] Add to PATH manually: export PATH=\"$HOME/.local/bin:\$PATH\""
    }
fi

# Install Python dependencies
pip install requests 2>/dev/null || pip3 install requests 2>/dev/null || {
    echo "[!] Install requests manually: pip install requests"
}

echo ""
echo "[+] phoned CLI installed!"
echo ""
echo "Setup:"
echo "  phoned init         # Configure connection"
echo "  phoned status       # Test connection"
echo "  phoned ssh          # Open SSH session"
echo ""
echo "Commands:"
echo "  phoned status       - Phone status"
echo "  phoned ssh          - SSH session"
echo "  phoned run <cmd>    - Execute command"
echo "  phoned deploy <dir> - Deploy project"
echo "  phoned services     - List services"
echo "  phoned projects     - List projects"
echo "  phoned logs <svc>   - View logs"
echo "  phoned anon on      - Enable Tor"
echo "  phoned anon rotate  - Rotate IP"
echo "  phoned tunnel start - Start tunnel"
echo "  phoned health       - Health check"
echo ""
