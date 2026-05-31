#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# PHONE SERVER - Full Bootstrap Script
# Run this ON YOUR PHONE in Termux
# ============================================================
set -euo pipefail

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
pkg update -y && pkg upgrade -y

log "Installing core packages..."
pkg install -y \
  openssh tmux curl wget git python \
  termux-services termux-api jq htop \
  nano vim rsync socat net-tools \
  proot-distro zip unzip tree

log "Installing optional but recommended..."
pkg install -y \
  nodejs npm golang rust \
  nginx privoxy tor \
  jq yq

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
# STEP 3: SSH Hardening
# ============================================================
echo -e "\n${CYAN}═══ STEP 3: Configuring SSH ═══${NC}"

SSHD_CONFIG="$PREFIX/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "$SSHD_CONFIG.bak" 2>/dev/null || true

cat > "$SSHD_CONFIG" << 'SSHEOF'
Port 8022
AddressFamily any
ListenAddress 0.0.0.0

# Authentication
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin no
AuthenticationMethods publickey

# Security
X11Forwarding no
AllowTcpForwarding yes
AllowAgentForwarding no
MaxAuthTries 3
MaxSessions 5
ClientAliveInterval 60
ClientAliveCountMax 3

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Misc
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
SSHEOF

log "SSH configured (port 8022, key-only auth)"
info "Set a password with 'passwd' (for emergency access only)"

# ============================================================
# STEP 4: Service Manager
# ============================================================
echo -e "\n${CYAN}═══ STEP 4: Enabling Service Manager ═══${NC}"

sv-enable sshd
sv up sshd
log "sshd service enabled"

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

# Start all runit services
exec runsvdir -P $PREFIX/var/service &
BOOTEOF
chmod +x "$HOME/.termux/boot/start-server.sh"
log "Boot script created"

# ============================================================
# STEP 6: phoned Server
# ============================================================
echo -e "\n${CYAN}═══ STEP 6: Installing phoned Server ═══${NC}"

pip install --upgrade pip 2>/dev/null || pip3 install --upgrade pip
pip install fastapi uvicorn psutil requests 2>/dev/null || \
pip3 install fastapi uvicorn psutil requests

# Copy server files
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$SCRIPT_DIR/server" ]; then
  cp -r "$SCRIPT_DIR/server/"* "$PHONESRV/"
  log "Server files copied"
else
  warn "Server files not found - run setup from the project directory"
fi

# Create phoned systemd-style service
mkdir -p "$PREFIX/var/service/phoned/log"
ln -sf "$PREFIX/share/termux-services/svlogger" "$PREFIX/var/service/phoned/log/run" 2>/dev/null || true

cat > "$PREFIX/var/service/phoned/run" << 'SVCEOF'
#!/bin/bash
cd $HOME/.phonesrv
exec python server.py
SVCEOF
chmod +x "$PREFIX/var/service/phoned/run"

sv-enable phoned
log "phoned server installed"

# ============================================================
# STEP 7: Process Manager (pm2)
# ============================================================
echo -e "\n${CYAN}═══ STEP 7: Installing Process Manager ═══${NC}"

npm install -g pm2 2>/dev/null || true
pm2 startup termux 2>/dev/null || true
log "pm2 installed"

# ============================================================
# STEP 8: Terminal Shell RC
# ============================================================
echo -e "\n${CYAN}═══ STEP 8: Setting Up Shell ═══${NC}"

cat >> "$HOME/.bashrc" << 'RCLOG'

# === Phone Server Aliases ===
export PHONESRV="$HOME/.phonesrv"
export PATH="$HOME/bin:$PATH"

alias ps-status='curl -s http://localhost:5000/status | jq'
alias ps-services='curl -s http://localhost:5000/services | jq'
alias ps-projects='ls -la ~/projects/'
alias ps-logs='tail -f $HOME/.phonesrv/logs/*.log'
alias ps-restart='sv restart phoned'
alias ps-sshlog='tail -f $PREFIX/var/log/sv/sshd/current'

