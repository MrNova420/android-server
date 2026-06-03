#!/usr/bin/env python3
"""
phoned - Phone Server API
Production-grade backend for Android phone server.
"""
import os
import sys
import json
import subprocess
import time
import signal
import logging
import secrets
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, Any, List
from functools import wraps

from fastapi import FastAPI, HTTPException, Query, Body, Depends, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

try:
    import psutil
except ImportError:
    psutil = None

# ============================================================
# CONFIG
# ============================================================

PHONESRV = Path.home() / ".phonesrv"
PROJECTS_DIR = Path.home() / "projects"
LOGS_DIR = PHONESRV / "logs"
TOKEN_FILE = PHONESRV / "config" / "token"
LOG_FILE = PHONESRV / "logs" / "server.log"

# Setup logging
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(str(LOG_FILE)),
        logging.StreamHandler(sys.stdout),
    ],
)
logger = logging.getLogger("phoned")

# ============================================================
# AUTH
# ============================================================

def get_token():
    """Load API token from file."""
    try:
        return TOKEN_FILE.read_text().strip()
    except FileNotFoundError:
        # Generate and save a new token
        token = secrets.token_urlsafe(32)
        TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
        TOKEN_FILE.write_text(token)
        TOKEN_FILE.chmod(0o600)
        logger.info(f"Generated new API token: {token}")
        return token

API_TOKEN = get_token()
security = HTTPBearer(auto_error=False)

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Verify API token."""
    if not credentials or credentials.credentials != API_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid or missing API token")
    return True

# ============================================================
# APP
# ============================================================

app = FastAPI(
    title="phoned",
    description="Android Phone Server Control API",
    version="2.0.0",
    docs_url="/docs" if os.environ.get("PHONED_DEV") else None,
    redoc_url=None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================================
# HELPERS
# ============================================================

def run_cmd(cmd: str, timeout: int = 30) -> Dict[str, Any]:
    """Run a shell command safely."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return {
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip(),
            "code": result.returncode,
            "ok": result.returncode == 0,
        }
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": "Command timed out", "code": -1, "ok": False}
    except Exception as e:
        logger.error(f"Command failed: {cmd} - {e}")
        return {"stdout": "", "stderr": str(e), "code": -1, "ok": False}

def safe_path(path: str) -> str:
    """Expand and validate a file path."""
    expanded = os.path.expanduser(path)
    # Prevent path traversal
    real = os.path.realpath(expanded)
    home = os.path.realpath(Path.home())
    if not real.startswith(home):
        raise HTTPException(400, "Path outside home directory")
    return real

# ============================================================
# PUBLIC ENDPOINTS (no auth)
# ============================================================

@app.get("/")
def root():
    return {
        "name": "phoned",
        "version": "2.0.0",
        "status": "running",
        "docs": "/docs" if os.environ.get("PHONED_DEV") else None,
    }

@app.get("/health")
def health():
    """Health check (no auth required)."""
    sshd_ok = run_cmd("pgrep sshd")["ok"]
    return {"status": "healthy" if sshd_ok else "degraded", "sshd": sshd_ok}

# ============================================================
# PROTECTED ENDPOINTS
# ============================================================

@app.get("/status")
def status(auth: bool = Depends(verify_token)):
    """Full system status."""
    cpu_pct = 0
    cpu_cores = 0
    mem_total = 0
    mem_used = 0
    mem_pct = 0
    disk_total = 0
    disk_used = 0
    disk_pct = 0

    if psutil:
        cpu_pct = psutil.cpu_percent(interval=0.5)
        cpu_cores = psutil.cpu_count()
        mem = psutil.virtual_memory()
        mem_total = round(mem.total / 1024 / 1024)
        mem_used = round(mem.used / 1024 / 1024)
        mem_pct = mem.percent
        disk = psutil.disk_usage(str(Path.home()))
        disk_total = round(disk.total / 1024 / 1024 / 1024, 1)
        disk_used = round(disk.used / 1024 / 1024 / 1024, 1)
        disk_pct = disk.percent

    battery = {}
    try:
        bat = subprocess.run(
            ["termux-battery-status"], capture_output=True, text=True, timeout=5
        )
        if bat.returncode == 0:
            battery = json.loads(bat.stdout)
    except Exception:
        battery = {"percentage": -1, "status": "unknown"}

    load = [0, 0, 0]
    try:
        load = list(os.getloadavg())
    except Exception:
        pass

    return {
        "timestamp": datetime.now().isoformat(),
        "cpu": {"percent": cpu_pct, "cores": cpu_cores, "load": load},
        "memory": {"total_mb": mem_total, "used_mb": mem_used, "percent": mem_pct},
        "disk": {"total_gb": disk_total, "used_gb": disk_used, "percent": disk_pct},
        "battery": battery,
        "uptime": run_cmd("uptime -p")["stdout"],
    }

