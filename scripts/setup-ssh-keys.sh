#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# SSH Key Setup Script
# Run this ON YOUR LAPTOP
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}═══ SSH Key Setup for Phone Server ═══${NC}"
echo ""

KEY_PATH="$HOME/.ssh/phone_key"
KEY_PUB="$KEY_PATH.pub"

# Generate key if it doesn't exist
if [ ! -f "$KEY_PATH" ]; then
    echo -e "${YELLOW}[*] Generating SSH key pair...${NC}"
    ssh-keygen -t ed25519 -C "phone-server" -f "$KEY_PATH" -N ""
    echo -e "${GREEN}[+] Key generated: $KEY_PATH${NC}"
else
    echo -e "${GREEN}[+] Key already exists: $KEY_PATH${NC}"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "  PUBLIC KEY (copy this to your phone):"
echo "═══════════════════════════════════════════════════"
echo ""
cat "$KEY_PUB"
echo ""
echo "═══════════════════════════════════════════════════"
echo ""
echo -e "${YELLOW}On your phone, run:${NC}"
echo ""
echo "  mkdir -p ~/.ssh && chmod 700 ~/.ssh"
echo "  echo '$(cat "$KEY_PUB")' >> ~/.ssh/authorized_keys"
echo "  chmod 600 ~/.ssh/authorized_keys"
echo ""
echo -e "${YELLOW}Or use ssh-copy-id (if phone is on LAN):${NC}"
echo ""
echo "  ssh-copy-id -p 8022 -i $KEY_PUB $USER@<phone-ip>"
echo ""
echo -e "${YELLOW}Then add to ~/.ssh/config:${NC}"
echo ""
echo "  Host phone"
echo "      HostName <phone-ip>"
echo "      Port 8022"
echo "      User $(whoami)"
echo "      IdentityFile $KEY_PATH"
echo ""
echo -e "${GREEN}[+] Test with: ssh -p 8022 -i $KEY_PATH $USER@<phone-ip>${NC}"
echo ""
