#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# MANUAL SSH SETUP - If the main script fails
# Run this ON YOUR PHONE in Termux
# ============================================================

echo "═══════════════════════════════════════"
echo "  MANUAL SSH SETUP"
echo "═══════════════════════════════════════"
echo ""

# Kill any existing sshd
pkill sshd 2>/dev/null
sleep 1

# Install openssh
echo "[*] Installing openssh..."
pkg install -y openssh

# Generate host keys
echo "[*] Generating host keys..."
ssh-keygen -A

# Set password
echo "[*] Setting password to 'phone' (change with: passwd)"
echo "phone:phone" | chpasswd 2>/dev/null || echo "Set manually with: passwd"

# Start sshd
echo "[*] Starting sshd..."
sshd

# Check
sleep 1
if pgrep sshd > /dev/null 2>&1; then
    echo ""
    echo "[+] SSHD IS RUNNING!"
    echo ""
    echo "  Port:     8022"
    echo "  User:     $(whoami)"
    echo "  Password: phone"
    echo ""
    echo "  Connect from laptop:"
    echo "    ssh -p 8022 $(whoami)@$(ip addr show wlan0 | grep inet | awk '{print $2}' | cut -d/ -f1)"
    echo ""
else
    echo ""
    echo "[!] sshd failed. Try running:"
    echo "    sshd -d"
    echo "  to see debug output"
    echo ""
fi
