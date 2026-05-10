#Requires -RunAsAdministrator
<#
.SYNOPSIS
    GRC Hyper-V Lab – Snapshot Manager
    Create, restore, list, and delete Hyper-V snapshots across all lab VMs.

.DESCRIPTION
    Manages checkpoint (snapshot) lifecycle for the GRC lab environment.
    Supports named snapshots so you can maintain multiple restore points
    (e.g. "baseline", "post-misconfiguration", "post-audit").

.PARAMETER Action
    Create   – Take a new snapshot of all (or specified) lab VMs
    Restore  – Restore all (or specified) VMs to a named snapshot
    List     – List all snapshots for all lab VMs
    Delete   – Delete a named snapshot from all (or specified) lab VMs
    Status   – Show current power state and last snapshot for each VM

.PARAMETER SnapshotName
    Name for Create/Restore/Delete operations. Default: "baseline"

.PARAMETER VMNames
    Specific VM names to operate on. Default: all lab VMs.

.PARAMETER Force
    Skip confirmation prompts for Restore and Delete.

.EXAMPLE
    # Create baseline snapshot (run after vagrant up + ansible provision)
    .\restore-snapshots.ps1 -Action Create -SnapshotName "baseline"

.EXAMPLE
    # Restore everything to baseline
    .\restore-snapshots.ps1 -Action Restore -SnapshotName "baseline"

.EXAMPLE
    # Create snapshot after misconfigurations are seeded
    .\restore-snapshots.ps1 -Action Create -SnapshotName "post-misconfiguration"

.EXAMPLE
    # List all snapshots
    .\restore-snapshots.ps1 -Action List

.EXAMPLE
    # Restore only the workstations
    .\restore-snapshots.ps1 -Action Restore -SnapshotName "baseline" `
        -VMNames "WORKSTATION-WIN10-01","WORKSTATION-WIN10-02","WORKSTATION-WIN11"

.EXAMPLE
    # Show current VM status
    .\restore-snapshots.ps1 -Action Status
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet("Create","Restore","List","Delete","Status")]
    [string]$Action,

    [string]$SnapshotName = "baseline",

    [string[]]$VMNames = @(
        "DC-PRIMARY",
        "DC-SECONDARY",
        "MEMBER-SERVER-01",
        "MEMBER-SERVER-02",
        "WORKSTATION-WIN10-01",
        "WORKSTATION-WIN10-02",
        "WORKSTATION-WIN11",
        "AUDIT-BOX"
    ),

    [switch]$Force
)

$ErrorActionPreference = "Continue"
$WarningPreference      = "Continue"

# ─── Helpers ──────────────────────────────────────────────────────────────────
function Write-Header { param($msg)
    Write-Host "`n╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host   "║  $($msg.PadRight(56))║" -ForegroundColor Cyan
    Write-Host   "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}
function Write-OK    { param($msg) Write-Host "  [OK]   $msg" -ForegroundColor Green  }
function Write-Warn  { param($msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "  [ERR]  $msg" -ForegroundColor Red    }
function Write-Info  { param($msg) Write-Host "  [INFO] $msg" -ForegroundColor Gray   }
function Write-Skip  { param($msg) Write-Host "  [SKIP] $msg" -ForegroundColor DarkGray }

function Get-LabVM {
    param([string]$Name)
    $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Warn "VM '$Name' not found in Hyper-V Manager – skipping."
        return $null
    }
    return $vm
}

function Get-SnapshotByName {
    param([string]$VMName, [string]$SnapName)
    $snaps = Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue
    return $snaps | Where-Object { $_.Name -eq $SnapName } | Select-Object -First 1
}

function Confirm-Action {
    param([string]$Message)
    if ($Force) { return $true }
    $response = Read-Host "`n  $Message [y/N]"
    return ($response -ieq "y")
}

