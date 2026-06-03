#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# ONE-COMMAND INSTALLER
# Run this ON YOUR PHONE in Termux:
#
#   pkg install git && git clone https://github.com/MrNova420/android-server && cd android-server && bash install.sh
#
# Or if git isn't available:
#   pkg install curl && curl -fsSL https://raw.githubusercontent.com/MrNova420/android-server/main/install.sh | bash
#
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
fail() { echo -e "${RED}[x]${NC} $1"; }

echo -e "${PURPLE}"
echo "╔══════════════════════════════════════════════════╗"
echo "║       PHONE SERVER - AUTO INSTALLER             ║"
echo "║   One command. Zero config. Production ready.   ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

PHONESRV="$HOME/.phonesrv"
SSH_PORT=8022
API_PORT=5000
API_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)
USER=$(whoami)
IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)

# ============================================================
# PHASE 1: PACKAGES
# ============================================================
echo -e "${BLUE}═══ Phase 1: Installing packages ═══${NC}"

pkg update -y 2>/dev/null || true
pkg upgrade -y 2>/dev/null || true

# Core packages
for pkg in openssh python curl git jq htop tmux termux-services termux-api; do
    if command -v "$pkg" > /dev/null 2>&1 || [ -f "$PREFIX/bin/$pkg" ]; then
        echo "  $pkg: already installed"
    else
        pkg install -y "$pkg" 2>/dev/null && log "$pkg installed" || warn "$pkg failed"
    fi
done

# Python packages
log "Installing Python packages..."
python -m pip install fastapi uvicorn psutil requests 2>/dev/null && {
    log "Python packages OK"
} || python3 -m pip install fastapi uvicorn psutil requests 2>/dev/null && {
    log "Python packages OK (pip3)"
} || {
    warn "pip failed - using pkg fallback"
    for py in python-fastapi python-uvicorn python-psutil python-requests; do
        pkg install -y "$py" 2>/dev/null || true
    done
}

# ============================================================
# PHASE 2: SSH (bulletproof)
# ============================================================
echo -e "\n${BLUE}═══ Phase 2: Setting up SSH ═══${NC}"

# Kill any existing sshd
pkill sshd 2>/dev/null; sleep 1

# Ensure host keys exist
ssh-keygen -A 2>/dev/null || true

# Write sshd_config
SSHD_CONFIG="$PREFIX/etc/ssh/sshd_config"
mkdir -p "$(dirname "$SSHD_CONFIG")" 2>/dev/null || true

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

# Set default password
echo "phone:phone" | chpasswd 2>/dev/null || echo "Set password with: passwd"

# Start sshd
sshd 2>/dev/null
sleep 2

if pgrep sshd > /dev/null 2>&1; then
    log "SSH running on port $SSH_PORT"
else
    warn "SSH failed to start with config, trying fallback..."
    sshd -D &
    sleep 2
    pgrep sshd > /dev/null 2>&1 && log "SSH running (fallback)" || fail "SSH FAILED"
fi

# ============================================================
# PHASE 3: DIRECTORIES + FILES
# ============================================================
echo -e "\n${BLUE}═══ Phase 3: Setting up files ═══${NC}"

mkdir -p "$PHONESRV"/{bin,config,logs,projects}
mkdir -p "$HOME/.termux/boot"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Save API token
echo "$API_TOKEN" > "$PHONESRV/config/token"
chmod 600 "$PHONESRV/config/token"

# Copy server files from git clone
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/server/server.py" ]; then
    cp "$SCRIPT_DIR/server/server.py" "$PHONESRV/"
    log "Server files installed"
elif [ -f "$SCRIPT_DIR/server.py" ]; then
    cp "$SCRIPT_DIR/server.py" "$PHONESRV/"
    log "Server files installed"
else
    warn "server.py not found - run from git clone directory"
fi

# Copy scripts
if [ -d "$SCRIPT_DIR/scripts" ]; then
    mkdir -p "$PHONESRV/scripts"
    cp "$SCRIPT_DIR/scripts/"*.sh "$PHONESRV/scripts/" 2>/dev/null || true
    chmod +x "$PHONESRV/scripts/"*.sh 2>/dev/null || true
fi

# ============================================================
# PHASE 4: BOOT PERSISTENCE
# ============================================================
echo -e "\n${BLUE}═══ Phase 4: Boot persistence ═══${NC}"

# Install boot script
cat > "$HOME/.termux/boot/start-server.sh" << 'BOOTEOF'
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
sleep 20
. $PREFIX/etc/profile 2>/dev/null

