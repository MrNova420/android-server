#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# Cloudflare Tunnel Setup Script
# Run this ON YOUR PHONE in Termux
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}═══ Cloudflare Tunnel Setup ═══${NC}"
echo ""
echo "This sets up a permanent tunnel so you can access"
echo "your phone from anywhere in the world."
echo ""

# Check for cloudflared
if ! command -v cloudflared &>/dev/null; then
    echo -e "${YELLOW}[*] Installing cloudflared...${NC}"
    pkg install -y cloudflared 2>/dev/null || {
        echo -e "${YELLOW}[*] Building cloudflared from source...${NC}"
        pkg install -y golang
        mkdir -p ~/tmp && cd ~/tmp
        git clone https://github.com/cloudflare/cloudflared.git
        cd cloudflared
        make cloudflared
        cp cloudflared "$PREFIX/bin/"
        cd ~
        rm -rf ~/tmp/cloudflared
    }
fi

echo -e "${GREEN}[+] cloudflared installed${NC}"
echo ""

# Login
echo -e "${YELLOW}[!] First, login to Cloudflare:${NC}"
echo "  A browser window will open (or copy the URL to your laptop)"
echo ""
cloudflared tunnel login

# Create tunnel
echo ""
echo -e "${YELLOW}[!] Enter a name for your tunnel:${NC}"
read -r TUNNEL_NAME
TUNNEL_NAME="${TUNNEL_NAME:-phone-server}"

echo -e "${YELLOW}[*] Creating tunnel: $TUNNEL_NAME${NC}"
cloudflared tunnel create "$TUNNEL_NAME"
TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')

echo ""
echo -e "${YELLOW}[!] Enter your domain (e.g., example.com):${NC}"
read -r DOMAIN

echo -e "${YELLOW}[*] Routing DNS...${NC}"
cloudflared tunnel route dns "$TUNNEL_ID" "ssh.$DOMAIN"
cloudflared tunnel route dns "$TUNNEL_ID" "api.$DOMAIN"
cloudflared tunnel route dns "$TUNNEL_ID" "web.$DOMAIN"

# Create config
CONFIG_DIR="$HOME/.cloudflared"
mkdir -p "$CONFIG_DIR"

CRED_FILE="$CONFIG_DIR/$TUNNEL_ID.json"

cat > "$CONFIG_DIR/config.yml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE

ingress:
  - hostname: ssh.$DOMAIN
    service: ssh://localhost:8022
  - hostname: api.$DOMAIN
    service: http://localhost:5000
  - hostname: web.$DOMAIN
    service: http://localhost:8080
  - service: http_status:404
EOF

echo -e "${GREEN}[+] Config created at $CONFIG_DIR/config.yml${NC}"

# Create runit service
SERVICE_DIR="$PREFIX/var/service/cloudflared"
mkdir -p "$SERVICE_DIR/log"
ln -sf "$PREFIX/share/termux-services/svlogger" "$SERVICE_DIR/log/run" 2>/dev/null || true

cat > "$SERVICE_DIR/run" << 'EOF'
#!/bin/bash
exec cloudflared tunnel --config /data/data/com.termux/files/home/.cloudflared/config.yml run
EOF
chmod +x "$SERVICE_DIR/run"

sv-enable cloudflared
sv up cloudflared

echo -e "${GREEN}[+] Cloudflare tunnel started!${NC}"
echo ""
echo "═══════════════════════════════════════════════"
echo -e "  SSH:       ssh $USER@ssh.$DOMAIN"
echo -e "  API:       https://api.$DOMAIN"
echo -e "  Web:       https://web.$DOMAIN"
echo "═══════════════════════════════════════════════"
echo ""
echo "Add this to your laptop's ~/.ssh/config:"
echo ""
echo "  Host phone-cloud"
echo "      HostName ssh.$DOMAIN"
echo "      User $USER"
echo "      ProxyCommand cloudflared access ssh --hostname ssh.$DOMAIN"
echo "      IdentityFile ~/.ssh/phone_key"
echo ""
