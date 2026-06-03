#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# WATCHDOG - Auto-restart crashed services
# Runs as a background daemon, monitors all services
# ============================================================

PHONESRV="$HOME/.phonesrv"
LOG="$PHONESRV/logs/watchdog.log"
PID_FILE="$PHONESRV/logs/watchdog.pid"
CHECK_INTERVAL=30  # seconds between checks

mkdir -p "$PHONESRV/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

# Prevent multiple instances
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Watchdog already running (PID $OLD_PID)"
        exit 1
    fi
fi
echo $$ > "$PID_FILE"

cleanup() {
    rm -f "$PID_FILE"
    log "Watchdog stopped"
    exit 0
}
trap cleanup SIGTERM SIGINT

log "Watchdog started (PID $$)"

# ============================================================
# SERVICE DEFINITIONS
# ============================================================
# Format: "name:command:critical"
# critical=1 means restart immediately if down
# critical=0 means log only

declare -A SERVICES
SERVICES[sshd]="sshd:1"
SERVICES[phoned]="cd $PHONESRV && python server.py:1"

# ============================================================
# CHECK FUNCTIONS
# ============================================================

check_service() {
    local name="$1"
    local cmd="$2"
    local critical="$3"

    case "$name" in
        sshd)
            if pgrep sshd > /dev/null 2>&1; then
                return 0
            fi
            log "CRITICAL: sshd is DOWN"
            sshd 2>/dev/null
            sleep 2
            if pgrep sshd > /dev/null 2>&1; then
                log "RECOVERED: sshd restarted"
                return 0
            else
                log "FAILED: sshd could not restart"
                return 1
            fi
            ;;
        phoned)
            if pgrep -f "server.py" > /dev/null 2>&1; then
                return 0
            fi
            log "CRITICAL: phoned is DOWN"
            cd "$PHONESRV" 2>/dev/null
            nohup python server.py >> "$PHONESRV/logs/server.log" 2>&1 &
            sleep 3
            if pgrep -f "server.py" > /dev/null 2>&1; then
                log "RECOVERED: phoned restarted"
                return 0
            else
                log "FAILED: phoned could not restart"
                return 1
            fi
            ;;
        tor)
            if pgrep tor > /dev/null 2>&1; then
                return 0
            fi
            log "INFO: tor is down"
            sv up tor 2>/dev/null || true
            return 0
            ;;
        nginx)
            if pgrep nginx > /dev/null 2>&1; then
                return 0
            fi
            log "INFO: nginx is down"
            sv up nginx 2>/dev/null || true
            return 0
            ;;
    esac
    return 0
}

check_resources() {
    # Check disk space
    if command -v df > /dev/null 2>&1; then
        DISK_PCT=$(df /data 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
        if [ "$DISK_PCT" -gt 95 ] 2>/dev/null; then
            log "WARNING: Disk ${DISK_PCT}% full - cleaning cache"
            pkg clean -y 2>/dev/null || true
            rm -rf /tmp/* 2>/dev/null || true
        fi
    fi

    # Check memory
    if [ -f /proc/meminfo ]; then
        FREE=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        if [ "$FREE" -lt 50000 ] 2>/dev/null; then
            log "WARNING: Low memory (${FREE}KB free)"
        fi
    fi
}

# ============================================================
# MAIN LOOP
# ============================================================

log "Monitoring services..."

while true; do
    # Check each service
    for key in "${!SERVICES[@]}"; do
        IFS=':' read -r name cmd critical <<< "${SERVICES[$key]}"
        check_service "$name" "$cmd" "$critical"
    done

    # Check resources periodically
    check_resources

    sleep "$CHECK_INTERVAL"
done
