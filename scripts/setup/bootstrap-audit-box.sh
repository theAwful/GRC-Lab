#!/usr/bin/env bash
# =============================================================================
# GRC Hyper-V Lab - AUDIT-BOX Bootstrap
# scripts/setup/bootstrap-audit-box.sh
#
# Runs as a shell provisioner on AUDIT-BOX (Kali) before ansible_local fires.
# Installs Ansible, Python WinRM packages, and Ansible Galaxy collections.
#
# INTERNET ACCESS
# ---------------
# AUDIT-BOX gets internet via Internet Connection Sharing (ICS) on the host.
# ICS shares the host's internet through GRC-Lab-Switch using a NAT gateway
# at 192.168.137.1. This script adds that as the default route if missing
# and prepends public DNS so apt/pip/galaxy can resolve hostnames.
#
# To enable ICS on your Windows host (one-time setup):
#   1. Open ncpa.cpl
#   2. Right-click your internet adapter (WiFi or Ethernet) -> Properties
#   3. Sharing tab -> check "Allow other network users to connect..."
#   4. Home networking connection -> select "vEthernet (GRC-Lab-Switch)"
#   5. Click OK
# =============================================================================

set -euo pipefail

echo ""
echo "============================================================"
echo "  GRC Lab - AUDIT-BOX Bootstrap"
echo "  Installing Ansible + dependencies"
echo "============================================================"
echo ""

# =============================================================================
# [0/7] Internet connectivity via NAT gateway (10.10.10.1)
# =============================================================================
# The Windows host is itself a VM (VirtIO NIC), so an external/bridged switch
# is not possible. Internet comes via NAT through the host at 10.10.10.1.
# create-hyperv-switch.ps1 sets this up with New-NetNat + IPEnableRouter.
echo "[0/7] Checking internet connectivity..."

LAB_GW="10.10.10.1"

# Add default route via lab gateway if not already set
if ! ip route show default 2>/dev/null | grep -q default; then
    echo "  Adding default route via $LAB_GW..."
    ip route add default via "$LAB_GW" 2>/dev/null || true
    sleep 2
fi

# Use public DNS for bootstrap -- lab DCs not promoted yet
if ! grep -q "8.8.8.8" /etc/resolv.conf; then
    echo "  Adding public DNS..."
    printf "nameserver 8.8.8.8\nnameserver 8.8.4.4\n" | \
        cat - /etc/resolv.conf > /tmp/resolv.tmp && \
        mv /tmp/resolv.tmp /etc/resolv.conf
fi

# Test -- retry 6 times
INTERNET_OK=false
for i in 1 2 3 4 5 6; do
    if curl -s --max-time 8 https://pypi.org > /dev/null 2>&1; then
        INTERNET_OK=true
        break
    fi
    echo "  Attempt $i/6 -- waiting 5s..."
    sleep 5
done

if $INTERNET_OK; then
    echo "  Internet: REACHABLE via $LAB_GW"
else
    echo ""
    echo "  !! INTERNET NOT REACHABLE !!"
    echo "  Checklist:"
    echo "    1. create-hyperv-switch.ps1 run on Windows host?"
    echo "    2. IPEnableRouter = 1 set? (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters).IPEnableRouter"
    echo "    3. Host itself has internet? (Test-NetConnection pypi.org -Port 443)"
    echo "    4. If IPEnableRouter was just set, a host reboot may be required."
    echo ""
    ip addr show
    ip route show
fi

echo ""

# =============================================================================
# [1/7] Update apt
# =============================================================================
echo "[1/7] Updating apt package lists..."
apt-get update -qq

# =============================================================================
# [2/7] Python 3 and core tools
# =============================================================================
echo "[2/7] Installing Python 3, pip, and core tools..."
apt-get install -y -qq \
    python3 \
    python3-pip \
    python3-full \
    pipx \
    git \
    curl \
    wget \
    sshpass \
    openssh-client \
    iproute2

# =============================================================================
# [3/7] Ansible via pipx
# =============================================================================
echo "[3/7] Installing Ansible..."
if ! command -v ansible &>/dev/null; then
    # pipx avoids PEP 668 "externally managed environment" errors on modern Kali
    pipx install --include-deps ansible 2>/dev/null || \
        pip3 install ansible --break-system-packages -q
    # Ensure ansible is in PATH
    pipx ensurepath 2>/dev/null || true
    export PATH="$PATH:/root/.local/bin"
    echo 'export PATH="$PATH:/root/.local/bin"' >> /etc/environment
    echo 'export PATH="$PATH:/root/.local/bin"' >> /home/vagrant/.bashrc
else
    echo "  Already installed: $(ansible --version 2>/dev/null | head -1)"
fi

# Make sure ansible-galaxy is reachable in this shell session
export PATH="$PATH:/root/.local/bin:/home/vagrant/.local/bin"