@app.get("/battery")
def battery_status(auth: bool = Depends(verify_token)):
    try:
        result = subprocess.run(
            ["termux-battery-status"], capture_output=True, text=True, timeout=5
        )
        return json.loads(result.stdout)
    except Exception as e:
        return {"error": str(e), "percentage": -1}

# ============================================================
# SERVICES
# ============================================================

@app.get("/services")
def list_services(auth: bool = Depends(verify_token)):
    result = run_cmd("sv -a status 2>/dev/null || echo 'service manager not available'")
    services = []
    for line in result["stdout"].split("\n"):
        line = line.strip()
        if ":" in line and line:
            parts = line.split(":", 1)
            if len(parts) == 2:
                name = parts[0].strip()
                status = parts[1].strip()
                services.append({"name": name, "status": status})
    return {"services": services}

@app.get("/services/{name}")
def service_status(name: str, auth: bool = Depends(verify_token)):
    if not name.isalnum():
        raise HTTPException(400, "Invalid service name")
    result = run_cmd(f"sv status {name} 2>/dev/null || echo 'unknown'")
    return {"name": name, "status": result["stdout"]}

@app.post("/services/{name}/{action}")
def service_action(name: str, action: str, auth: bool = Depends(verify_token)):
    if not name.isalnum() or action not in ["start", "stop", "restart"]:
        raise HTTPException(400, "Invalid parameters")
    cmd_action = {"start": "up", "stop": "down", "restart": "restart"}[action]
    result = run_cmd(f"sv {cmd_action} {name} 2>/dev/null")
    return {"name": name, "action": action, "ok": result["ok"]}

# ============================================================
# COMMAND EXECUTION
# ============================================================

# Block dangerous commands
BLOCKED_CMDS = ["rm -rf /", "mkfs", "dd if=", "> /dev/sd", ":(){ :|:& };:"]

@app.post("/run")
def run_command(cmd: str = Body(..., embed=True), auth: bool = Depends(verify_token)):
    for blocked in BLOCKED_CMDS:
        if blocked in cmd:
            raise HTTPException(400, "Blocked dangerous command")
    result = run_cmd(cmd, timeout=60)
    return result

# ============================================================
# PROJECTS
# ============================================================

@app.get("/projects")
def list_projects(auth: bool = Depends(verify_token)):
    projects = []
    PROJECTS_DIR.mkdir(parents=True, exist_ok=True)
    for item in PROJECTS_DIR.iterdir():
        if item.is_dir():
            run_script = item / "run.sh"
            pm2_check = run_cmd(f"pm2 list --no-color 2>/dev/null | grep {item.name}")
            running = item.name in pm2_check.get("stdout", "")
            size = sum(f.stat().st_size for f in item.rglob("*") if f.is_file())
            projects.append({
                "name": item.name,
                "path": str(item),
                "has_run_script": run_script.exists(),
                "running": running,
                "size_mb": round(size / 1024 / 1024, 2),
            })
    return {"projects": projects, "count": len(projects)}

@app.post("/projects/{name}")
def create_project(name: str, auth: bool = Depends(verify_token)):
    if not name.replace("-", "").replace("_", "").isalnum():
        raise HTTPException(400, "Invalid project name (alphanumeric, - or _ only)")
    proj_dir = PROJECTS_DIR / name
    if proj_dir.exists():
        raise HTTPException(409, "Project already exists")
    proj_dir.mkdir(parents=True)
    (proj_dir / "run.sh").write_text(f"#!/bin/bash\necho 'Edit run.sh to start {name}'\n")
    (proj_dir / "run.sh").chmod(0o755)
    return {"name": name, "path": str(proj_dir), "created": True}

@app.delete("/projects/{name}")
def delete_project(name: str, auth: bool = Depends(verify_token)):
    proj_dir = PROJECTS_DIR / name
    if not proj_dir.exists():
        raise HTTPException(404, "Project not found")
    run_cmd(f"pm2 delete {name} 2>/dev/null")
    import shutil
    shutil.rmtree(proj_dir)
    return {"name": name, "deleted": True}

