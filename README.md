# Phone Server - Android VPS

Turn any Android phone into a **private, secure, anonymous VPS** you can access from anywhere.

## Quick Start (3 steps)

### 1. Phone (one command)
```bash
curl -fsSL https://raw.githubusercontent.com/YOU/android-server/main/setup-phone.sh | bash
```

### 2. Laptop (one command)
```bash
bash install-client.sh && phoned init
```

### 3. Done
```bash
phoned ssh          # SSH session
phoned status       # Phone status
phoned deploy ./app # Deploy project
```

## Features

| Feature | Details |
|---------|---------|
| **Full SSH** | Key-only auth, like a real VPS |
| **Remote Access** | LAN, Cloudflare tunnel, or Tor |
| **Port Forwarding** | `phoned ports 8080` forwards any port |
| **Project Deploy** | `phoned deploy ./app` syncs instantly |
| **Process Manager** | pm2 for 24/7 project uptime |
| **Anonymous Mode** | Tor + IP rotation + .onion services |
| **Monitoring** | CPU, RAM, disk, battery, health |
| **Dashboard** | Web UI at port 8090 |
| **File Transfer** | `phoned files upload/download` |
| **Auto-Start** | Survives reboots via Termux:Boot |

## CLI Commands

```bash
phoned init              # Setup wizard
phoned status            # Full phone status
phoned ssh               # SSH into phone
phoned run "cmd"         # Execute remote command
phoned deploy ./app      # Deploy project
phoned services          # List all services
phoned service X restart # Control a service
phoned projects          # List deployed projects
phoned logs X            # View service logs
phoned ports 8080        # Forward port locally
phoned sync ./app        # Sync directory
phoned anon on           # Enable Tor
phoned anon rotate       # New Tor IP
phoned network           # IP addresses
phoned health            # Health check
phoned device battery    # Battery status
phoned device notify     # Send notification
phoned files list ~      # Browse files
phoned update            # Update packages
phoned reboot            # Reboot phone
```

## Access Methods

### Local Network (fastest)
```bash
ssh -p 8022 user@192.168.x.x
```

### Cloudflare Tunnel (from anywhere)
```bash
ssh user@ssh.yourdomain.com  # after tunnel setup
```

### Tor (anonymous)
```bash
ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:9050 %h %p" user@xxx.onion
```

## Architecture

```
Phone (Termux)                    Laptop
├── sshd (port 8022)  ◄────────  ssh / phoned ssh
├── phoned API (:5000) ◄─────── phoned status/deploy/...
├── Tor (:9050)                 phoned anon on/rotate
├── Cloudflare Tunnel ◄──────── phoned tunnel start
├── pm2 (process manager)       phoned projects
├── nginx (:8080)               phoned ports 8080
└── dashboard (:8090)           browser
```

## Requirements

**Phone:** Android 7+, Termux (F-Droid), Termux:Boot, Termux:API  
**Laptop:** Python 3.8+, SSH client, `pip install requests`

## License

MIT
