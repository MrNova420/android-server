#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# BOOT SCRIPT - Bulletproof startup for phone server
# Place at: ~/.termux/boot/start-server.sh
# ============================================================

# Keep CPU alive - CRITICAL for always-on
termux-wake-lock

# Wait for system to stabilize
sleep 20

# Source Termux environment
. $PREFIX/etc/profile 2>/dev/null

LOG="$HOME/.phonesrv/logs/boot.log"
mkdir -p "$HOME/.phonesrv/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

log "=== BOOT SEQUENCE START ==="

# ============================================================
# 1. SSH - ALWAYS RUNNING
# ============================================================
log "Starting SSH..."
if ! pgrep sshd > /dev/null 2>&1; then
    # Generate keys if missing
    ssh-keygen -A 2>/dev/null || true
    
    # Kill stale lock files
    rm -f /tmp/sshd.pid 2>/dev/null || true
    
    # Start sshd
    sshd 2>/dev/null
    sleep 2
    
    if pgrep sshd > /dev/null 2>&1; then
        log "SSH: OK (port 8022)"
    else
        log "SSH: FAILED - retrying..."
        sleep 5
        sshd 2>/dev/null
        sleep 2
        pgrep sshd > /dev/null 2>&1 && log "SSH: OK (retry)" || log "SSH: FAILED permanently"
    fi
else
    log "SSH: Already running"
fi

# ============================================================
# 2. PHONED SERVER - ALWAYS RUNNING
# ============================================================
log "Starting phoned server..."
if ! pgrep -f "server.py" > /dev/null 2>&1; then
    cd "$HOME/.phonesrv" 2>/dev/null
    
    if [ -f server.py ]; then
        nohup python server.py >> logs/server.log 2>&1 &
        sleep 3
        
        if pgrep -f "server.py" > /dev/null 2>&1; then
            log "phoned: OK (port 5000)"
        else
            log "phoned: FAILED - check logs/server.log"
        fi
    else
        log "phoned: server.py not found"
    fi
else
    log "phoned: Already running"
fi

# ============================================================
# 3. START WATCHDOG
# ============================================================
log "Starting watchdog..."
if ! pgrep -f "watchdog.sh" > /dev/null 2>&1; then
    nohup bash "$HOME/.phonesrv/scripts/watchdog.sh" >> "$HOME/.phonesrv/logs/watchdog.log" 2>&1 &
    sleep 1
    pgrep -f "watchdog.sh" > /dev/null 2>&1 && log "Watchdog: OK" || log "Watchdog: FAILED"
else
    log "Watchdog: Already running"
fi

# ============================================================
# 4. START RUNIT SERVICES (if configured)
# ============================================================
if command -v runsvdir > /dev/null 2>&1; then
    if [ -d "$PREFIX/var/service" ]; then
        log "Starting runit services..."
        # Non-blocking: let runit manage services in background
        runsvdir -P "$PREFIX/var/service" &
    fi
fi

# ============================================================
# 5. OPTIONAL SERVICES
# ============================================================

# Tor (if configured)
if [ -f "$HOME/.phonesrv/config/tor_enabled" ]; then
    sv up tor 2>/dev/null && log "Tor: OK" || log "Tor: Failed"
fi

# Cloudflare tunnel (if configured)
if [ -f "$HOME/.phonesrv/config/tunnel_enabled" ]; then
    sv up cloudflared 2>/dev/null && log "Tunnel: OK" || log "Tunnel: Failed"
fi

log "=== BOOT SEQUENCE COMPLETE ==="
