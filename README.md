# GRC Audit Lab — Hyper-V Edition

A **Vagrant + Ansible + Hyper-V** lab environment purpose-built for IT GRC (Governance, Risk & Compliance) teams to develop, test, and validate audit scripts against a realistic, fully-populated Active Directory environment.

> Inspired by [mad-hyperv](https://github.com/Marmeus/mad-hyperv) — reengineered for GRC/audit use cases rather than penetration testing.

---

## What's in the Lab

| Component | Details |
|-----------|---------|
| **Domain** | `corp.grclab.local` / NetBIOS: `GRCLAB` |
| **Users** | ~200 accounts across 10 departments |
| **Groups** | 55+ security, distribution, role, and GPO-filter groups |
| **Computers** | ~50 objects (desktops, laptops, servers, kiosks) |
| **GPOs** | 12 Group Policy Objects linked to relevant OUs |
| **PSOs** | 4 Fine-Grained Password Policies |
| **GRC Findings** | 15 intentional misconfigurations (MC-001 through MC-015) |
| **Audit Scripts** | 7 ready-to-run PowerShell audit scripts |

---

## Network Topology

```
10.10.10.0/24  –  GRC-Lab-Switch (Hyper-V Internal + NAT)
│
├── 10.10.10.1    Hyper-V Host (NAT gateway)
├── 10.10.10.10   DC-PRIMARY         (Windows Server 2022 – PDC/FSMO)
├── 10.10.10.11   DC-SECONDARY       (Windows Server 2022 – Replica DC)
├── 10.10.10.20   MEMBER-SERVER-01   (Windows Server 2019 – File Server)
├── 10.10.10.21   MEMBER-SERVER-02   (Windows Server 2019 – IIS Web Server)
├── 10.10.10.31   WORKSTATION-WIN10-01  (Windows 10 – domain workstation)
├── 10.10.10.32   WORKSTATION-WIN10-02  (Windows 10 – domain workstation)
├── 10.10.10.33   WORKSTATION-WIN11     (Windows 11 – domain workstation)
└── 10.10.10.50   AUDIT-BOX          (Kali Linux – jump host / audit runner)
```

---

## Quick Start

```powershell
# 1. Clone
git clone https://github.com/YOUR-ORG/grc-hyperv-lab.git
cd grc-hyperv-lab

# 2. Preflight check
.\scripts\setup\preflight-check.ps1

# 3. Create Hyper-V switch
.\scripts\setup\create-hyperv-switch.ps1

# 4. Deploy (60-90 min first run)
vagrant up

# 5. Take baseline snapshot
.\scripts\setup\restore-snapshots.ps1 -Action Create -SnapshotName "baseline"

# 6. Run audit scripts
cd scripts\audit-targets
.\Get-ADUserAudit.ps1      -DomainController 10.10.10.10
.\Get-PasswordPolicy.ps1   -DomainController 10.10.10.10
.\Get-PrivilegedGroups.ps1 -DomainController 10.10.10.10
.\Get-SMBConfig.ps1        -TargetHosts 10.10.10.10,10.10.10.20 -CheckNullSessions -CheckWinRM
.\Get-AuditPolicy.ps1      -TargetHosts 10.10.10.10,10.10.10.11
.\Get-GPOReport.ps1        -DomainController 10.10.10.10
.\Get-ServiceAccounts.ps1  -DomainController 10.10.10.10
```

---

## Intentional GRC Findings

The lab ships with 15 seeded misconfigurations your audit scripts should detect:

| ID | Finding | Severity | Location |
|----|---------|----------|----------|
| MC-001 | Password policy below CIS baseline (min 8 chars, no complexity) | High | DC-PRIMARY |
| MC-002 | Stale/inactive accounts not disabled (>90 days) | Medium | DC-PRIMARY |
| MC-003 | Domain Users in local Administrators on workstations | Critical | WIN10-01/02 |
| MC-004 | SMBv1 enabled, signing not required | High | MEMBER-SERVER-01 |
| MC-005 | Logon/privilege auditing disabled on DCs | High | Both DCs |
| MC-006 | Guest account enabled (blank password) | Medium | WIN10-02 |
| MC-007 | Null sessions allowed (RestrictAnonymous=0) | Medium | DC-SECONDARY |
| MC-008 | WinRM HTTP only – no HTTPS listener | Medium | Member Servers |
| MC-009 | Service accounts with PasswordNeverExpires | Medium | DC-PRIMARY |
| MC-010 | BitLocker not configured on workstations | Medium | Workstations |
| MC-011 | Orphaned/former accounts still in privileged groups | High | DC-PRIMARY |
| MC-012 | Excess members directly in Domain Admins | High | DC-PRIMARY |
| MC-013 | Hidden privilege path via nested group membership | High | DC-PRIMARY |
| MC-014 | Service accounts in Remote Desktop Users group | Medium | DC-PRIMARY |
| MC-015 | Test accounts enabled and in production groups | Medium | DC-PRIMARY |

All findings can be toggled via `ansible/group_vars/all.yml` — set any `mc_0XX_*` flag to `false` and re-run `misconfigurations.yml` to clear a finding.

---

## Repository Structure

```
grc-hyperv-lab/
├── Vagrantfile
├── .gitignore
│
├── ansible/
│   ├── inventory.yml
│   ├── group_vars/
│   │   ├── all.yml                       # Domain, credentials, MC flags
│   │   ├── domain_controllers.yml
│   │   ├── member_servers.yml
│   │   └── workstations.yml
│   ├── host_vars/
│   │   └── dc-primary.yml
│   ├── playbooks/
│   │   ├── site.yml                      # Master – runs everything in order
│   │   ├── domain-controllers.yml        # DC-PRIMARY + DC-SECONDARY
│   │   ├── member-servers.yml            # File Server + IIS
│   │   ├── workstations.yml              # Win10/Win11 workstations
│   │   ├── misconfigurations.yml         # Intentional GRC findings
│   │   └── audit-box.yml                 # Kali jump host config
│   └── roles/
│       ├── common/tasks/main.yml         # WinRM, firewall, PS policy (all Windows)
│       ├── dc-primary/tasks/
│       │   ├── main.yml                  # Forest creation, DNS, FSMO
│       │   └── populate-ad.yml           # Calls Invoke-ADLabPopulate.ps1
│       ├── dc-secondary/tasks/main.yml   # Replica DC promotion
│       ├── member-server/tasks/main.yml  # Domain join, server baseline
│       └── workstation/tasks/main.yml    # Domain join, workstation baseline
│
├── scripts/
│   ├── setup/
│   │   ├── preflight-check.ps1           # Host requirement validation
│   │   ├── create-hyperv-switch.ps1      # Hyper-V switch + NAT creation
│   │   ├── restore-snapshots.ps1         # Snapshot lifecycle management
│   │   └── Invoke-ADLabPopulate.ps1      # AD data population (~200 users, groups, etc.)
│   └── audit-targets/
│       ├── Get-ADUserAudit.ps1           # User enum, stale accounts, guest
│       ├── Get-PrivilegedGroups.ps1      # Privileged group membership + local admins
│       ├── Get-PasswordPolicy.ps1        # Domain policy vs CIS, BitLocker
│       ├── Get-GPOReport.ps1             # GPO enum, HTML export
│       ├── Get-AuditPolicy.ps1           # Audit subcategory configuration
│       ├── Get-SMBConfig.ps1             # SMB versions, signing, null sessions, WinRM
│       └── Get-ServiceAccounts.ps1       # Service account review
│
└── docs/
    ├── README.md                         # This file
    ├── INSTALLATION.md                   # Full step-by-step setup guide
    ├── MISCONFIGURATIONS.md              # GRC findings reference
    ├── AD-DATA-REFERENCE.md             # Full AD object inventory
    └── AUDIT-SCRIPT-GUIDE.md            # How to use audit scripts
```

---

## Host Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Windows 10 Pro 21H2+ | Windows 11 Pro/Enterprise |
| RAM | 32 GB | 64 GB |
| CPU | 8 cores (VT-x/AMD-V) | 16+ cores |
| Disk | 500 GB SSD | 1 TB NVMe |
| Hyper-V | Enabled | Enabled |

See [INSTALLATION.md](INSTALLATION.md) for detailed setup instructions.

---

## Snapshot Management

```powershell
# Create a named snapshot of all VMs
.\scripts\setup\restore-snapshots.ps1 -Action Create -SnapshotName "baseline"

# Restore all VMs to a snapshot (instant lab reset)
.\scripts\setup\restore-snapshots.ps1 -Action Restore -SnapshotName "baseline" -Force

# List all snapshots
.\scripts\setup\restore-snapshots.ps1 -Action List

# Show current VM states
.\scripts\setup\restore-snapshots.ps1 -Action Status
```

---

## Default Credentials

| Account | Username | Password |
|---------|----------|----------|
| Domain Administrator | `GRCLAB\Administrator` | Set in `group_vars/all.yml` |
| Standard domain users | `firstname.lastname` | `LabP@ssw0rd2024!` |
| Admin accounts (Tier 0/1) | `adm.firstname.lastname` | `LabP@ssw0rd2024!` |
| Vagrant (all VMs) | `vagrant` | `vagrant` |

---

## Contributing

1. Fork the repository
2. Create a branch: `git checkout -b feature/new-audit-script`
3. Add your audit script to `scripts/audit-targets/`
4. Update `docs/AUDIT-SCRIPT-GUIDE.md`
5. Submit a pull request

---

> ⚠️ **Warning:** This lab contains intentional security misconfigurations for GRC testing purposes. **Never deploy on a production network or expose to the internet.**

---

## License

MIT — See [LICENSE](LICENSE)
