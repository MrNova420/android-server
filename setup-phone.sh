#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# PHONE SERVER - Production Bootstrap
# Run this ON YOUR PHONE in Termux
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
fail() { echo -e "${RED}[x]${NC} $1"; }

echo -e "${PURPLE}"
echo "╔══════════════════════════════════════════════════╗"
echo "║         PHONE SERVER - SETUP                    ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

PHONESRV="$HOME/.phonesrv"
SSH_PORT=8022
API_PORT=5000
API_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)

# ============================================================
# 1. PACKAGES
# ============================================================
echo -e "${BLUE}═══ Installing packages ═══${NC}"

pkg update -y 2>/dev/null
pkg upgrade -y 2>/dev/null

# Core packages - one at a time for reliability
for pkg in openssh python curl wget git jq htop tmux termux-services termux-api; do
    pkg install -y "$pkg" 2>/dev/null || warn "Failed: $pkg"
done

# Python packages - Termux compatible method
echo "[*] Installing Python packages..."
# Try pip directly first (works on most Termux versions)
python -m pip install --upgrade pip 2>/dev/null || true
python -m pip install fastapi uvicorn psutil requests 2>/dev/null && {
    log "Python packages installed via pip"
} || {
    # Fallback: try pip3
    python3 -m pip install --upgrade pip 2>/dev/null || true
    python3 -m pip install fastapi uvicorn psutil requests 2>/dev/null && {
        log "Python packages installed via pip3"
    } || {
        # Fallback: install via pkg
        warn "pip failed, using pkg fallback"
        for py in python-fastapi python-uvicorn python-psutil python-requests; do
            pkg install -y "$py" 2>/dev/null || true
        done
    }
}

# Verify Python packages
python -c "import fastapi; import uvicorn; import psutil; import requests" 2>/dev/null && {
    log "Python packages verified"
} || {
    warn "Some Python packages missing - server may not start"
}

# ============================================================
# 2. DIRECTORIES
# ============================================================
echo -e "\n${BLUE}═══ Creating directories ═══${NC}"

mkdir -p "$PHONESRV"/{bin,config,logs,projects}
mkdir -p "$HOME/.termux/boot"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
log "Directories created"

# ============================================================
# 3. SSH (rock-solid)
# ============================================================
echo -e "\n${BLUE}═══ Setting up SSH ═══${NC}"

# Kill any existing sshd
pkill sshd 2>/dev/null; sleep 1

# Ensure openssh is installed
pkg install -y openssh 2>/dev/null

# Generate host keys if missing
ssh-keygen -A 2>/dev/null

# Find sshd_config
SSHD_CONFIG="$PREFIX/etc/ssh/sshd_config"
if [ ! -f "$SSHD_CONFIG" ]; then
    mkdir -p "$(dirname "$SSHD_CONFIG")"
    # Create minimal config
    cat > "$SSHD_CONFIG" << 'EOF'
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
    log "Created sshd_config"
else
    # Patch existing config for our settings
    sed -i 's/^#\?Port .*/Port 8022/' "$SSHD_CONFIG"
    sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' "$SSHD_CONFIG"
    sed -i 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
    log "Patched existing sshd_config"
fi

# Set password
echo "Setting password to 'phone' (change with: passwd)"
echo "phone:phone" | chpasswd 2>/dev/null || echo "phone" | passwd --stdin "$(whoami)" 2>/dev/null || {
    # Manual password set
    echo "Set password manually: passwd"
}

# Start sshd
sshd 2>/dev/null
sleep 1

# Verify sshd is running
if pgrep sshd > /dev/null 2>&1; then
    log "sshd running on port $SSH_PORT"
else
    warn "sshd failed to start with config, trying without..."
    sshd -D &
    sleep 1
    if pgrep sshd > /dev/null 2>&1; then
        log "sshd started (fallback mode)"
    else
        fail "CRITICAL: sshd failed. Try: sshd -d (debug mode)"
    fi
fi

# ============================================================
# 4. API TOKEN (save for client)
# ============================================================
echo -e "\n${BLUE}═══ Generating API token ═══${NC}"

mkdir -p "$PHONESRV/config"
cat > "$PHONESRV/config/token" << EOF
$API_TOKEN
EOF
chmod 600 "$PHONESRV/config/token"
log "API token saved"

# ============================================================
# 5. SERVER
# ============================================================
echo -e "\n${BLUE}═══ Installing server ═══${NC}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Copy server files
if [ -d "$SCRIPT_DIR/server" ]; then
    cp "$SCRIPT_DIR/server/server.py" "$PHONESRV/"
    cp "$SCRIPT_DIR/server/requirements.txt" "$PHONESRV/" 2>/dev/null || true
    log "Server files copied"
else
    fail "server/ directory not found. Run from project root."
fi

# Create run script
cat > "$PHONESRV/run-server.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd "$HOME/.phonesrv"
exec python server.py 2>&1 | tee -a logs/server.log
EOF
chmod +x "$PHONESRV/run-server.sh"

# ============================================================
# 6. BOOT SCRIPT
# ============================================================
echo -e "\n${BLUE}═══ Setting up boot persistence ═══${NC}"

cat > "$HOME/.termux/boot/start-server.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

