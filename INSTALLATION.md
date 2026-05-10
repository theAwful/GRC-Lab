# Installation Guide

> **Windows host users:** Ansible does not run on Windows. This lab solves that by running Ansible *inside* the AUDIT-BOX (Kali) VM — Vagrant boots it and triggers Ansible automatically. You only need Vagrant and Git on your Windows machine.

---

## How the Deployment Works

```
Your Windows Host (Hyper-V)
  │
  ├─ vagrant up
  │
  │  1. Boots all Windows VMs
  │     └─ PowerShell WinRM bootstrap runs on each
  │
  │  2. Boots AUDIT-BOX (Kali)
  │     └─ bootstrap-audit-box.sh installs Ansible + Galaxy collections
  │
  │  3. ansible_local provisioner fires ON AUDIT-BOX
  │     └─ Ansible targets all Windows VMs over WinRM
  │        Promotes DCs, populates AD, configures everything
  └──────────────────────────────────────────────────────────
```

**You need on Windows: Vagrant + Git only. No Ansible. No Python. No WSL.**

---

Complete step-by-step instructions for deploying the GRC Hyper-V Lab from scratch.

---

## Prerequisites

### Host Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Windows 10 Pro/Enterprise 21H2+ | Windows 11 Pro/Enterprise |
| RAM | 32 GB | 64 GB |
| CPU | 8 cores, Intel VT-x or AMD-V | 16+ cores |
| Disk | 500 GB SSD | 1 TB NVMe |
| Hyper-V | Must be supported and enabled | — |

> **Note:** Running all 8 VMs simultaneously requires ~32 GB RAM. On a 32 GB host, use staged deployment (see Step 7B).

---

## Step 1 – Enable Hyper-V

Run the following in an **Administrator PowerShell** window, then reboot:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Tools-All -All
```

Verify after reboot:

```powershell
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
# State should be: Enabled
```

---

## Step 2 – Install Dependencies

```powershell
# Install Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = `
    [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
    'https://community.chocolatey.org/install.ps1'))

# Install core tools
choco install vagrant git python3 -y

# Verify versions
vagrant --version    # 2.4+
python --version     # 3.10+
git --version

# Python packages for Ansible WinRM
pip install ansible pywinrm requests-ntlm requests-kerberos

# Ansible collections (required)
ansible-galaxy collection install ansible.windows
ansible-galaxy collection install community.windows
ansible-galaxy collection install microsoft.ad

# Vagrant plugin
vagrant plugin install vagrant-reload
```

---

## Step 3 – Clone the Repository

```powershell
git clone https://github.com/YOUR-ORG/grc-hyperv-lab.git
cd grc-hyperv-lab
```

---

## Step 4 – Run the Preflight Check

```powershell
.\scripts\setup\preflight-check.ps1
```

This validates:
- Hyper-V is enabled
- The `GRC-Lab-Switch` virtual switch exists (or reminds you to create it)
- Sufficient RAM and disk space
- Vagrant, Ansible, and pywinrm are installed

Fix any `[FAIL]` items before continuing.

---

## Step 5 – Create the Hyper-V Internal Switch

```powershell
.\scripts\setup\create-hyperv-switch.ps1
```

This creates:
- **Internal switch** named `GRC-Lab-Switch`
- **Host IP** `10.10.10.1/24` on that switch
- **NAT rule** `GRC-Lab-NAT` so VMs can reach the internet through the host

To verify:

```powershell
Get-VMSwitch -Name "GRC-Lab-Switch"
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "10.10.10.*" }
```

---

## Step 6 – Configure Credentials

Edit `ansible/group_vars/all.yml` and set a strong password:

```yaml
domain_admin_pass: "YourStrongP@ss2024!"
```

> Do not commit real credentials. The default `GrcL@b2024!` is for lab use only.

---

## Step 7 – Pre-download Vagrant Boxes

This step is optional but **strongly recommended** — it avoids timeout failures during `vagrant up` on slow connections:

```powershell
vagrant box add gusztavvargadr/windows-server-2022-standard --provider hyperv
vagrant box add gusztavvargadr/windows-server-2019-standard --provider hyperv
vagrant box add gusztavvargadr/windows-10-enterprise --provider hyperv
vagrant box add gusztavvargadr/windows-11-enterprise --provider hyperv
vagrant box add kalilinux/rolling --provider hyperv
```

> Boxes are 5–15 GB each. Total download: ~50–60 GB.

---

## Step 8A – Full Deployment (64 GB+ hosts)

```powershell
vagrant up
```

This brings up all 8 VMs in sequence and runs Ansible provisioning from AUDIT-BOX at the end. **Expected runtime: 60–90 minutes** on first run.

---

## Step 8B – Staged Deployment (32 GB hosts)

Bring VMs up in groups to avoid OOM. Shut down each group before starting the next, or reduce per-VM RAM in `Vagrantfile`.

```powershell
# Stage 1: Domain Controllers (required first – everything else joins them)
vagrant up DC-PRIMARY DC-SECONDARY
# Wait for full provisioning to complete before proceeding