# ─── Check Hyper-V availability ───────────────────────────────────────────────
try {
    Get-VM -ErrorAction Stop | Out-Null
} catch {
    Write-Err "Cannot connect to Hyper-V. Ensure you are running as Administrator on the Hyper-V host."
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# ACTION: Status
# ─────────────────────────────────────────────────────────────────────────────
if ($Action -eq "Status") {
    Write-Header "GRC Lab – VM Status"
    Write-Host "`n  {0,-28} {1,-12} {2,-25} {3}" -f "VM Name","State","Latest Snapshot","Snapshot Time"
    Write-Host "  {0,-28} {1,-12} {2,-25} {3}" -f ("-"*27),("-"*11),("-"*24),("-"*20)

    foreach ($name in $VMNames) {
        $vm = Get-LabVM $name
        if (-not $vm) { continue }

        $latestSnap = Get-VMSnapshot -VMName $name -ErrorAction SilentlyContinue |
            Sort-Object CreationTime -Descending | Select-Object -First 1

        $snapName = if ($latestSnap) { $latestSnap.Name } else { "(none)" }
        $snapTime = if ($latestSnap) { $latestSnap.CreationTime.ToString("yyyy-MM-dd HH:mm") } else { "" }

        $stateColor = switch ($vm.State) {
            "Running" { "Green" }; "Off" { "Gray" }; "Paused" { "Yellow" }; default { "White" }
        }
        Write-Host ("  {0,-28} " -f $name) -NoNewline
        Write-Host ("{0,-12} " -f $vm.State) -NoNewline -ForegroundColor $stateColor
        Write-Host ("{0,-25} {1}" -f $snapName, $snapTime)
    }
    Write-Host ""
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# ACTION: List
# ─────────────────────────────────────────────────────────────────────────────
if ($Action -eq "List") {
    Write-Header "GRC Lab – All Snapshots"

    foreach ($name in $VMNames) {
        $vm = Get-LabVM $name
        if (-not $vm) { continue }

        $snaps = Get-VMSnapshot -VMName $name -ErrorAction SilentlyContinue
        Write-Host "`n  ► $name" -ForegroundColor Cyan
        if (-not $snaps -or $snaps.Count -eq 0) {
            Write-Info "  No snapshots."
        } else {
            foreach ($s in ($snaps | Sort-Object CreationTime)) {
                Write-Host ("    {0,-30} {1}" -f $s.Name, $s.CreationTime.ToString("yyyy-MM-dd HH:mm:ss"))
            }
        }
    }
    Write-Host ""
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# ACTION: Create
# ─────────────────────────────────────────────────────────────────────────────
if ($Action -eq "Create") {
    Write-Header "GRC Lab – Creating Snapshot: '$SnapshotName'"

    $pass = 0; $skip = 0; $fail = 0

    foreach ($name in $VMNames) {
        $vm = Get-LabVM $name
        if (-not $vm) { $skip++; continue }

        # Warn if snapshot name already exists
        $existing = Get-SnapshotByName -VMName $name -SnapName $SnapshotName
        if ($existing) {
            Write-Warn "$name – Snapshot '$SnapshotName' already exists (created $($existing.CreationTime.ToString('yyyy-MM-dd HH:mm'))). Will create a new one with the same name."
        }

        try {
            Checkpoint-VM -Name $name -SnapshotName $SnapshotName -ErrorAction Stop
            Write-OK "$name – Snapshot '$SnapshotName' created."
            $pass++
        } catch {
            Write-Err "$name – Failed to create snapshot: $($_.Exception.Message)"
            $fail++
        }
    }

    Write-Host "`n  Summary: $pass created, $skip skipped, $fail failed.`n" -ForegroundColor Cyan
    if ($fail -gt 0) { exit 1 } else { exit 0 }
}

# ─────────────────────────────────────────────────────────────────────────────
# ACTION: Restore
# ─────────────────────────────────────────────────────────────────────────────
if ($Action -eq "Restore") {
    Write-Header "GRC Lab – Restoring Snapshot: '$SnapshotName'"

    # Verify snapshots exist before committing
    Write-Host "`n  Checking snapshot availability...`n"
    $missing = @()
    foreach ($name in $VMNames) {
        $vm = Get-LabVM $name
        if (-not $vm) { continue }
        $snap = Get-SnapshotByName -VMName $name -SnapName $SnapshotName
        if (-not $snap) {
            $missing += $name
            Write-Warn "$name – Snapshot '$SnapshotName' NOT FOUND."
        } else {
            Write-Info "$name – Snapshot found (created $($snap.CreationTime.ToString('yyyy-MM-dd HH:mm')))."
        }
    }

    if ($missing.Count -gt 0) {
        Write-Warn "`n  $($missing.Count) VM(s) missing snapshot '$SnapshotName': $($missing -join ', ')"
        if (-not (Confirm-Action "Restore available VMs anyway, skipping the ones above?")) {
            Write-Host "  Restore cancelled.`n"
            exit 0
        }
    } else {
        if (-not (Confirm-Action "Restore ALL $($VMNames.Count) VMs to snapshot '$SnapshotName'? This will revert all changes since the snapshot was taken.")) {
            Write-Host "  Restore cancelled.`n"
            exit 0
        }
    }

    Write-Host ""
    $pass = 0; $skip = 0; $fail = 0

    foreach ($name in $VMNames) {
        $vm = Get-LabVM $name
        if (-not $vm) { $skip++; continue }

        $snap = Get-SnapshotByName -VMName $name -SnapName $SnapshotName
        if (-not $snap) { Write-Skip "$name – no '$SnapshotName' snapshot."; $skip++; continue }

        try {
            # Stop the VM first if running
            if ($vm.State -ne "Off") {
                Write-Info "$name – Stopping VM..."
                Stop-VM -Name $name -Force -TurnOff -ErrorAction Stop
                Start-Sleep -Seconds 3
            }

            # Restore
            Restore-VMSnapshot -VMSnapshot $snap -Confirm:$false -ErrorAction Stop
            Write-OK "$name – Restored to '$SnapshotName'."

            # Start the VM back up
            Start-VM -Name $name -ErrorAction Stop
            Write-Info "$name – Starting VM..."
            $pass++
        } catch {
            Write-Err "$name – Restore failed: $($_.Exception.Message)"
            $fail++
        }
    }

    Write-Host "`n  Summary: $pass restored, $skip skipped, $fail failed." -ForegroundColor Cyan

    if ($pass -gt 0) {
        Write-Host "`n  Waiting 60 seconds for VMs to boot before reporting...`n"
        Start-Sleep -Seconds 60
        # Quick status check
        & $PSCommandPath -Action Status -VMNames $VMNames
    }

    if ($fail -gt 0) { exit 1 } else { exit 0 }
}

# ─────────────────────────────────────────────────────────────────────────────
# ACTION: Delete
# ─────────────────────────────────────────────────────────────────────────────
if ($Action -eq "Delete") {
    Write-Header "GRC Lab – Deleting Snapshot: '$SnapshotName'"

    if (-not (Confirm-Action "Permanently delete snapshot '$SnapshotName' from all specified VMs? This cannot be undone.")) {
        Write-Host "  Delete cancelled.`n"
        exit 0
    }

    $pass = 0; $skip = 0; $fail = 0

    foreach ($name in $VMNames) {
        $vm = Get-LabVM $name
        if (-not $vm) { $skip++; continue }

        $snap = Get-SnapshotByName -VMName $name -SnapName $SnapshotName
        if (-not $snap) {
            Write-Skip "$name – snapshot '$SnapshotName' not found."
            $skip++
            continue
        }

        try {
            Remove-VMSnapshot -VMSnapshot $snap -Confirm:$false -ErrorAction Stop
            Write-OK "$name – Snapshot '$SnapshotName' deleted."
            $pass++
        } catch {
            Write-Err "$name – Delete failed: $($_.Exception.Message)"
            $fail++
        }
    }

    Write-Host "`n  Summary: $pass deleted, $skip skipped, $fail failed.`n" -ForegroundColor Cyan
    if ($fail -gt 0) { exit 1 } else { exit 0 }
}