@app.post("/projects/{name}/start")
def start_project(name: str, auth: bool = Depends(verify_token)):
    proj_dir = PROJECTS_DIR / name
    run_script = proj_dir / "run.sh"
    if not run_script.exists():
        raise HTTPException(404, "No run.sh found")
    result = run_cmd(f"cd {proj_dir} && pm2 start run.sh --name {name} 2>/dev/null")
    return {"name": name, "ok": result["ok"]}

@app.post("/projects/{name}/stop")
def stop_project(name: str, auth: bool = Depends(verify_token)):
    result = run_cmd(f"pm2 stop {name} 2>/dev/null")
    return {"name": name, "ok": result["ok"]}

@app.get("/projects/{name}/logs")
def project_logs(name: str, lines: int = 50, auth: bool = Depends(verify_token)):
    if lines < 1 or lines > 1000:
        lines = 50
    result = run_cmd(f"pm2 logs {name} --nostream --lines {lines} --no-color 2>/dev/null")
    return {"name": name, "logs": result["stdout"]}

# ============================================================
# NETWORK & ANONYMITY
# ============================================================

@app.get("/network")
def network_info(auth: bool = Depends(verify_token)):
    ip_local = run_cmd("ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}'")["stdout"]
    ip_public = run_cmd("curl -s --max-time 5 https://api.ipify.org 2>/dev/null")["stdout"]
    ip_tor = run_cmd("curl -s --max-time 10 --socks5-hostname 127.0.0.1:9050 https://api.ipify.org 2>/dev/null")["stdout"]
    return {
        "local_ip": ip_local,
        "public_ip": ip_public,
        "tor_ip": ip_tor or "Tor not running",
        "ssh_port": 8022,
    }

@app.get("/tor/status")
def tor_status(auth: bool = Depends(verify_token)):
    tor_running = run_cmd("pgrep tor 2>/dev/null")["ok"]
    tor_ip = run_cmd("curl -s --max-time 10 --socks5-hostname 127.0.0.1:9050 https://api.ipify.org 2>/dev/null")["stdout"]
    onions = []
    onion_dir = Path.home() / ".tor" / "services"
    if onion_dir.exists():
        for f in onion_dir.glob("*/hostname"):
            try:
                onions.append(f.read_text().strip())
            except Exception:
                pass
    return {"running": tor_running, "ip": tor_ip or "N/A", "onion_services": onions}

@app.post("/tor/start")
def tor_start(auth: bool = Depends(verify_token)):
    return {"ok": run_cmd("sv up tor 2>/dev/null")["ok"]}

@app.post("/tor/stop")
def tor_stop(auth: bool = Depends(verify_token)):
    return {"ok": run_cmd("sv down tor 2>/dev/null")["ok"]}

@app.post("/tor/rotate")
def tor_rotate(auth: bool = Depends(verify_token)):
    result = run_cmd("(echo 'AUTHENTICATE'; echo 'SIGNAL NEWNYM'; echo 'QUIT') | nc 127.0.0.1 9051 2>/dev/null")
    return {"ok": result["ok"]}

@app.get("/tunnel/status")
def tunnel_status(auth: bool = Depends(verify_token)):
    result = run_cmd("sv status cloudflared 2>/dev/null || echo 'not configured'")
    return {"status": result["stdout"]}

@app.post("/tunnel/start")
def tunnel_start(auth: bool = Depends(verify_token)):
    return {"ok": run_cmd("sv up cloudflared 2>/dev/null")["ok"]}

@app.post("/tunnel/stop")
def tunnel_stop(auth: bool = Depends(verify_token)):
    return {"ok": run_cmd("sv down cloudflared 2>/dev/null")["ok"]}

# ============================================================
# FILES
# ============================================================

@app.get("/files/list")
def list_files(path: str = "~", auth: bool = Depends(verify_token)):
    real_path = safe_path(path)
    if not os.path.isdir(real_path):
        raise HTTPException(404, "Directory not found")
    result = run_cmd(f"ls -la {real_path}")
    return {"path": path, "listing": result["stdout"]}

@app.get("/files/read")
def read_file(path: str, auth: bool = Depends(verify_token)):
    real_path = safe_path(path)
    if not os.path.isfile(real_path):
        raise HTTPException(404, "File not found")
    size = os.path.getsize(real_path)
    if size > 1_000_000:
        raise HTTPException(400, "File too large (>1MB)")
    try:
        with open(real_path, "r") as f:
            content = f.read()
        return {"path": path, "content": content, "size": size}
    except Exception as e:
        raise HTTPException(500, str(e))