LOG="$HOME/.phonesrv/logs/boot.log"
mkdir -p "$HOME/.phonesrv/logs"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] BOOT START" >> "$LOG"

# Start SSH
if ! pgrep sshd > /dev/null 2>&1; then
    ssh-keygen -A 2>/dev/null || true
    rm -f /tmp/sshd.pid 2>/dev/null || true
    sshd 2>/dev/null
    sleep 2
fi

# Start phoned
if ! pgrep -f "server.py" > /dev/null 2>&1; then
    cd "$HOME/.phonesrv" 2>/dev/null
    [ -f server.py ] && nohup python server.py >> logs/server.log 2>&1 &
    sleep 3
fi

# Start watchdog
if ! pgrep -f "watchdog.sh" > /dev/null 2>&1; then
    [ -f "$HOME/.phonesrv/scripts/watchdog.sh" ] && \
        nohup bash "$HOME/.phonesrv/scripts/watchdog.sh" >> "$HOME/.phonesrv/logs/watchdog.log" 2>&1 &
fi

# Start health monitor
if ! pgrep -f "health-monitor.sh" > /dev/null 2>&1; then
    [ -f "$HOME/.phonesrv/scripts/health-monitor.sh" ] && \
        nohup bash "$HOME/.phonesrv/scripts/health-monitor.sh" >> "$HOME/.phonesrv/logs/health.log" 2>&1 &
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] BOOT COMPLETE" >> "$LOG"
BOOTEOF
chmod +x "$HOME/.termux/boot/start-server.sh"
log "Boot script installed"

# ============================================================
# PHASE 5: HELPER SCRIPTS
# ============================================================
echo -e "\n${BLUE}═══ Phase 5: Helper scripts ═══${NC}"

cat > "$PHONESRV/bin/sysinfo" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "═══════════════════════════════════"
echo "  PHONE SERVER STATUS"
echo "═══════════════════════════════════"
echo ""
echo "Device:  $(getprop ro.product.model 2>/dev/null || echo unknown)"
echo "Uptime:  $(uptime -p 2>/dev/null || uptime)"
echo ""
echo "CPU:     $(top -bn1 2>/dev/null | head -3 | tail -1 || echo N/A)"
echo ""
free -h 2>/dev/null || cat /proc/meminfo | head -3
echo ""
df -h /data 2>/dev/null || df -h ~
echo ""
echo "Battery: $(termux-battery-status 2>/dev/null | jq -c '{pct:.percentage, status:.status}' 2>/dev/null || echo N/A)"
echo ""
echo "Network: $(ip addr show wlan0 2>/dev/null | grep 'inet ' || echo 'No WiFi')"
echo ""
echo "SSH:     $(pgrep sshd > /dev/null && echo 'running on 8022' || echo 'STOPPED')"
echo "phoned:  $(pgrep -f 'server.py' > /dev/null && echo 'running on 5000' || echo 'STOPPED')"
echo "watchdog:$(pgrep -f 'watchdog.sh' > /dev/null && echo ' running' || echo ' STOPPED')"
echo ""
echo "═══════════════════════════════════"
EOF
chmod +x "$PHONESRV/bin/sysinfo"

cat > "$PHONESRV/bin/start-sshd" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
pkill sshd 2>/dev/null; sleep 1
rm -f /tmp/sshd.pid 2>/dev/null || true
ssh-keygen -A 2>/dev/null || true
sshd 2>/dev/null
sleep 1
pgrep sshd > /dev/null 2>&1 && echo "[+] sshd running on port 8022" || echo "[!] sshd failed"
EOF
chmod +x "$PHONESRV/bin/start-sshd"

cat > "$PHONESRV/bin/start-phoned" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
pkill -f 'server.py' 2>/dev/null; sleep 1
cd "$HOME/.phonesrv"
[ -f server.py ] && nohup python server.py >> logs/server.log 2>&1 &
sleep 2
pgrep -f 'server.py' > /dev/null 2>&1 && echo "[+] phoned running on port 5000" || echo "[!] phoned failed"
EOF
chmod +x "$PHONESRV/bin/start-phoned"

cat > "$PHONESRV/bin/restart-all" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "[*] Restarting all services..."
pkill sshd 2>/dev/null; sleep 1; sshd 2>/dev/null && echo "[+] sshd" || echo "[!] sshd"
pkill -f 'server.py' 2>/dev/null; sleep 1
cd "$HOME/.phonesrv" && nohup python server.py >> logs/server.log 2>&1 &
sleep 2 && pgrep -f 'server.py' > /dev/null 2>&1 && echo "[+] phoned" || echo "[!] phoned"
echo "[+] Done"
EOF
chmod +x "$PHONESRV/bin/restart-all"

