#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# FIX PIP - If pip install is blocked on Termux
# Run this ON YOUR PHONE in Termux
# ============================================================

echo "═══════════════════════════════════════"
echo "  FIXING PIP INSTALLATION"
echo "═══════════════════════════════════════"
echo ""

# Method 1: Use pkg to install pip
echo "[*] Method 1: Installing via pkg..."
pkg install -y python-pip 2>/dev/null

# Method 2: Ensurepip
echo "[*] Method 2: Trying ensurepip..."
python -m ensurepip --upgrade 2>/dev/null || true
python3 -m ensurepip --upgrade 2>/dev/null || true

# Method 3: get-pip.py
echo "[*] Method 3: Using get-pip.py..."
curl -sS https://bootstrap.pypa.io/get-pip.py | python 2>/dev/null || \
curl -sS https://bootstrap.pypa.io/get-pip.py | python3 2>/dev/null || true

# Upgrade pip
echo "[*] Upgrading pip..."
pip install --upgrade pip 2>/dev/null || \
pip3 install --upgrade pip 2>/dev/null || true

# Test
echo ""
echo "[*] Testing pip..."
if pip --version 2>/dev/null || pip3 --version 2>/dev/null; then
    echo ""
    echo "[+] PIP IS WORKING!"
    echo ""
    echo "  Install packages with:"
    echo "    pip install fastapi uvicorn psutil requests"
    echo ""
else
    echo ""
    echo "[!] pip still not working."
    echo "  Try installing packages directly:"
    echo "    pkg install python-fastapi python-uvicorn python-psutil python-requests"
    echo ""
fi
