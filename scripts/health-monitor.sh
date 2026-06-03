#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# HEALTH MONITOR - Continuous health checks + auto-repair
# ============================================================

PHONESRV="$HOME/.phonesrv"
LOG="$PHONESRV/logs/health.log"
mkdir -p "$PHONESRV/logs"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# ============================================================
# CHECK: SSH
# ============================================================
check_ssh() {
    if pgrep sshd > /dev/null 2>&1; then
        # Test if it's actually listening
        if command -v ss > /dev/null 2>&1; then
            if ss -tln | grep -q ":8022"; then
                return 0
            fi
        fi
        # Fallback: try to connect locally
        if timeout 3 bash -c "echo > /dev/tcp/127.0.0.1/8022" 2>/dev/null; then
            return 0
        fi
        log "WARN: sshd running but not listening on 8022"
    fi
    return 1
}

fix_ssh() {
    log "FIX: Restarting sshd"
    pkill sshd 2>/dev/null
    sleep 2
    rm -f /tmp/sshd.pid 2>/dev/null || true
    ssh-keygen -A 2>/dev/null || true
    sshd 2>/dev/null
    sleep 2
    if pgrep sshd > /dev/null 2>&1; then
        log "FIX: sshd restored"
        return 0
    else
        log "FIX: sshd FAILED to restore"
        return 1
    fi
}

# ============================================================
# CHECK: phoned API
# ============================================================
check_phoned() {
    if pgrep -f "server.py" > /dev/null 2>&1; then
        # Test if API responds
        if timeout 5 curl -sf http://localhost:5000/health > /dev/null 2>&1; then
            return 0
        fi
        log "WARN: phoned running but API not responding"
    fi
    return 1
}

fix_phoned() {
    log "FIX: Restarting phoned"
    pkill -f "server.py" 2>/dev/null
    sleep 2
    cd "$PHONESRV" 2>/dev/null
    if [ -f server.py ]; then
        nohup python server.py >> logs/server.log 2>&1 &
        sleep 3
        if pgrep -f "server.py" > /dev/null 2>&1; then
            log "FIX: phoned restored"
            return 0
        fi
    fi
    log "FIX: phoned FAILED to restore"
    return 1
}

# ============================================================
# CHECK: Disk Space
# ============================================================
check_disk() {
    local pct=$(df /data 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "$pct" -gt 95 ] 2>/dev/null; then
        return 1
    fi
    return 0
}

fix_disk() {
    log "FIX: Cleaning disk space"
    pkg clean -y 2>/dev/null || true
    rm -rf /tmp/* 2>/dev/null || true
    rm -rf ~/.cache/pip/http 2>/dev/null || true
    # Clean old logs
    find "$PHONESRV/logs" -name "*.log" -size +10M -exec truncate -s 1M {} \; 2>/dev/null || true
    log "FIX: Disk cleanup done"
}

# ============================================================
# CHECK: Memory
# ============================================================
check_memory() {
    if [ -f /proc/meminfo ]; then
        local free=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        if [ "$free" -lt 30000 ] 2>/dev/null; then
            return 1
        fi
    fi
    return 0
}

fix_memory() {
    log "FIX: Memory pressure - clearing caches"
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    # Kill any zombie processes
    pkill -9 defunct 2>/dev/null || true
}

# ============================================================
# MAIN LOOP
# ============================================================

log "Health monitor started"

FAIL_COUNT_SSH=0
FAIL_COUNT_PHONED=0

while true; do
    # SSH check
    if ! check_ssh; then
        FAIL_COUNT_SSH=$((FAIL_COUNT_SSH + 1))
        if [ "$FAIL_COUNT_SSH" -ge 2 ]; then
            log "ALERT: SSH down for ${FAIL_COUNT_SSH} checks"
            fix_ssh
            FAIL_COUNT_SSH=0
        fi
    else
        FAIL_COUNT_SSH=0
    fi

    # phoned check
    if ! check_phoned; then
        FAIL_COUNT_PHONED=$((FAIL_COUNT_PHONED + 1))
        if [ "$FAIL_COUNT_PHONED" -ge 2 ]; then
            log "ALERT: phoned down for ${FAIL_COUNT_PHONED} checks"
            fix_phoned
            FAIL_COUNT_PHONED=0
        fi
    else
        FAIL_COUNT_PHONED=0
    fi

    # Disk check (every 5 minutes)
    if [ $(($(date +%s) % 300)) -lt 30 ]; then
        check_disk || fix_disk
    fi

    # Memory check (every 2 minutes)
    if [ $(($(date +%s) % 120)) -lt 30 ]; then
        check_memory || fix_memory
    fi

    sleep 30
done