# =============================================================================
# [4/7] Python WinRM packages for Ansible -> Windows communication
# =============================================================================
echo "[4/7] Installing pywinrm and WinRM dependencies..."
ANSIBLE_BIN=$(command -v ansible 2>/dev/null || echo "/root/.local/bin/ansible")
PIPX_ANSIBLE=$(pipx list 2>/dev/null | grep "ansible" | head -1)

if [ -n "$PIPX_ANSIBLE" ]; then
    # Inject into the pipx ansible venv
    pipx inject ansible \
        pywinrm \
        "pywinrm[kerberos]" \
        requests-ntlm \
        requests-kerberos \
        2>/dev/null || \
    pip3 install pywinrm "pywinrm[kerberos]" requests-ntlm requests-kerberos \
        --break-system-packages -q
else
    pip3 install pywinrm "pywinrm[kerberos]" requests-ntlm requests-kerberos \
        --break-system-packages -q
fi

# Verify
python3 -c "import winrm; print('  pywinrm: ' + winrm.__version__)" 2>/dev/null || \
    echo "  WARNING: pywinrm not importable -- check pip install"

# =============================================================================
# [5/7] Ansible Galaxy collections
# =============================================================================
echo "[5/7] Installing Ansible Galaxy collections..."
GALAXY=$(command -v ansible-galaxy 2>/dev/null || echo "/root/.local/bin/ansible-galaxy")

$GALAXY collection install \
    ansible.windows \
    community.windows \
    microsoft.ad \
    community.general \
    --force-with-deps 2>&1 | tail -8

echo "  Collections installed."

# =============================================================================
# [6/7] Additional audit tools
# =============================================================================
echo "[6/7] Installing audit tools..."
apt-get install -y -qq \
    nmap \
    smbclient \
    ldap-utils \
    netcat-openbsd \
    dnsutils \
    jq \
    tree \
    tmux \
    vim \
    dos2unix \
    2>/dev/null || true

# PowerShell (for running .ps1 audit scripts directly from AUDIT-BOX)
if ! command -v pwsh &>/dev/null; then
    apt-get install -y -qq powershell 2>/dev/null || true
fi
if command -v pwsh &>/dev/null; then
    pwsh -NoProfile -NonInteractive -Command "
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Install-Module ImportExcel -Force -Scope AllUsers -ErrorAction SilentlyContinue
        Write-Output 'PS modules done.'
    " 2>/dev/null || true
fi

# =============================================================================
# [7/7] Workspace and config
# =============================================================================
echo "[7/7] Setting up audit workspace..."

# /etc/hosts entries for lab VMs
if ! grep -q "dc-primary" /etc/hosts; then
cat >> /etc/hosts << 'HOSTS'
# GRC Lab VMs
10.10.10.10  dc-primary dc-primary.corp.grclab.local
10.10.10.11  dc-secondary dc-secondary.corp.grclab.local
10.10.10.20  member-server-01 member-server-01.corp.grclab.local
10.10.10.21  member-server-02 member-server-02.corp.grclab.local
10.10.10.31  workstation-win10-01 workstation-win10-01.corp.grclab.local
10.10.10.32  workstation-win10-02 workstation-win10-02.corp.grclab.local
10.10.10.33  workstation-win11 workstation-win11.corp.grclab.local
HOSTS
fi

# Kerberos config
cat > /etc/krb5.conf << 'KRB5'
[libdefaults]
  default_realm = CORP.GRCLAB.LOCAL
  dns_lookup_realm = false
  dns_lookup_kdc = false

[realms]
  CORP.GRCLAB.LOCAL = {
    kdc = 10.10.10.10
    kdc = 10.10.10.11
    admin_server = 10.10.10.10
  }

[domain_realm]
  .corp.grclab.local = CORP.GRCLAB.LOCAL
  corp.grclab.local = CORP.GRCLAB.LOCAL
KRB5

# Audit workspace directories
mkdir -p /home/vagrant/grc-audit/{scripts,reports,evidence,config}
chown -R vagrant:vagrant /home/vagrant/grc-audit

# Bash aliases for convenience
if ! grep -q "GRC LAB" /home/vagrant/.bashrc; then
cat >> /home/vagrant/.bashrc << 'ALIASES'
# GRC Lab aliases
alias run-audit='bash ~/grc-audit/run-all-audits.sh'
alias audit-reports='ls -lh ~/grc-audit/reports/'
alias lab-scan='nmap -sn 10.10.10.0/24'
alias smb-enum='smbclient -L 10.10.10.10 -U GRCLAB\\Administrator'
ALIASES
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================================"
echo "  Bootstrap complete. Summary:"
echo "    Ansible:  $(ansible --version 2>/dev/null | head -1 || echo 'check PATH')"
echo "    pywinrm:  $(python3 -c 'import winrm; print(winrm.__version__)' 2>/dev/null || echo 'not found')"
echo "    pwsh:     $(pwsh --version 2>/dev/null || echo 'not installed')"
echo "    Internet: $(curl -s --max-time 5 https://pypi.org > /dev/null 2>&1 && echo 'OK' || echo 'NOT REACHABLE')"
echo "============================================================"
echo ""