cat > "$PHONESRV/bin/status" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "═══════════════════════════════════"
echo "  SERVICE STATUS"
echo "═══════════════════════════════════"
echo ""
pgrep sshd > /dev/null 2>&1 && echo "  sshd:     ● running" || echo "  sshd:     ○ STOPPED"
pgrep -f 'server.py' > /dev/null 2>&1 && echo "  phoned:   ● running" || echo "  phoned:   ○ STOPPED"
pgrep -f 'watchdog.sh' > /dev/null 2>&1 && echo "  watchdog: ● running" || echo "  watchdog: ○ STOPPED"
pgrep -f 'health-monitor.sh' > /dev/null 2>&1 && echo "  health:   ● running" || echo "  health:   ○ STOPPED"
pgrep tor > /dev/null 2>&1 && echo "  tor:      ● running" || echo "  tor:      ○ stopped"
pgrep nginx > /dev/null 2>&1 && echo "  nginx:    ● running" || echo "  nginx:    ○ stopped"
echo ""
echo "═══════════════════════════════════"
EOF
chmod +x "$PHONESRV/bin/status"

# Add to PATH
echo 'export PATH="$HOME/.phonesrv/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/.phonesrv/bin:$PATH"

log "Helper scripts installed"

# ============================================================
# PHASE 6: START EVERYTHING
# ============================================================
echo -e "\n${BLUE}═══ Phase 6: Starting services ═══${NC}"

# Ensure sshd
pgrep sshd > /dev/null 2>&1 || { sshd 2>/dev/null; sleep 1; }

# Start phoned
cd "$PHONESRV"
nohup python server.py >> logs/server.log 2>&1 &
sleep 3

# Start watchdog
[ -f "$PHONESRV/scripts/watchdog.sh" ] && \
    nohup bash "$PHONESRV/scripts/watchdog.sh" >> logs/watchdog.log 2>&1 &

# Start health monitor
[ -f "$PHONESRV/scripts/health-monitor.sh" ] && \
    nohup bash "$PHONESRV/scripts/health-monitor.sh" >> logs/health.log 2>&1 &

sleep 2

# ============================================================
# PHASE 7: VERIFY
# ============================================================
echo -e "\n${BLUE}═══ Phase 7: Verification ═══${NC}"

SSH_OK=false
PHONED_OK=false
WD_OK=false

pgrep sshd > /dev/null 2>&1 && { log "SSH: OK"; SSH_OK=true; } || fail "SSH: FAILED"
pgrep -f "server.py" > /dev/null 2>&1 && { log "phoned: OK"; PHONED_OK=true; } || warn "phoned: FAILED"
pgrep -f "watchdog.sh" > /dev/null 2>&1 && { log "watchdog: OK"; WD_OK=true; } || warn "watchdog: FAILED"

# ============================================================
# DONE
# ============================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗"
echo -e "║           INSTALLATION COMPLETE                 ║"
echo -e "╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${YELLOW}Phone Server Info:${NC}"
echo -e "  User:       ${GREEN}$USER${NC}"
echo -e "  Password:   ${GREEN}phone${NC} ${YELLOW}(change: passwd)${NC}"
echo -e "  SSH Port:   ${GREEN}$SSH_PORT${NC}"
echo -e "  Local IP:   ${GREEN}${IP:-unknown}${NC}"
echo -e "  API Token:  ${GREEN}$API_TOKEN${NC}"
echo ""
if $SSH_OK && $PHONED_OK; then
    echo -e "  ${GREEN}All systems operational!${NC}"
else
    echo -e "  ${YELLOW}Some services failed to start. Run: status${NC}"
fi
echo ""
echo -e "  ${YELLOW}From your laptop:${NC}"
echo -e "  ${GREEN}ssh -p $SSH_PORT $USER@${IP:-<phone-ip>}${NC}"
echo -e "  ${YELLOW}Password: phone${NC}"
echo ""
echo -e "  ${YELLOW}Commands on phone:${NC}"
echo "  sysinfo        System status"
echo "  status         Service status"
echo "  start-sshd     Restart SSH"
echo "  start-phoned   Restart server"
echo "  restart-all    Restart everything"
echo ""
