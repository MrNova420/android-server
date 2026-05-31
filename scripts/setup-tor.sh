#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# Tor Setup Script
# Run this ON YOUR PHONE in Termux
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PHONESRV="$HOME/.phonesrv"

echo -e "${BLUE}═══ Tor Anonymity Setup ═══${NC}"
echo ""

# Install packages
echo -e "${YELLOW}[*] Installing Tor and Privoxy...${NC}"
pkg install -y tor privoxy

# Create directories
mkdir -p "$HOME/.tor/services/ssh"
mkdir -p "$HOME/.tor/services/web"
mkdir -p "$HOME/.tor/services/api"
mkdir -p "$PHONESRV/logs"

# Copy torrc
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/../configs/torrc" ]; then
    cp "$SCRIPT_DIR/../configs/torrc" "$PREFIX/etc/tor/torrc"
else
    # Generate default torrc
    cat > "$PREFIX/etc/tor/torrc" << 'EOF'
SocksPort 9050
ControlPort 9051
CookieAuthentication 1
Log notice file /data/data/com.termux/files/home/.phonesrv/logs/tor.log

HiddenServiceDir /data/data/com.termux/files/home/.tor/services/ssh/
HiddenServicePort 22 127.0.0.1:8022

HiddenServiceDir /data/data/com.termux/files/home/.tor/services/web/
HiddenServicePort 80 127.0.0.1:8080

HiddenServiceDir /data/data/com.termux/files/home/.tor/services/api/
HiddenServicePort 5000 127.0.0.1:5000

CircuitBuildTimeout 60
KeepAlivePeriod 60
EOF
fi

# Configure Privoxy
cat > "$PREFIX/etc/privoxy/config" << 'EOF'
listen-address 127.0.0.1:8118
forward-socks5t / 127.0.0.1:9050 .
toggle 0
EOF

# Create runit services
# Tor service
TOR_SVC="$PREFIX/var/service/tor"
mkdir -p "$TOR_SVC/log"
ln -sf "$PREFIX/share/termux-services/svlogger" "$TOR_SVC/log/run" 2>/dev/null || true
cat > "$TOR_SVC/run" << 'EOF'
#!/bin/bash
exec tor
EOF
chmod +x "$TOR_SVC/run"

# Privoxy service
PRIVOXY_SVC="$PREFIX/var/service/privoxy"
mkdir -p "$PRIVOXY_SVC/log"
ln -sf "$PREFIX/share/termux-services/svlogger" "$PRIVOXY_SVC/log/run" 2>/dev/null || true
cat > "$PRIVOXY_SVC/run" << 'EOF'
#!/bin/bash
exec privoxy /data/data/com.termux/files/usr/etc/privoxy/config
EOF
chmod +x "$PRIVOXY_SVC/run"

# Enable services
sv-enable tor
sv-enable privoxy

# Create IP rotation script
cat > "$PHONESRV/bin/rotate-tor" << 'ROTATE'
#!/data/data/com.termux/files/usr/bin/bash
# Rotate Tor circuit to get a new IP
echo "[*] Requesting new Tor circuit..."
(echo 'AUTHENTICATE'; echo 'SIGNAL NEWNYM'; echo 'QUIT') | nc 127.0.0.1 9051 2>/dev/null
sleep 2
echo "[+] New Tor IP:"
curl -s --socks5-hostname 127.0.0.1:9050 https://api.ipify.org
echo ""
ROTATE
chmod +x "$PHONESRV/bin/rotate-tor"

# Create test script
cat > "$PHONESRV/bin/test-tor" << 'TEST'
#!/data/data/com.termux/files/usr/bin/bash
echo "═══════════════════════════════════"
echo "  Tor Connection Test"
echo "═══════════════════════════════════"
echo ""
echo -n "Direct IP:     "
curl -s --max-time 5 https://api.ipify.org || echo "FAILED"
echo ""
echo -n "Tor IP:        "
curl -s --max-time 10 --socks5-hostname 127.0.0.1:9050 https://api.ipify.org || echo "FAILED (Tor not ready)"
echo ""
echo ""
if [ -d "$HOME/.tor/services/ssh" ]; then
    ONION=$(cat "$HOME/.tor/services/ssh/hostname" 2>/dev/null || echo "not ready")
    echo "SSH .onion:    $ONION"
fi
if [ -d "$HOME/.tor/services/web" ]; then
    ONION=$(cat "$HOME/.tor/services/web/hostname" 2>/dev/null || echo "not ready")
    echo "Web .onion:    $ONION"
fi
if [ -d "$HOME/.tor/services/api" ]; then
    ONION=$(cat "$HOME/.tor/services/api/hostname" 2>/dev/null || echo "not ready")
    echo "API .onion:    $ONION"
fi
echo ""
echo "═══════════════════════════════════"
TEST
chmod +x "$PHONESRV/bin/test-tor"

echo ""
echo -e "${GREEN}[+] Tor setup complete!${NC}"
echo ""
echo "Start services:"
echo "  sv up tor"
echo "  sv up privoxy"
echo ""
echo "Test connection:"
echo "  test-tor"
echo ""
echo "Rotate IP:"
echo "  rotate-tor"
echo ""
echo "Get .onion addresses:"
echo "  cat ~/.tor/services/ssh/hostname"
echo "  cat ~/.tor/services/web/hostname"
echo "  cat ~/.tor/services/api/hostname"
echo ""
echo "Proxy settings:"
echo "  SOCKS5: 127.0.0.1:9050"
echo "  HTTP:   127.0.0.1:8118"
echo ""
