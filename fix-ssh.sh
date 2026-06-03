#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# FIX SSH - Run this if SSH is broken
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"

echo ""
echo "═══════════════════════════════════════"
echo "  SSH FIX"
echo "═══════════════════════════════════════"
echo ""

# Step 1: Kill existing
echo -e "${YELLOW}[1] Killing existing sshd...${NC}"
pkill sshd 2>/dev/null
sleep 1
rm -f /tmp/sshd.pid 2>/dev/null || true
echo -e "  ${GREEN}Done${NC}"

# Step 2: Check openssh
echo ""
echo -e "${YELLOW}[2] Checking openssh...${NC}"
if ! command -v sshd > /dev/null 2>&1; then
    echo -e "  ${RED}sshd not found - installing...${NC}"
    pkg install -y openssh 2>/dev/null
fi

if command -v sshd > /dev/null 2>&1; then
    echo -e "  ${GREEN}sshd found: $(which sshd)${NC}"
else
    echo -e "  ${RED}FAILED to install openssh${NC}"
    exit 1
fi

# Step 3: Generate host keys
echo ""
echo -e "${YELLOW}[3] Generating host keys...${NC}"
mkdir -p "$PREFIX/etc/ssh"
ssh-keygen -A 2>&1 | head -5
echo -e "  ${GREEN}Done${NC}"

# Step 4: Write config
echo ""
echo -e "${YELLOW}[4] Writing sshd_config...${NC}"
cat > "$PREFIX/etc/ssh/sshd_config" << 'EOF'
Port 8022
AddressFamily any
ListenAddress 0.0.0.0
PubkeyAuthentication yes
PasswordAuthentication yes
PermitRootLogin no
X11Forwarding no
AllowTcpForwarding yes
MaxAuthTries 3
MaxSessions 5
ClientAliveInterval 60
ClientAliveCountMax 3
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
EOF
echo -e "  ${GREEN}Done${NC}"

# Step 5: Start sshd
echo ""
echo -e "${YELLOW}[5] Starting sshd...${NC}"
sshd 2>/dev/null
sleep 2

if pgrep sshd > /dev/null 2>&1; then
    echo -e "  ${GREEN}SSH IS RUNNING on port 8022${NC}"
else
    echo -e "  ${RED}SSH FAILED to start${NC}"
    echo ""
    echo "  Trying debug mode (will show error)..."
    echo "  ───────────────────────────────────"
    timeout 5 sshd -d 2>&1 || true
    echo "  ───────────────────────────────────"
fi

# Step 6: Verify
echo ""
echo -e "${YELLOW}[6] Verifying...${NC}"
if pgrep sshd > /dev/null 2>&1; then
    echo -e "  ${GREEN}SSH is running!${NC}"
else
    echo -e "  ${RED}SSH is NOT running${NC}"
fi

# Summary
echo ""
echo "═══════════════════════════════════════"
IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
echo -e "  User:     $(whoami)"
echo -e "  Port:     8022"
echo -e "  IP:       ${IP:-unknown}"
echo -e "  Password: (run 'passwd' to set)"
echo "═══════════════════════════════════════"
echo ""
echo "  From laptop: ssh -p 8022 $(whoami)@${IP:-<ip>}"
echo ""
