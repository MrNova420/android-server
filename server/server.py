#!/usr/bin/env python3
"""
phoned - Phone Server API
FastAPI backend that runs on the Android phone.
Provides remote management, monitoring, and control.
"""
import os
import sys
import json
import subprocess
import time
import signal
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, Any, List

from fastapi import FastAPI, HTTPException, Query, Body
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import psutil

app = FastAPI(
    title="phoned",
    description="Android Phone Server Control API",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

PHONESRV = Path.home() / ".phonesrv"
PROJECTS_DIR = Path.home() / "projects"
LOGS_DIR = PHONESRV / "logs"
CONFIG_DIR = PHONESRV / "config"


def run_cmd(cmd: str, timeout: int = 30) -> Dict[str, Any]:
    """Run a shell command and return structured result."""
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
        return {"stdout": "", "stderr": str(e), "code": -1, "ok": False}


# ──────────────────────────────────────────────
# STATUS & MONITORING
# ──────────────────────────────────────────────

@app.get("/")
def root():
    """API root - shows basic info."""
    return {
        "name": "phoned",
        "version": "1.0.0",
        "uptime": run_cmd("uptime -p")["stdout"],
        "endpoints": [
            "/status", "/services", "/projects", "/logs",
            "/run", "/deploy", "/battery", "/network"
        ]
    }


@app.get("/status")
def status():
    """Full system status."""
    cpu = psutil.cpu_percent(interval=1)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage(str(Path.home()))

    battery = {}
    try:
        bat = subprocess.run(
            ["termux-battery-status"], capture_output=True, text=True, timeout=5
        )
        if bat.returncode == 0:
            battery = json.loads(bat.stdout)
    except Exception:
        battery = {"percentage": -1, "status": "unknown"}

    load = os.getloadavg() if hasattr(os, "getloadavg") else [0, 0, 0]

    return {
        "timestamp": datetime.now().isoformat(),
        "cpu": {
            "percent": cpu,
            "cores": psutil.cpu_count(),
            "load": {"1m": load[0], "5m": load[1], "15m": load[2]},
        },
        "memory": {
            "total_mb": round(mem.total / 1024 / 1024),
            "used_mb": round(mem.used / 1024 / 1024),
            "available_mb": round(mem.available / 1024 / 1024),
            "percent": mem.percent,
        },
        "disk": {
            "total_gb": round(disk.total / 1024 / 1024 / 1024, 1),
            "used_gb": round(disk.used / 1024 / 1024 / 1024, 1),
            "free_gb": round(disk.free / 1024 / 1024 / 1024, 1),
            "percent": disk.percent,
        },
        "battery": battery,
        "uptime": run_cmd("uptime -p")["stdout"],
        "hostname": run_cmd("hostname")["stdout"],
        "load_avg": load,
    }


@app.get("/battery")
def battery_status():
    """Get battery status."""
    try:
        result = subprocess.run(
            ["termux-battery-status"], capture_output=True, text=True, timeout=5
        )
        return json.loads(result.stdout)
    except Exception as e:
        return {"error": str(e), "percentage": -1}


# ──────────────────────────────────────────────
# SERVICES MANAGEMENT
# ──────────────────────────────────────────────

@app.get("/services")
def list_services():
    """List all runit services and their status."""
    result = run_cmd("sv -a status")
    services = []
    for line in result["stdout"].split("\n"):
        line = line.strip()
        if not line or ":" not in line:
            continue
        parts = line.split(":", 1)
        if len(parts) == 2:
            name = parts[0].strip()
            status = parts[1].strip()
            services.append({"name": name, "status": status})
    return {"services": services}


@app.get("/services/{name}")
def service_status(name: str):
    """Get status of a specific service."""
    result = run_cmd(f"sv status {name}")
    return {"name": name, "status": result["stdout"], "ok": result["ok"]}


@app.post("/services/{name}/start")
def start_service(name: str):
    """Start a service."""
    result = run_cmd(f"sv up {name}")
    return {"name": name, "action": "start", "ok": result["ok"], "output": result["stdout"]}


@app.post("/services/{name}/stop")
def stop_service(name: str):
    """Stop a service."""
    result = run_cmd(f"sv down {name}")
    return {"name": name, "action": "stop", "ok": result["ok"], "output": result["stdout"]}


@app.post("/services/{name}/restart")
def restart_service(name: str):
    """Restart a service."""
    result = run_cmd(f"sv restart {name}")
    return {"name": name, "action": "restart", "ok": result["ok"], "output": result["stdout"]}


# ──────────────────────────────────────────────
# COMMAND EXECUTION
# ──────────────────────────────────────────────

@app.post("/run")
def run_command(cmd: str = Body(..., embed=True)):
    """Execute a shell command on the phone."""
    result = run_cmd(cmd, timeout=60)
    return result


@app.post("/run/safe")
def run_safe_command(cmd: str = Body(..., embed=True)):
    """Execute a command with restricted access (no rm -rf, etc)."""
    blocked = ["rm -rf /", "mkfs", "dd if=", "> /dev/sd"]
    for b in blocked:
        if b in cmd:
            return {"stdout": "", "stderr": "Blocked dangerous command", "code": -1, "ok": False}
    result = run_cmd(cmd, timeout=30)
    return result


# ──────────────────────────────────────────────
# PROJECTS
# ──────────────────────────────────────────────

@app.get("/projects")
def list_projects():
    """List all deployed projects."""
    projects = []
    if PROJECTS_DIR.exists():
        for item in PROJECTS_DIR.iterdir():
            if item.is_dir():
                run_script = item / "run.sh"
                has_run = run_script.exists()
                # Check if running via pm2
                pm2_check = run_cmd(f"pm2 list --no-color | grep {item.name}")
                running = item.name in pm2_check.get("stdout", "")

                projects.append({
                    "name": item.name,
                    "path": str(item),
                    "has_run_script": has_run,
                    "running": running,
                    "size_mb": round(
                        sum(f.stat().st_size for f in item.rglob("*") if f.is_file())
                        / 1024 / 1024, 2
                    ),
                })
    return {"projects": projects, "count": len(projects)}


@app.post("/projects/{name}")
def create_project(name: str):
    """Create a new project directory."""
    proj_dir = PROJECTS_DIR / name
    if proj_dir.exists():
        raise HTTPException(400, f"Project '{name}' already exists")

    proj_dir.mkdir(parents=True, exist_ok=True)

    # Create template run script
    run_script = proj_dir / "run.sh"
    run_script.write_text(f"""#!/bin/bash
# Project: {name}
# Edit this script to run your application
echo "Edit run.sh to start your project"
# Example: python app.py
# Example: node server.js
# Example: go run main.go
""")
    run_script.chmod(0o755)

    return {"name": name, "path": str(proj_dir), "created": True}


@app.delete("/projects/{name}")
def delete_project(name: str):
    """Delete a project."""
    proj_dir = PROJECTS_DIR / name
    if not proj_dir.exists():
        raise HTTPException(404, f"Project '{name}' not found")

    # Stop if running
    run_cmd(f"pm2 delete {name}")

    import shutil
    shutil.rmtree(proj_dir)
    return {"name": name, "deleted": True}


@app.post("/projects/{name}/start")
def start_project(name: str):
    """Start a project with pm2."""
    proj_dir = PROJECTS_DIR / name
    run_script = proj_dir / "run.sh"
    if not run_script.exists():
        raise HTTPException(404, f"No run.sh found for project '{name}'")

    result = run_cmd(f"cd {proj_dir} && pm2 start run.sh --name {name}")
    return {"name": name, "action": "start", "ok": result["ok"], "output": result["stdout"]}


@app.post("/projects/{name}/stop")
def stop_project(name: str):
    """Stop a project."""
    result = run_cmd(f"pm2 stop {name}")
    return {"name": name, "action": "stop", "ok": result["ok"], "output": result["stdout"]}


@app.post("/projects/{name}/restart")
def restart_project(name: str):
    """Restart a project."""
    result = run_cmd(f"pm2 restart {name}")
    return {"name": name, "action": "restart", "ok": result["ok"], "output": result["stdout"]}


@app.get("/projects/{name}/logs")
def project_logs(name: str, lines: int = 50):
    """Get project logs."""
    result = run_cmd(f"pm2 logs {name} --nostream --lines {lines} --no-color")
    return {"name": name, "logs": result["stdout"]}


# ──────────────────────────────────────────────
# PROCESS MANAGER
# ──────────────────────────────────────────────

@app.get("/pm2/list")
def pm2_list():
    """List pm2 processes."""
    result = run_cmd("pm2 list --no-color")
    return {"output": result["stdout"]}


@app.post("/pm2/save")
def pm2_save():
    """Save current pm2 process list."""
    result = run_cmd("pm2 save")
    return {"ok": result["ok"], "output": result["stdout"]}


# ──────────────────────────────────────────────
# LOGS
# ──────────────────────────────────────────────

@app.get("/logs/{service}")
def get_logs(service: str, lines: int = 100):
    """Get logs for a runit service."""
    log_file = Path.home() / f". termux/files/usr/var/log/sv/{service}/current"
    alt_log = Path(f"/data/data/com.termux/files/usr/var/log/sv/{service}/current")

    for path in [log_file, alt_log]:
        if path.exists():
            result = run_cmd(f"tail -n {lines} {path}")
            return {"service": service, "logs": result["stdout"]}

    # Fallback: try sv log
    result = run_cmd(f"cat $PREFIX/var/log/sv/{service}/current 2>/dev/null | tail -n {lines}")
    return {"service": service, "logs": result["stdout"]}


@app.get("/logs/app/{name}")
def app_logs(name: str, lines: int = 100):
    """Get application logs from ~/logs/."""
    log_file = Path.home() / "logs" / f"{name}.log"
    if log_file.exists():
        result = run_cmd(f"tail -n {lines} {log_file}")
        return {"name": name, "logs": result["stdout"]}

    return {"name": name, "logs": "No logs found"}


# ──────────────────────────────────────────────
# NETWORK & ANONYMITY
# ──────────────────────────────────────────────

@app.get("/network")
def network_info():
    """Get network information."""
    ip_local = run_cmd("ip addr show wlan0 | grep 'inet ' | awk '{print $2}'")
    ip_public = run_cmd("curl -s --max-time 5 https://api.ipify.org")
    ip_tor = run_cmd("curl -s --max-time 10 --socks5-hostname 127.0.0.1:9050 https://api.ipify.org")

    return {
        "local_ip": ip_local["stdout"],
        "public_ip": ip_public["stdout"],
        "tor_ip": ip_tor["stdout"] or "Tor not running",
        "ssh_port": 8022,
    }


@app.get("/tor/status")
def tor_status():
    """Check Tor status."""
    tor_running = run_cmd("pgrep tor")
    tor_ip = run_cmd("curl -s --max-time 10 --socks5-hostname 127.0.0.1:9050 https://api.ipify.org")

    # Get .onion addresses
    onion_dirs = list((Path.home() / ".tor" / "services").glob("*/hostname"))
    onions = []
    for f in onion_dirs:
        onions.append(f.read_text().strip())

    return {
        "running": tor_running["ok"],
        "ip": tor_ip["stdout"] or "N/A",
        "onion_services": onions,
    }


@app.post("/tor/start")
def tor_start():
    """Start Tor."""
    result = run_cmd("sv up tor")
    return {"action": "tor_start", "ok": result["ok"]}


@app.post("/tor/stop")
def tor_stop():
    """Stop Tor."""
    result = run_cmd("sv down tor")
    return {"action": "tor_stop", "ok": result["ok"]}


@app.post("/tor/rotate")
def tor_rotate():
    """Rotate Tor circuit (get new IP)."""
    result = run_cmd("(echo 'AUTHENTICATE'; echo 'SIGNAL NEWNYM'; echo 'QUIT') | nc 127.0.0.1 9051")
    return {"action": "rotate", "ok": result["ok"], "output": result["stdout"]}


# ──────────────────────────────────────────────
# TUNNEL MANAGEMENT
# ──────────────────────────────────────────────

@app.get("/tunnel/status")
def tunnel_status():
    """Check Cloudflare tunnel status."""
    result = run_cmd("sv status cloudflared")
    return {"cloudflared": result["stdout"], "running": result["ok"]}


@app.post("/tunnel/start")
def tunnel_start():
    """Start Cloudflare tunnel."""
    result = run_cmd("sv up cloudflared")
    return {"action": "tunnel_start", "ok": result["ok"]}


@app.post("/tunnel/stop")
def tunnel_stop():
    """Stop Cloudflare tunnel."""
    result = run_cmd("sv down cloudflared")
    return {"action": "tunnel_stop", "ok": result["ok"]}


# ──────────────────────────────────────────────
# FILE MANAGEMENT
# ──────────────────────────────────────────────

@app.get("/files/list")
def list_files(path: str = "~"):
    """List files in a directory."""
    expanded = run_cmd(f"echo {path}")["stdout"]
    result = run_cmd(f"ls -la {expanded}")
    return {"path": expanded, "listing": result["stdout"]}


@app.get("/files/read")
def read_file(path: str):
    """Read a file (small files only)."""
    size = run_cmd(f"wc -c < {path}")
    try:
        size_bytes = int(size["stdout"])
    except ValueError:
        return {"error": "Could not determine file size"}

    if size_bytes > 1_000_000:
        return {"error": "File too large (>1MB)"}

    try:
        with open(os.path.expanduser(path), "r") as f:
            content = f.read()
        return {"path": path, "content": content, "size": size_bytes}
    except Exception as e:
        return {"error": str(e)}


@app.post("/files/write")
def write_file(path: str = Body(...), content: str = Body(...)):
    """Write content to a file."""
    try:
        full_path = os.path.expanduser(path)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        with open(full_path, "w") as f:
            f.write(content)
        return {"path": path, "written": len(content), "ok": True}
    except Exception as e:
        return {"error": str(e), "ok": False}


# ──────────────────────────────────────────────
# DEVICE CONTROL (Termux:API)
# ──────────────────────────────────────────────

@app.post("/device/notification")
def send_notification(title: str = Body(...), message: str = Body(...)):
    """Send a notification to the phone."""
    result = run_cmd(f'termux-notification -t "{title}" -c "{message}"')
    return {"ok": result["ok"]}


@app.post("/device/vibrate")
def vibrate(duration_ms: int = Body(200)):
    """Vibrate the phone."""
    result = run_cmd(f"termux-vibrate -d {duration_ms}")
    return {"ok": result["ok"]}


@app.post("/device/torch")
def toggle_torch(on: bool = Body(True)):
    """Toggle the flashlight."""
    state = "on" if on else "off"
    result = run_cmd(f"termux-torch {state}")
    return {"ok": result["ok"], "state": state}


@app.get("/device/clipboard")
def get_clipboard():
    """Get clipboard content."""
    result = run_cmd("termux-clipboard-get")
    return {"content": result["stdout"]}


@app.post("/device/clipboard")
def set_clipboard(text: str = Body(...)):
    """Set clipboard content."""
    result = run_cmd(f"termux-clipboard-set '{text}'")
    return {"ok": result["ok"]}


@app.get("/device/location")
def get_location():
    """Get device GPS location."""
    result = run_cmd("termux-location")
    try:
        return json.loads(result["stdout"])
    except Exception:
        return {"error": "Could not get location", "raw": result["stdout"]}


# ──────────────────────────────────────────────
# MAINTENANCE
# ──────────────────────────────────────────────

@app.post("/maint/update")
def system_update():
    """Update all packages."""
    result = run_cmd("pkg update -y && pkg upgrade -y", timeout=120)
    return {"action": "update", "ok": result["ok"], "output": result["stdout"]}


@app.post("/maint/clean")
def system_clean():
    """Clean package cache and temp files."""
    result = run_cmd("pkg clean -y && rm -rf /tmp/*")
    return {"action": "clean", "ok": result["ok"]}


@app.post("/maint/reboot")
def reboot_device():
    """Reboot the phone."""
    result = run_cmd("reboot")
    return {"action": "reboot", "ok": result["ok"]}


@app.get("/maint/health")
def health_check():
    """Comprehensive health check."""
    checks = {}

    # SSH
    sshd = run_cmd("pgrep sshd")
    checks["sshd"] = {"running": sshd["ok"], "pid": sshd["stdout"]}

    # phoned
    phoned = run_cmd("pgrep -f 'server.py'")
    checks["phoned"] = {"running": phoned["ok"], "pid": phoned["stdout"]}

    # Tor
    tor = run_cmd("pgrep tor")
    checks["tor"] = {"running": tor["ok"]}

    # Nginx
    nginx = run_cmd("pgrep nginx")
    checks["nginx"] = {"running": nginx["ok"]}

    # pm2
    pm2 = run_cmd("pm2 list --no-color | grep -c online")
    checks["pm2"] = {"online_processes": pm2["stdout"]}

    # Disk space
    disk = psutil.disk_usage(str(Path.home()))
    checks["disk"] = {
        "percent": disk.percent,
        "warning": disk.percent > 90,
    }

    # Memory
    mem = psutil.virtual_memory()
    checks["memory"] = {
        "percent": mem.percent,
        "warning": mem.percent > 90,
    }

    # Battery
    try:
        bat = subprocess.run(
            ["termux-battery-status"], capture_output=True, text=True, timeout=5
        )
        bat_data = json.loads(bat.stdout)
        checks["battery"] = {
            "percent": bat_data.get("percentage", -1),
            "warning": bat_data.get("percentage", 100) < 20,
        }
    except Exception:
        checks["battery"] = {"percent": -1, "warning": False}

    # Overall health
    all_ok = all(
        v.get("running", True) if isinstance(v, dict) else True
        for v in checks.values()
    )

    return {
        "healthy": all_ok,
        "checks": checks,
        "timestamp": datetime.now().isoformat(),
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000, log_level="info")
