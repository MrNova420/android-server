#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# Full Setup Script - Runs Everything
# Run this ON YOUR PHONE in Termux
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

BANNER="""
${PURPLE}╔══════════════════════════════════════════════════╗
║       PHONE SERVER - COMPLETE SETUP              ║
╚══════════════════════════════════════════════════╝${NC}
"""

echo -e "$BANNER"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ─── Step 1: Core setup ───
echo -e "${BLUE}[1/5] Core Setup${NC}"
bash "$PROJECT_DIR/setup-phone.sh"

# ─── Step 2: SSH Keys ───
echo ""
echo -e "${BLUE}[2/5] SSH Key Info${NC}"
echo -e "${YELLOW}On your LAPTOP, run:${NC}"
echo "  bash $(pwd)/scripts/setup-ssh-keys.sh"
echo ""

# ─── Step 3: Tor ───
echo -e "${BLUE}[3/5] Tor Setup${NC}"
read -p "Install Tor for anonymity? (y/N): " INSTALL_TOR
if [[ "$INSTALL_TOR" =~ ^[Yy]$ ]]; then
    bash "$SCRIPT_DIR/setup-tor.sh"
else
    echo "[*] Skipping Tor"
fi

# ─── Step 4: Cloudflare Tunnel ───
echo ""
echo -e "${BLUE}[4/5] Cloudflare Tunnel${NC}"
read -p "Setup Cloudflare tunnel for remote access? (y/N): " INSTALL_TUNNEL
if [[ "$INSTALL_TUNNEL" =~ ^[Yy]$ ]]; then
    bash "$SCRIPT_DIR/setup-tunnel.sh"
else
    echo "[*] Skipping tunnel"
fi

# ─── Step 5: Dashboard ───
echo ""
echo -e "${BLUE}[5/5] Dashboard${NC}"
DASHBOARD_DIR="$HOME/.phonesrv/dashboard"
mkdir -p "$DASHBOARD_DIR"
cp "$PROJECT_DIR/dashboard/index.html" "$DASHBOARD_DIR/"
echo "[+] Dashboard copied to $DASHBOARD_DIR"

# ─── Done ───
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗"
echo -e "║           FULL SETUP COMPLETE!                   ║"
echo -e "╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Quick Start:${NC}"
echo "  1. Set password:     ${GREEN}passwd${NC}"
echo "  2. Get username:     ${GREEN}whoami${NC}"
echo "  3. Get IP:           ${GREEN}ip addr show wlan0${NC}"
echo "  4. Start phoned:     ${GREEN}sv up phoned${NC}"
echo "  5. Check status:     ${GREEN}sysinfo${NC}"
echo ""
echo -e "${YELLOW}From your laptop:${NC}"
echo "  ${GREEN}ssh -p 8022 <user>@<ip>${NC}"
echo ""
echo -e "${YELLOW}Commands:${NC}"
echo "  sysinfo         - System status"
echo "  anon on/off     - Anonymous mode"
echo "  anon rotate     - Rotate Tor IP"
echo "  tunnel start    - Start Cloudflare tunnel"
echo "  deploy <name>   - Deploy a project"
echo "  restart-all     - Restart all services"
echo ""