# Keep CPU alive
termux-wake-lock

# Wait for network
sleep 15

# Source environment
. $PREFIX/etc/profile 2>/dev/null

# Start sshd if not running
if ! pgrep sshd > /dev/null 2>&1; then
    sshd
fi

# Start phoned server
cd $HOME/.phonesrv
if [ -f server.py ]; then
    nohup python server.py >> logs/server.log 2>&1 &
fi

# Start runit services (if configured)
if command -v runsvdir > /dev/null 2>&1; then
    exec runsvdir -P $PREFIX/var/service &
fi
EOF
chmod +x "$HOME/.termux/boot/start-server.sh"
log "Boot script installed"

# ============================================================
# 7. HELPER SCRIPTS
# ============================================================
echo -e "\n${BLUE}═══ Installing helper scripts ═══${NC}"

cat > "$PHONESRV/bin/sysinfo" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "═══════════════════════════════════"
echo "  PHONE SERVER STATUS"
echo "═══════════════════════════════════"
echo ""
echo "Device:    $(getprop ro.product.model 2>/dev/null || echo unknown)"
echo "Uptime:    $(uptime -p 2>/dev/null || uptime)"
echo ""
echo "CPU:       $(top -bn1 | head -3 | tail -1)"
echo ""
free -h 2>/dev/null || cat /proc/meminfo | head -3
echo ""
df -h /data 2>/dev/null || df -h ~
echo ""
echo "Battery:   $(termux-battery-status 2>/dev/null | jq -c '{pct:.percentage, status:.status}' 2>/dev/null || echo N/A)"
echo ""
echo "Network:   $(ip addr show wlan0 2>/dev/null | grep 'inet ' || echo 'No WiFi')"
echo ""
echo "SSH:       $(pgrep sshd > /dev/null && echo 'running' || echo 'STOPPED')"
echo "phoned:    $(pgrep -f 'server.py' > /dev/null && echo 'running' || echo 'STOPPED')"
echo ""
echo "═══════════════════════════════════"
EOF
chmod +x "$PHONESRV/bin/sysinfo"

cat > "$PHONESRV/bin/start-sshd" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
pkill sshd 2>/dev/null; sleep 1
sshd 2>/dev/null
pgrep sshd > /dev/null 2>&1 && echo "[+] sshd started on port 8022" || echo "[!] sshd failed"
EOF
chmod +x "$PHONESRV/bin/start-sshd"

cat > "$PHONESRV/bin/start-phoned" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
pkill -f 'server.py' 2>/dev/null; sleep 1
cd $HOME/.phonesrv
nohup python server.py >> logs/server.log 2>&1 &
sleep 2
pgrep -f 'server.py' > /dev/null 2>&1 && echo "[+] phoned started on port 5000" || echo "[!] phoned failed"
EOF
chmod +x "$PHONESRV/bin/start-phoned"

cat > "$PHONESRV/bin/restart-all" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "[*] Restarting..."
pkill sshd 2>/dev/null; sleep 1; sshd 2>/dev/null && echo "[+] sshd" || echo "[!] sshd"
pkill -f 'server.py' 2>/dev/null; sleep 1
cd $HOME/.phonesrv && nohup python server.py >> logs/server.log 2>&1 &
sleep 2 && pgrep -f 'server.py' > /dev/null 2>&1 && echo "[+] phoned" || echo "[!] phoned"
EOF
chmod +x "$PHONESRV/bin/restart-all"

# Add to PATH
echo 'export PATH="$HOME/.phonesrv/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/.phonesrv/bin:$PATH"
log "Helper scripts installed"

# ============================================================
# 8. START EVERYTHING
# ============================================================
echo -e "\n${BLUE}═══ Starting services ═══${NC}"

# Ensure sshd is running
pgrep sshd > /dev/null 2>&1 || sshd 2>/dev/null

# Start phoned
cd "$PHONESRV"
nohup python server.py >> logs/server.log 2>&1 &
sleep 2

if pgrep -f "server.py" > /dev/null 2>&1; then
    log "phoned server running on port $API_PORT"
else
    warn "phoned server failed to start - check: cat ~/.phonesrv/logs/server.log"
fi

# ============================================================
# DONE
# ============================================================
IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
USER=$(whoami)

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗"
echo -e "║           SETUP COMPLETE                         ║"
echo -e "╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  SSH User:     ${GREEN}$USER${NC}"
echo -e "  SSH Password: ${GREEN}phone${NC}  ${YELLOW}(change with: passwd)${NC}"
echo -e "  SSH Port:     ${GREEN}$SSH_PORT${NC}"
echo -e "  Local IP:     ${GREEN}${IP:-unknown}${NC}"
echo -e "  API Token:    ${GREEN}$API_TOKEN${NC}"
echo ""
echo -e "  ${YELLOW}From laptop:${NC}"
echo -e "  ${GREEN}ssh -p $SSH_PORT $USER@${IP:-<phone-ip>}${NC}"
echo ""
echo -e "  ${YELLOW}Commands:${NC}"
echo "  sysinfo        - System status"
echo "  start-sshd     - Restart SSH"
echo "  start-phoned   - Restart server"
echo "  restart-all    - Restart everything"
echo ""
