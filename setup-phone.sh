#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# PHONE SERVER - Full Bootstrap Script
# Run this ON YOUR PHONE in Termux
# ============================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

BANNER="""
${PURPLE}╔══════════════════════════════════════════════════╗
║         PHONE SERVER - SETUP WIZARD              ║
║     Turn your Android into a private server      ║
╚══════════════════════════════════════════════════╝${NC}
"""

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

echo -e "$BANNER"

# ============================================================
# STEP 1: System Update & Packages
# ============================================================
echo -e "\n${CYAN}═══ STEP 1: Installing Packages ═══${NC}"

log "Updating package repos..."
pkg update -y
pkg upgrade -y || true

log "Installing core packages..."
pkg install -y openssh || true
pkg install -y tmux || true
pkg install -y curl wget git || true
pkg install -y python || true
pkg install -y termux-services || true
pkg install -y termux-api || true
pkg install -y jq htop nano vim rsync socat || true
pkg install -y net-tools zip unzip tree || true

log "Installing optional..."
pkg install -y nodejs npm || true
pkg install -y nginx privoxy tor || true

log "Installing Python packages..."
# Termux handles pip differently - no --break-system-packages needed
pip install --upgrade pip 2>/dev/null || \
pip3 install --upgrade pip 2>/dev/null || true

pip install fastapi uvicorn psutil requests 2>/dev/null || \
pip3 install fastapi uvicorn psutil requests 2>/dev/null || {
    warn "pip failed - installing via pkg instead"
    pkg install -y python-pip || true
    pip install fastapi uvicorn psutil requests || true
}

log "Packages installed"

# ============================================================
# STEP 2: Directories
# ============================================================
echo -e "\n${CYAN}═══ STEP 2: Creating Directory Structure ═══${NC}"

PHONESRV="$HOME/.phonesrv"
mkdir -p "$PHONESRV"/{bin,config,logs,projects,scripts}
mkdir -p "$PHONESRV/config/ssh"
mkdir -p "$HOME/.termux/boot"
mkdir -p "$HOME/.ssh"
mkdir -p "$HOME/bin"
log "Created $PHONESRV"

# ============================================================
# STEP 3: SSH Setup (handle conflicts)
# ============================================================
echo -e "\n${CYAN}═══ STEP 3: Configuring SSH ═══${NC}"

# Kill any existing sshd first
pkill sshd 2>/dev/null || true
sleep 1

# Find or create sshd_config
SSHD_CONFIG="$PREFIX/etc/ssh/sshd_config"
if [ ! -f "$SSHD_CONFIG" ]; then
    mkdir -p "$(dirname "$SSHD_CONFIG")"
    info "Creating $SSHD_CONFIG"
fi

# Backup and write new config
cp "$SSHD_CONFIG" "$SSHD_CONFIG.bak" 2>/dev/null || true

cat > "$SSHD_CONFIG" << 'SSHEOF'
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
SSHEOF

# Set a default password (user should change it)
echo "Setting default password to 'phone' - change it with passwd"
echo "phone:phone" | chpasswd 2>/dev/null || {
    # If chpasswd not available, use termux way
    echo "Set password manually with: passwd"
}

# Generate host keys if missing
ssh-keygen -A 2>/dev/null || true

# Start sshd
log "Starting sshd..."
sshd 2>/dev/null

# Verify
sleep 1
if pgrep sshd > /dev/null 2>&1; then
    log "sshd is running on port 8022"
else
    warn "sshd didn't start, trying alternative..."
    # Try without config
    sshd -D &
    sleep 1
    if pgrep sshd > /dev/null 2>&1; then
        log "sshd started (alternative mode)"
    else
        err "sshd failed to start - try running: sshd -d"
    fi
fi

info "SSH user: $(whoami)"
info "SSH port: 8022"

# ============================================================
# STEP 4: Service Manager
# ============================================================
echo -e "\n${CYAN}═══ STEP 4: Enabling Service Manager ═══${NC}"

sv-enable sshd 2>/dev/null || true
sv up sshd 2>/dev/null || true
log "Service manager configured"

# ============================================================
# STEP 5: Boot Script
# ============================================================
echo -e "\n${CYAN}═══ STEP 5: Configuring Boot Persistence ═══${NC}"

cat > "$HOME/.termux/boot/start-server.sh" << 'BOOTEOF'
#!/data/data/com.termux/files/usr/bin/bash

# Keep CPU alive - critical for always-on
termux-wake-lock

# Wait for WiFi to come up
sleep 15

# Source environment
. $PREFIX/etc/profile

# Start sshd if not running
if ! pgrep sshd > /dev/null 2>&1; then
    sshd
fi

# Start all runit services
exec runsvdir -P $PREFIX/var/service &
BOOTEOF
chmod +x "$HOME/.termux/boot/start-server.sh"
log "Boot script created"