@app.post("/files/write")
def write_file(path: str = Body(...), content: str = Body(...), auth: bool = Depends(verify_token)):
    real_path = safe_path(path)
    try:
        os.makedirs(os.path.dirname(real_path), exist_ok=True)
        with open(real_path, "w") as f:
            f.write(content)
        return {"path": path, "written": len(content)}
    except Exception as e:
        raise HTTPException(500, str(e))

# ============================================================
# DEVICE CONTROL
# ============================================================

@app.post("/device/notification")
def send_notification(title: str = Body(...), message: str = Body(...), auth: bool = Depends(verify_token)):
    result = run_cmd(f'termux-notification -t "{title[:100]}" -c "{message[:500]}"')
    return {"ok": result["ok"]}

@app.post("/device/vibrate")
def vibrate(duration_ms: int = Body(200), auth: bool = Depends(verify_token)):
    duration_ms = max(100, min(5000, duration_ms))
    result = run_cmd(f"termux-vibrate -d {duration_ms}")
    return {"ok": result["ok"]}

@app.post("/device/torch")
def toggle_torch(on: bool = Body(True), auth: bool = Depends(verify_token)):
    result = run_cmd(f"termux-torch {'on' if on else 'off'}")
    return {"ok": result["ok"], "state": "on" if on else "off"}

@app.get("/device/clipboard")
def get_clipboard(auth: bool = Depends(verify_token)):
    result = run_cmd("termux-clipboard-get")
    return {"content": result["stdout"]}

@app.get("/device/location")
def get_location(auth: bool = Depends(verify_token)):
    result = run_cmd("termux-location")
    try:
        return json.loads(result["stdout"])
    except Exception:
        return {"error": "Could not get location"}

# ============================================================
# MAINTENANCE
# ============================================================

@app.post("/maint/update")
def system_update(auth: bool = Depends(verify_token)):
    result = run_cmd("pkg update -y && pkg upgrade -y", timeout=120)
    return {"ok": result["ok"], "output": result["stdout"]}

@app.post("/maint/clean")
def system_clean(auth: bool = Depends(verify_token)):
    result = run_cmd("pkg clean -y 2>/dev/null; rm -rf /tmp/* 2>/dev/null")
    return {"ok": result["ok"]}

@app.post("/maint/reboot")
def reboot_device(auth: bool = Depends(verify_token)):
    result = run_cmd("reboot")
    return {"ok": result["ok"]}

@app.get("/maint/health")
def health_check(auth: bool = Depends(verify_token)):
    checks = {}
    checks["sshd"] = {"running": run_cmd("pgrep sshd 2>/dev/null")["ok"]}
    checks["phoned"] = {"running": run_cmd("pgrep -f 'server.py' 2>/dev/null")["ok"]}
    checks["tor"] = {"running": run_cmd("pgrep tor 2>/dev/null")["ok"]}

    if psutil:
        mem = psutil.virtual_memory()
        disk = psutil.disk_usage(str(Path.home()))
        checks["memory"] = {"percent": mem.percent, "warning": mem.percent > 90}
        checks["disk"] = {"percent": disk.percent, "warning": disk.percent > 90}

    try:
        bat = subprocess.run(["termux-battery-status"], capture_output=True, text=True, timeout=5)
        bat_data = json.loads(bat.stdout)
        pct = bat_data.get("percentage", 100)
        checks["battery"] = {"percent": pct, "warning": pct < 20}
    except Exception:
        checks["battery"] = {"percent": -1, "warning": False}

    healthy = all(
        v.get("running", True) if isinstance(v, dict) else True
        for v in checks.values()
    )
    return {"healthy": healthy, "checks": checks, "timestamp": datetime.now().isoformat()}

@app.post("/maint/ssh-restart")
def restart_ssh(auth: bool = Depends(verify_token)):
    run_cmd("pkill sshd 2>/dev/null")
    time.sleep(1)
    result = run_cmd("sshd 2>/dev/null")
    running = run_cmd("pgrep sshd 2>/dev/null")["ok"]
    return {"ok": running, "output": result["stdout"]}

# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":
    import uvicorn

    logger.info(f"phoned starting on port {API_PORT}")
    logger.info(f"API token: {API_TOKEN}")

    # Handle signals gracefully
    def shutdown(sig, frame):
        logger.info("Shutting down...")
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    uvicorn.run(app, host="0.0.0.0", port=API_PORT, log_level="info")