# Quick project deploy
deploy() {
  if [ -z "$1" ]; then
    echo "Usage: deploy <local-path>"
    return 1
  fi
  rsync -avzP -e 'ssh -p 8022' "$1" "$(whoami)@localhost:~/projects/"
}

# Quick SSH into this phone
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
# Basic Termux firewall (iptables)
# Note: Limited without root, but blocks some traffic

echo "[*] Applying basic firewall rules..."

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT 2>/dev/null

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null

# Allow SSH
iptables -A INPUT -p tcp --dport 8022 -j ACCEPT 2>/dev/null

# Allow phoned API (local only)
iptables -A INPUT -p tcp --dport 5000 -s 127.0.0.1 -j ACCEPT 2>/dev/null

# Allow HTTP (local only)
iptables -A INPUT -p tcp --dport 8080 -s 127.0.0.1 -j ACCEPT 2>/dev/null

echo "[+] Firewall rules applied"
FWEOF
chmod +x "$PHONESRV/bin/firewall.sh"
log "Firewall script created"

# ============================================================
# STEP 10: Helper Scripts
# ============================================================
echo -e "\n${CYAN}═══ STEP 10: Creating Helper Scripts ═══${NC}"

# System info script
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
termux-battery-status 2>/dev/null | jq -c '{percentage: .percentage, status: .status, temperature: .temperature}' 2>/dev/null || echo "  Install termux-api"
echo ""
echo "🌡️  CPU:"
top -bn1 | head -5 2>/dev/null || echo "  N/A"
echo ""
echo "🌐 Network:"
ip addr show wlan0 2>/dev/null | grep "inet " || echo "  No WiFi"
echo ""
echo "📡 Services:"
sv status sshd 2>/dev/null || echo "  sshd: unknown"
sv status phoned 2>/dev/null || echo "  phoned: unknown"
echo ""
echo "═══════════════════════════════════════"
INFOEOF
chmod +x "$PHONESRV/bin/sysinfo"

# Quick tunnel script
cat > "$PHONESRV/bin/tunnel" << 'TUNEOF'
#!/data/data/com.termux/files/usr/bin/bash
# Quick tunnel management
case "${1:-help}" in
  start)
    sv up cloudflared 2>/dev/null || echo "cloudflared not configured"
    ;;
  stop)
    sv down cloudflared 2>/dev/null || echo "cloudflared not configured"
    ;;
  status)
    sv status cloudflared 2>/dev/null || echo "cloudflared not configured"
    ;;
  *)
    echo "Usage: tunnel {start|stop|status}"
    ;;
esac
TUNEOF
chmod +x "$PHONESRV/bin/tunnel"

# Anonymous mode
cat > "$PHONESRV/bin/anon" << 'ANONEOF'
#!/data/data/com.termux/files/usr/bin/bash
case "${1:-status}" in
  on)
    echo "[*] Enabling anonymous mode..."
    sv up tor 2>/dev/null && echo "[+] Tor started" || echo "[!] Tor not installed"
    sv up privoxy 2>/dev/null && echo "[+] Privoxy started" || echo "[!] Privoxy not installed"
    echo "[+] Anonymous mode ON"
    ;;
  off)
    echo "[*] Disabling anonymous mode..."
    sv down tor 2>/dev/null
    sv down privoxy 2>/dev/null
    echo "[+] Anonymous mode OFF"
    ;;
  rotate)
    echo "[*] Rotating Tor circuit..."
    (echo 'AUTHENTICATE'; echo 'SIGNAL NEWNYM'; echo 'QUIT') | nc 127.0.0.1 9051 2>/dev/null
    echo "[+] New circuit established"
    ;;
  ip)
    curl -s --socks5-hostname 127.0.0.1:9050 https://api.ipify.org 2>/dev/null || echo "Tor not running"
    ;;
  status)
    sv status tor 2>/dev/null || echo "Tor: not installed"
    sv status privoxy 2>/dev/null || echo "Privoxy: not installed"
    ;;
  *)
    echo "Usage: anon {on|off|rotate|ip|status}"
    ;;