# ============================================================
# STEP 6: phoned Server
# ============================================================
echo -e "\n${CYAN}═══ STEP 6: Installing phoned Server ═══${NC}"

# Copy server files
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$SCRIPT_DIR/server" ]; then
    cp -r "$SCRIPT_DIR/server/"* "$PHONESRV/"
    log "Server files copied"
else
    warn "Server files not found - run from project directory"
fi

# Create phoned service
mkdir -p "$PREFIX/var/service/phoned/log" 2>/dev/null || true
ln -sf "$PREFIX/share/termux-services/svlogger" "$PREFIX/var/service/phoned/log/run" 2>/dev/null || true

cat > "$PREFIX/var/service/phoned/run" << 'SVCEOF'
#!/bin/bash
cd $HOME/.phonesrv
exec python server.py
SVCEOF
chmod +x "$PREFIX/var/service/phoned/run"

sv-enable phoned 2>/dev/null || true
sv up phoned 2>/dev/null || true
log "phoned server installed"

# ============================================================
# STEP 7: Process Manager (pm2)
# ============================================================
echo -e "\n${CYAN}═══ STEP 7: Installing Process Manager ═══${NC}"

npm install -g pm2 2>/dev/null || true
pm2 startup termux 2>/dev/null || true
log "pm2 installed"

# ============================================================
# STEP 8: Shell Setup
# ============================================================
echo -e "\n${CYAN}═══ STEP 8: Setting Up Shell ═══${NC}"

cat >> "$HOME/.bashrc" << 'RCLOG'

# === Phone Server Aliases ===
export PHONESRV="$HOME/.phonesrv"
export PATH="$HOME/.phonesrv/bin:$HOME/bin:$PATH"

alias sysinfo='$HOME/.phonesrv/bin/sysinfo'
alias ps-status='curl -s http://localhost:5000/status | jq'
alias ps-services='curl -s http://localhost:5000/services | jq'
alias ps-projects='ls -la ~/projects/'
alias ps-logs='tail -f $HOME/.phonesrv/logs/*.log'
alias ps-restart='sv restart phoned'
alias ps-sshlog='tail -f $PREFIX/var/log/sv/sshd/current'

deploy() {
  if [ -z "$1" ]; then
    echo "Usage: deploy <local-path>"
    return 1
  fi
  rsync -avzP -e 'ssh -p 8022' "$1" "$(whoami)@localhost:~/projects/"
}

connect() {
  ssh -p 8022 "$(whoami)@localhost"
}
RCLOG

log "Shell aliases added"

# ============================================================
# STEP 9: Firewall (basic)
# ============================================================
echo -e "\n${CYAN}═══ STEP 9: Basic Security ═══${NC}"

cat > "$PHONESRV/bin/firewall.sh" << 'FWEOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "[*] Applying basic firewall rules..."
iptables -A INPUT -i lo -j ACCEPT 2>/dev/null
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
iptables -A INPUT -p tcp --dport 8022 -j ACCEPT 2>/dev/null
iptables -A INPUT -p tcp --dport 5000 -s 127.0.0.1 -j ACCEPT 2>/dev/null
iptables -A INPUT -p tcp --dport 8080 -s 127.0.0.1 -j ACCEPT 2>/dev/null
echo "[+] Firewall rules applied"
FWEOF
chmod +x "$PHONESRV/bin/firewall.sh"
log "Firewall script created"

# ============================================================
# STEP 10: Helper Scripts
# ============================================================
echo -e "\n${CYAN}═══ STEP 10: Creating Helper Scripts ═══${NC}"

cat > "$PHONESRV/bin/sysinfo" << 'INFOEOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "═══════════════════════════════════════"
echo "       PHONE SERVER STATUS"
echo "═══════════════════════════════════════"
echo ""
echo "📱 Device:"
getprop ro.product.model 2>/dev/null || echo "  Unknown"
echo ""
echo "⏱️  Uptime:"
uptime -p 2>/dev/null || uptime
echo ""
echo "💾 Memory:"
free -h 2>/dev/null || cat /proc/meminfo | head -3
echo ""
echo "💿 Disk:"
df -h /data 2>/dev/null || df -h ~
echo ""
echo "🔋 Battery:"
termux-battery-status 2>/dev/null | jq -c '{percentage: .percentage, status: .status}' 2>/dev/null || echo "  N/A"
echo ""
echo "🌐 Network:"
ip addr show wlan0 2>/dev/null | grep "inet " || echo "  No WiFi"
echo ""
echo "📡 Services:"
pgrep sshd > /dev/null && echo "  sshd:    running" || echo "  sshd:    stopped"
pgrep -f "server.py" > /dev/null && echo "  phoned:  running" || echo "  phoned:  stopped"
echo ""
echo "═══════════════════════════════════════"
INFOEOF
chmod +x "$PHONESRV/bin/sysinfo"

