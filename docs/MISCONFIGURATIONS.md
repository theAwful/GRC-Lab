# Intentional Misconfigurations Reference

| ID | Finding | Category | Severity | VM | Control |
|----|---------|----------|----------|----|---------|
| MC-001 | Password policy: min 8 chars, no complexity, 180-day max age | IAM | High | DC-PRIMARY | CIS L1 1.1 / NIST IA-5 |
| MC-002 | Stale accounts (>90 days) not disabled | IAM | Medium | DC-PRIMARY | CIS 5.3 / NIST AC-2(3) |
| MC-003 | Domain Users in local Administrators | Privilege | Critical | WIN10-01/02 | CIS 4.3 / NIST AC-6 |
| MC-004 | SMBv1 enabled, signing not required | Network | High | MEMBER-SVR-01 | CIS 18.3 / NIST SC-8 |
| MC-005 | Logon/privilege auditing disabled | Logging | High | Both DCs | CIS 17.x / NIST AU-2 |
| MC-006 | Guest account enabled | IAM | Medium | WIN10-02 | CIS 4.5 |
| MC-007 | RestrictAnonymous=0 (null sessions) | Network | Medium | DC-SECONDARY | CIS 2.3 / NIST AC-17 |
| MC-008 | WinRM HTTP only, no HTTPS listener | Network | Medium | Member Servers | CIS 9.2 / NIST SC-8 |
| MC-009 | Service accounts: PasswordNeverExpires | IAM | Medium | DC-PRIMARY | CIS 1.1 / NIST IA-5 |
| MC-010 | No BitLocker on workstations | Encryption | Medium | All workstations | CIS 3.6 / NIST SC-28 |

Each finding can be toggled via `ansible/group_vars/all.yml` mc_00X flags.
To disable a finding: set its flag to `false` and re-run `ansible-playbook ... misconfigurations.yml`.
