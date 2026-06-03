# Phone Server

Turn any Android phone into a **private, secure, always-on VPS**.

## One Command Setup

**On your phone (Termux):**
```bash
pkg install git && git clone https://github.com/MrNova420/android-server && cd android-server && bash install.sh
```

That's it. SSH, API, watchdog, health monitoring - all auto-configured.

**On your laptop:**
```bash
git clone https://github.com/MrNova420/android-server && cd android-server && bash install-client.sh && phoned init
```

## What You Get

| Service | Port | Purpose |
|---------|------|---------|
| SSH | 8022 | Remote shell access |
| phoned API | 5000 | Remote management |
| Watchdog | - | Auto-restart crashed services |
| Health Monitor | - | Disk/memory/resource checks |

## Reliability Features

- **Auto-restart**: Watchdog monitors SSH and phoned, restarts if crashed
- **Boot persistence**: Services start automatically on phone reboot
- **Health monitoring**: Disk cleanup, memory pressure handling
- **Crash prevention**: Resource limits, OOM protection

## Access

| Method | Command | Use Case |
|--------|---------|----------|
| SSH | `phoned ssh` | Same WiFi |
| Cloudflare | `ssh user@ssh.domain.com` | Anywhere |
| Tor | `ssh user@xxx.onion` | Anonymous |
| Port Forward | `phoned ports 8080` | Expose any port |

## CLI Commands

```
phoned status            Phone status (CPU, RAM, disk, battery)
phoned ssh               SSH session
phoned run "cmd"         Execute remote command
phoned deploy ./app      Deploy project to phone
phoned services          List services
phoned service X start   Start/stop/restart service
phoned projects          List projects
phoned logs X            View logs
phoned ports 8080        Forward port locally
phoned sync ./app        Sync directory
phoned anon on           Enable Tor
phoned anon rotate       New Tor IP
phoned network           IP addresses
phoned health            Health check
phoned device battery    Battery status
phoned device notify     Send notification
phoned ssh-restart       Restart SSH
phoned update            Update packages
phoned reboot            Reboot phone
```

## Phone Commands

```
sysinfo        System status
status         Service status
start-sshd     Restart SSH
start-phoned   Restart server
restart-all    Restart everything
```

## Troubleshooting

```bash
# SSH won't start
bash fix-ssh.sh

# pip blocked
bash fix-pip.sh

# Check logs
cat ~/.phonesrv/logs/server.log
cat ~/.phonesrv/logs/watchdog.log
cat ~/.phonesrv/logs/health.log

# Restart everything
restart-all
```

## Architecture

```
Phone                                  Laptop
├── sshd (:8022)           ◄───────  ssh / phoned ssh
├── phoned API (:5000)     ◄───────  phoned status/deploy/...
├── watchdog (auto-heal)             monitors all services
├── health monitor                   disk/memory/resource checks
├── Tor (:9050)                      phoned anon on
├── Cloudflare Tunnel   ◄─────────  phoned tunnel start
└── pm2 (projects)                   phoned projects
```

## Requirements

**Phone**: Android 7+, Termux (F-Droid), Termux:Boot, Termux:API  
**Laptop**: Python 3.8+, SSH client, `pip install requests`

## License

MIT