cat > "$PHONESRV/bin/tunnel" << 'TUNEOF'
#!/data/data/com.termux/files/usr/bin/bash
case "${1:-help}" in
  start) sv up cloudflared 2>/dev/null || echo "Not configured" ;;
  stop)  sv down cloudflared 2>/dev/null || echo "Not configured" ;;
  status) sv status cloudflared 2>/dev/null || echo "Not configured" ;;
  *) echo "Usage: tunnel {start|stop|status}" ;;
esac
TUNEOF
chmod +x "$PHONESRV/bin/tunnel"

cat > "$PHONESRV/bin/anon" << 'ANONEOF'
#!/data/data/com.termux/files/usr/bin/bash
case "${1:-status}" in
  on)
    sv up tor 2>/dev/null && echo "[+] Tor started" || echo "[!] Tor not installed"
    sv up privoxy 2>/dev/null && echo "[+] Privoxy started" || echo "[!] Privoxy not installed"
    ;;
  off)
    sv down tor 2>/dev/null
    sv down privoxy 2>/dev/null
    echo "[+] Anonymous mode OFF"
    ;;
  rotate)
    (echo 'AUTHENTICATE'; echo 'SIGNAL NEWNYM'; echo 'QUIT') | nc 127.0.0.1 9051 2>/dev/null
    echo "[+] New circuit requested"
    ;;
  ip)
    curl -s --socks5-hostname 127.0.0.1:9050 https://api.ipify.org 2>/dev/null || echo "Tor not running"
    ;;
  status)
    pgrep tor > /dev/null && echo "Tor: running" || echo "Tor: stopped"
    ;;
  *) echo "Usage: anon {on|off|rotate|ip|status}" ;;
esac
ANONEOF
chmod +x "$PHONESRV/bin/anon"

cat > "$PHONESRV/bin/restart-all" << 'RESEOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "[*] Restarting all services..."
pkill sshd 2>/dev/null; sleep 1; sshd && echo "[+] sshd" || echo "[!] sshd failed"
sv restart phoned 2>/dev/null && echo "[+] phoned" || echo "[!] phoned"
sv restart tor 2>/dev/null && echo "[+] tor" || echo "[!] tor skipped"
sv restart nginx 2>/dev/null && echo "[+] nginx" || echo "[!] nginx skipped"
sv restart cloudflared 2>/dev/null && echo "[+] cloudflared" || echo "[!] cloudflared skipped"
echo "[+] Done"
RESEOF
chmod +x "$PHONESRV/bin/restart-all"

cat > "$PHONESRV/bin/start-sshd" << 'SSHEOF'
#!/data/data/com.termux/files/usr/bin/bash
pkill sshd 2>/dev/null
sleep 1
sshd
if pgrep sshd > /dev/null 2>&1; then
    echo "[+] sshd started on port 8022"
else
    echo "[!] sshd failed to start"
fi
SSHEOF
chmod +x "$PHONESRV/bin/start-sshd"

# Add bin to PATH
echo 'export PATH="$HOME/.phonesrv/bin:$HOME/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/.phonesrv/bin:$HOME/bin:$PATH"

log "Helper scripts installed"

# ============================================================
# START EVERYTHING
# ============================================================
echo -e "\n${CYAN}═══ Starting Services ═══${NC}"

# Make sure sshd is running
if ! pgrep sshd > /dev/null 2>&1; then
    sshd 2>/dev/null
fi

# Start phoned server in background
cd "$PHONESRV"
nohup python server.py > logs/server.log 2>&1 &
sleep 2

if pgrep -f "server.py" > /dev/null 2>&1; then
    log "phoned server started on port 5000"
else
    warn "phoned server didn't start - check logs"
fi

# ============================================================
# DONE
# ============================================================
echo -e "\n${GREEN}╔══════════════════════════════════════════════════╗"
echo -e "║           SETUP COMPLETE!                        ║"
echo -e "╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Phone Info:${NC}"
echo "  Username:  ${GREEN}$(whoami)${NC}"
echo "  SSH Port:  ${GREEN}8022${NC}"
IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
echo "  Local IP:  ${GREEN}${IP:-check wifi settings}${NC}"
echo ""
echo -e "${YELLOW}From your laptop:${NC}"
echo "  ${GREEN}ssh -p 8022 $(whoami)@${IP:-<phone-ip>}${NC}"
echo ""
echo -e "${YELLOW}If SSH doesn't work, try:${NC}"
echo "  ${GREEN}sshd${NC}            # Restart SSH"
echo "  ${GREEN}passwd${NC}          # Set password"
echo ""
echo -e "${YELLOW}Quick commands:${NC}"
echo "  sysinfo        - System status"
echo "  start-sshd     - Start SSH server"
echo "  anon on/off    - Anonymous mode"
echo "  restart-all    - Restart everything"
echo ""
