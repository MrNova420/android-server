#!/bin/bash
# ============================================================
# Install phoned CLI on your LAPTOP
# ============================================================
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.phoned"

echo "[*] Installing phoned CLI..."

mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Install CLI
cp "$SCRIPT_DIR/client/phoned" "$INSTALL_DIR/phoned"
chmod +x "$INSTALL_DIR/phoned"

# Symlink to /usr/local/bin if possible
if [ ! -f "/usr/local/bin/phoned" ] 2>/dev/null; then
    sudo ln -sf "$INSTALL_DIR/phoned" /usr/local/bin/phoned 2>/dev/null || {
        echo "[*] Add to PATH: export PATH=\"$HOME/.local/bin:\$PATH\""
    }
fi

# Install requests if missing
python3 -c "import requests" 2>/dev/null || {
    echo "[*] Installing requests..."
    pip3 install requests 2>/dev/null || pip install requests 2>/dev/null || {
        echo "[!] Install manually: pip3 install requests"
    }
}

echo ""
echo "[+] phoned CLI installed!"
echo ""
echo "Setup:"
echo "  phoned init"
echo ""
echo "Commands:"
echo "  phoned status       - Phone status"
echo "  phoned ssh          - SSH session"
echo "  phoned deploy <dir> - Deploy project"
echo "  phoned services     - List services"
echo "  phoned projects     - List projects"
echo "  phoned ports 8080   - Port forward"
echo "  phoned anon on      - Enable Tor"
echo "  phoned health       - Health check"
echo ""