# Stage 2: Member Servers
vagrant up MEMBER-SERVER-01 MEMBER-SERVER-02

# Stage 3: Workstations
vagrant up WORKSTATION-WIN10-01 WORKSTATION-WIN10-02 WORKSTATION-WIN11

# Stage 4: Audit Box (triggers Ansible provisioning of everything)
vagrant up AUDIT-BOX
```

---

## Step 9 – Verify the Deployment

Once `vagrant up` completes, run the following checks:

```powershell
# Check all VMs are running
Get-VM | Select-Object Name, State

# Verify DC-PRIMARY is healthy
vagrant winrm DC-PRIMARY -e -c "Import-Module ActiveDirectory; Get-ADDomain"

# Count AD objects
vagrant winrm DC-PRIMARY -e -c @"
  (Get-ADUser -Filter *).Count
  (Get-ADGroup -Filter *).Count
  (Get-ADComputer -Filter *).Count
"@
# Expected: ~200 users, ~55 groups, ~50 computers
```

---

## Step 10 – Take Baseline Snapshots

After successful deployment, capture a clean restore point:

```powershell
.\scripts\setup\restore-snapshots.ps1 -Action Create -SnapshotName "baseline"

# Verify snapshots were created
.\scripts\setup\restore-snapshots.ps1 -Action List
```

---

## Step 11 – Connect and Start Auditing

```powershell
# Option A: Run audit scripts from your Windows host directly
cd scripts\audit-targets
.\Get-ADUserAudit.ps1 -DomainController 10.10.10.10

# Option B: SSH into AUDIT-BOX and run from there
vagrant ssh AUDIT-BOX
bash ~/grc-audit/run-all-audits.sh
```

---

## Reducing VM RAM (for hosts with less than 32 GB)

Edit the `Vagrantfile` and lower the `ram` values:

```ruby
MACHINES = [
  { name: "DC-PRIMARY",   ..., ram: 3072, ... },  # Min 3 GB for DC
  { name: "DC-SECONDARY", ..., ram: 2048, ... },  # Min 2 GB for replica DC
  { name: "MEMBER-SERVER-01", ..., ram: 2048, ... },
  ...
  { name: "WORKSTATION-WIN10-01", ..., ram: 2048, ... },
]
```

Minimum RAM guidance:
- Domain Controllers: 3 GB minimum
- Member Servers: 2 GB minimum
- Workstations: 2 GB minimum
- AUDIT-BOX (Kali): 2 GB minimum

---

## Troubleshooting

### WinRM connection refused / timeout

```powershell
# From the Hyper-V host, test WinRM port directly
Test-NetConnection -ComputerName 10.10.10.10 -Port 5985

# Inside the VM (via Hyper-V console), run:
winrm quickconfig -q
netsh advfirewall firewall add rule name="WinRM-HTTP" protocol=TCP dir=in localport=5985 action=allow
```

### Vagrant up fails with "The box could not be found"

```powershell
vagrant box list
vagrant box add gusztavvargadr/windows-server-2022-standard --provider hyperv
```

### Ansible "unreachable" for Windows hosts

```powershell
# Verify pywinrm is installed correctly
python -c "import winrm; print(winrm.__version__)"

# Check group_vars/all.yml has correct transport
# ansible_winrm_transport: ntlm
```

### Domain join fails on member servers / workstations

Ensure DC-PRIMARY is fully provisioned before running member servers:

```powershell
# Test DNS from within the VM console
nslookup corp.grclab.local 10.10.10.10

# Test from host
vagrant winrm DC-PRIMARY -e -c "Get-ADDomain"
```

### "GRC-Lab-Switch not found" in Vagrantfile

```powershell
.\scripts\setup\create-hyperv-switch.ps1
# Then re-run vagrant up
```

### Out of disk space during box download

Vagrant stores boxes in `%USERPROFILE%\.vagrant.d\boxes` by default. To change:

```powershell
$env:VAGRANT_HOME = "D:\.vagrant.d"
[System.Environment]::SetEnvironmentVariable("VAGRANT_HOME","D:\.vagrant.d","Machine")
```

---

## Resetting the Lab

```powershell
# Option A: Restore to baseline snapshot (fastest – ~2 min)
.\scripts\setup\restore-snapshots.ps1 -Action Restore -SnapshotName "baseline" -Force

# Option B: Re-run only Ansible provisioning (no VM rebuild – ~20 min)
ansible-playbook -i ansible/inventory.yml ansible/playbooks/site.yml

# Option C: Full destroy and rebuild (slowest – 60-90 min)
vagrant destroy -f
vagrant up
```