esac
ANONEOF
chmod +x "$PHONESRV/bin/anon"

# Deploy helper
cat > "$PHONESRV/bin/deploy" << 'DEPLOYEOF'
#!/data/data/com.termux/files/usr/bin/bash
# Deploy a project from local machine
# Usage: deploy <project-name> [source-path]
if [ -z "$1" ]; then
  echo "Usage: deploy <project-name> [source-path]"
  echo "  If source-path omitted, creates empty project dir"
  exit 1
fi

PROJ_NAME="$1"
PROJ_DIR="$HOME/projects/$PROJ_NAME"
mkdir -p "$PROJ_DIR"

if [ -n "$2" ] && [ -d "$2" ]; then
  cp -r "$2"/* "$PROJ_DIR"/
  echo "[+] Deployed $2 -> $PROJ_DIR"
else
  echo "[+] Created project: $PROJ_DIR"
fi

# Create a basic run script
if [ ! -f "$PROJ_DIR/run.sh" ]; then
  cat > "$PROJ_DIR/run.sh" << 'RUNEOF'
#!/bin/bash
# Project run script - edit this
echo "Edit this script to run your project"
echo "Example: python app.py"
echo "Example: node server.js"
RUNEOF
  chmod +x "$PROJ_DIR/run.sh"
  echo "[+] Created run.sh template"
fi

echo "[+] Use 'pm2 start $PROJ_DIR/run.sh --name $PROJ_NAME' to start"
DEPLOYEOF
chmod +x "$PHONESRV/bin/deploy"

# Restart helper
cat > "$PHONESRV/bin/restart-all" << 'RESEOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "[*] Restarting all services..."
sv restart sshd 2>/dev/null && echo "[+] sshd" || echo "[!] sshd failed"
sv restart phoned 2>/dev/null && echo "[+] phoned" || echo "[!] phoned failed"
sv restart tor 2>/dev/null && echo "[+] tor" || echo "[!] tor skipped"
sv restart nginx 2>/dev/null && echo "[+] nginx" || echo "[!] nginx skipped"
sv restart cloudflared 2>/dev/null && echo "[+] cloudflared" || echo "[!] cloudflared skipped"
echo "[+] All services restarted"
RESEOF
chmod +x "$PHONESRV/bin/restart-all"

# Add bin to PATH
export PATH="$HOME/.phonesrv/bin:$HOME/bin:$PATH"
echo 'export PATH="$HOME/.phonesrv/bin:$HOME/bin:$PATH"' >> "$HOME/.bashrc"

log "Helper scripts installed"
info "Available commands: sysinfo, tunnel, anon, deploy, restart-all"

# ============================================================
# DONE
# ============================================================
echo -e "\n${GREEN}╔══════════════════════════════════════════════════╗"
echo -e "║           SETUP COMPLETE!                        ║"
echo -e "╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Set a password:  ${GREEN}passwd${NC}"
echo "  2. Add your laptop SSH key:"
echo "     ${GREEN}echo 'ssh-ed25519 AAAA... your@email.com' >> ~/.ssh/authorized_keys${NC}"
echo "  3. Note your username:  ${GREEN}whoami${NC}"
echo "  4. Note your IP:  ${GREEN}ip addr show wlan0 | grep inet${NC}"
echo "  5. Connect from laptop:  ${GREEN}ssh -p 8022 <username>@<ip>${NC}"
echo "  6. Start phoned:  ${GREEN}sv up phoned${NC}"
echo "  7. Check status:  ${GREEN}sysinfo${NC}"
echo ""
echo -e "${PURPLE}Commands:${NC}"
echo "  sysinfo       - System status"
echo "  anon on/off   - Anonymous mode"
echo "  tunnel start  - Start Cloudflare tunnel"
echo "  deploy <name> - Deploy a project"
echo "  restart-all   - Restart all services"
echo ""
