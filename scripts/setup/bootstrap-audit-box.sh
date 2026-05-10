#!/usr/bin/env bash
# =============================================================================
# GRC Hyper-V Lab – AUDIT-BOX Bootstrap
# scripts/setup/bootstrap-audit-box.sh
#
# Runs as a shell provisioner on AUDIT-BOX (Kali) BEFORE ansible_local fires.
# Installs Ansible, all required Python packages, and Ansible Galaxy collections.
# This is the step that replaces "ansible-galaxy install" on your Windows host.
# =============================================================================

set -euo pipefail

echo ""
echo "============================================================"
echo "  GRC Lab – AUDIT-BOX Bootstrap"
echo "  Installing Ansible + dependencies for lab provisioning"
echo "============================================================"
echo ""

# ── Update apt ────────────────────────────────────────────────────────────────
echo "[1/7] Updating apt package lists..."
apt-get update -qq

# ── Python 3 + pip ────────────────────────────────────────────────────────────
echo "[2/7] Installing Python 3, pip, venv..."
apt-get install -y -qq \
    python3 \
    python3-pip \
    python3-venv \
    python3-full \
    pipx \
    git \
    curl \
    wget \
    sshpass \
    openssh-client

# ── Ansible via pipx (preferred on modern Kali – avoids PEP 668 errors) ──────
echo "[3/7] Installing Ansible via pipx..."
if ! command -v ansible &>/dev/null; then
    pipx install --include-deps ansible
    pipx ensurepath
    # Make ansible available in PATH for this session and all future ones
    export PATH="$PATH:/root/.local/bin"
    echo 'export PATH="$PATH:/root/.local/bin"' >> /etc/environment
    echo 'export PATH="$PATH:/root/.local/bin"' >> /home/vagrant/.bashrc
else
    echo "  Ansible already installed: $(ansible --version | head -1)"
fi

# Ensure ansible is findable in PATH for the rest of this script
export PATH="$PATH:/root/.local/bin:/home/vagrant/.local/bin"

# ── Python packages for WinRM ─────────────────────────────────────────────────
echo "[4/7] Installing Python WinRM packages..."
# Use pipx inject to add pywinrm into the same venv as ansible
pipx inject ansible \
    pywinrm \
    requests-ntlm \
    requests-kerberos \
    "pywinrm[kerberos]" \
    "pywinrm[credssp]" \
    jinja2 \
    pyyaml \
    packaging \
    2>/dev/null || \
# Fallback: pip install with break-system-packages flag
pip3 install \
    ansible \
    pywinrm \
    requests-ntlm \
    requests-kerberos \
    "pywinrm[kerberos]" \
    jinja2 \
    pyyaml \
    packaging \
    --break-system-packages \
    --quiet

echo "  pywinrm version: $(python3 -c 'import winrm; print(winrm.__version__)' 2>/dev/null || echo 'check pip')"

# ── Ansible Galaxy collections ────────────────────────────────────────────────
echo "[5/7] Installing Ansible Galaxy collections..."

# Ensure ansible-galaxy is reachable
GALAXY="$(command -v ansible-galaxy 2>/dev/null || echo /root/.local/bin/ansible-galaxy)"

# Install as root (so ansible_local can use them)
$GALAXY collection install \
    ansible.windows \
    community.windows \
    microsoft.ad \
    community.general \
    --force-with-deps \
    -p /home/vagrant/.ansible/collections \
    2>&1 | tail -5

# Also install at system level so vagrant user can use them
$GALAXY collection install \
    ansible.windows \
    community.windows \
    microsoft.ad \
    community.general \
    --force-with-deps \
    2>&1 | tail -5

echo "  Collections installed:"
$GALAXY collection list 2>/dev/null | grep -E "ansible\.windows|community\.windows|microsoft\.ad|community\.general" || true

# ── Additional audit tools ────────────────────────────────────────────────────
echo "[6/7] Installing additional GRC audit tools..."
apt-get install -y -qq \
    nmap \
    smbclient \
    ldap-utils \
    netcat-openbsd \
    dnsutils \
    powershell \
    jq \
    tree \
    tmux \
    vim \
    dos2unix \
    csvkit \
    2>/dev/null || true

# PowerShell audit modules
if command -v pwsh &>/dev/null; then
    pwsh -NoProfile -NonInteractive -Command "
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Install-Module ImportExcel   -Force -Scope AllUsers -ErrorAction SilentlyContinue
        Install-Module PSWriteHTML   -Force -Scope AllUsers -ErrorAction SilentlyContinue
        Write-Output 'PS modules done.'
    " 2>/dev/null || true
fi

# ── Verify installation ───────────────────────────────────────────────────────
echo "[7/7] Verifying installation..."

echo ""
echo "  Ansible:       $(ansible --version 2>/dev/null | head -1 || echo 'NOT FOUND')"
echo "  ansible-galaxy: $(ansible-galaxy --version 2>/dev/null | head -1 || echo 'NOT FOUND')"
echo "  python3:       $(python3 --version 2>/dev/null || echo 'NOT FOUND')"
echo "  pywinrm:       $(python3 -c 'import winrm; print(winrm.__version__)' 2>/dev/null || echo 'NOT FOUND')"
echo "  pwsh:          $(pwsh --version 2>/dev/null || echo 'not installed')"

# Fail loud if Ansible didn't install
if ! command -v ansible &>/dev/null && ! test -f /root/.local/bin/ansible; then
    echo ""
    echo "ERROR: Ansible installation failed. Check network connectivity and retry."
    exit 1
fi

# ── /etc/hosts for lab VMs ────────────────────────────────────────────────────
echo ""
echo "Writing /etc/hosts lab entries..."
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

# ── Kerberos config ───────────────────────────────────────────────────────────
cat > /etc/krb5.conf << 'KRB5'
[libdefaults]
  default_realm = CORP.GRCLAB.LOCAL
  dns_lookup_realm = false
  dns_lookup_kdc = false
  forwardable = true

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

# ── Audit workspace ───────────────────────────────────────────────────────────
mkdir -p /home/vagrant/grc-audit/{scripts,reports,evidence,config}
chown -R vagrant:vagrant /home/vagrant/grc-audit

echo ""
echo "============================================================"
echo "  AUDIT-BOX Bootstrap complete."
echo "  Ansible is ready. ansible_local provisioner will now run"
echo "  the site.yml playbook against all lab VMs."
echo "============================================================"
echo ""
