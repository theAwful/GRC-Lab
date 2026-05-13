#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates GRC-Lab-Switch and configures NAT so all VMs including AUDIT-BOX
    get internet access through the host via 10.10.10.1.

.NOTES
    This host appears to be a VM itself (VirtIO NIC detected), so an external
    switch is not possible. NAT through the internal switch is the correct
    approach for nested virtualization environments.

    All VMs use:
      Gateway : 10.10.10.1  (this host)
      DNS     : 8.8.8.8 during bootstrap, then 10.10.10.10 after DC promotion
#>

$SwitchName = "GRC-Lab-Switch"
$NatName    = "GRC-Lab-NAT"
$HostIP     = "10.10.10.1"
$Prefix     = "10.10.10.0/24"
$PrefixLen  = 24

Write-Host ""
Write-Host "=== GRC Lab - Hyper-V Switch + NAT Setup ===" -ForegroundColor Cyan
Write-Host ""

# ── 1. Internal switch ────────────────────────────────────────────────────────
$existing = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  [OK] Switch '$SwitchName' already exists." -ForegroundColor Green
} else {
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
    Write-Host "  [+] Switch '$SwitchName' created." -ForegroundColor Green
}

# ── 2. Host IP 10.10.10.1 on the switch adapter ───────────────────────────────
$adapter = Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" }
if (-not $adapter) {
    Write-Error "Cannot find adapter for '$SwitchName'"
    exit 1
}

$existingIP = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex `
    -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -eq $HostIP }

if ($existingIP) {
    Write-Host "  [OK] Host IP $HostIP already assigned." -ForegroundColor Green
} else {
    Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 `
        -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceIndex $adapter.ifIndex `
        -IPAddress $HostIP -PrefixLength $PrefixLen | Out-Null
    Write-Host "  [+] Host IP $HostIP/$PrefixLen assigned." -ForegroundColor Green
}

# ── 3. NAT rule ───────────────────────────────────────────────────────────────
$existingNat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
if ($existingNat) {
    Write-Host "  [OK] NAT '$NatName' already exists." -ForegroundColor Green
} else {
    New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $Prefix | Out-Null
    Write-Host "  [+] NAT '$NatName' created for $Prefix." -ForegroundColor Green
}

# ── 4. IP forwarding (required for NAT to actually route packets) ─────────────
$fwdKey  = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
$current = (Get-ItemProperty -Path $fwdKey -Name IPEnableRouter -ErrorAction SilentlyContinue).IPEnableRouter
if ($current -eq 1) {
    Write-Host "  [OK] IP forwarding already enabled." -ForegroundColor Green
} else {
    Set-ItemProperty -Path $fwdKey -Name IPEnableRouter -Value 1
    Write-Host "  [+] IP forwarding enabled." -ForegroundColor Green
    Write-Host "      NOTE: Reboot the host for IP forwarding to take full effect." -ForegroundColor Yellow
}

# ── 5. Firewall rule to allow forwarded traffic ───────────────────────────────
$fwRule = Get-NetFirewallRule -Name "GRC-Lab-Forward" -ErrorAction SilentlyContinue
if ($fwRule) {
    Write-Host "  [OK] Firewall forward rule already exists." -ForegroundColor Green
} else {
    New-NetFirewallRule `
        -Name        "GRC-Lab-Forward" `
        -DisplayName "GRC Lab - Allow Forwarded Traffic" `
        -Direction   Inbound `
        -Action      Allow `
        -Protocol    Any | Out-Null
    Write-Host "  [+] Firewall rule created." -ForegroundColor Green
}

# ── 6. Quick internet test from this host ────────────────────────────────────
Write-Host ""
Write-Host "  Testing internet from host..." -ForegroundColor Cyan
try {
    $r = Invoke-WebRequest -Uri "https://pypi.org" -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
    Write-Host "  [OK] Host has internet access." -ForegroundColor Green
} catch {
    Write-Warning "  Host cannot reach pypi.org -- VMs may not get internet either."
    Write-Warning "  Verify the parent hypervisor is passing internet through the VirtIO NIC."
}

# ── 7. Summary ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Switch      : $SwitchName (Internal)"
Write-Host "  Host IP     : $HostIP (gateway for all VMs)"
Write-Host "  NAT         : $NatName -> $Prefix"
Write-Host "  IP Forward  : $((Get-ItemProperty -Path $fwdKey -Name IPEnableRouter).IPEnableRouter) (1=enabled)"
Write-Host ""
Write-Host "  Configure VMs with:" -ForegroundColor Cyan
Write-Host "    IP      : 10.10.10.x"
Write-Host "    Mask    : 255.255.255.0"
Write-Host "    Gateway : 10.10.10.1"
Write-Host "    DNS     : 8.8.8.8 (bootstrap), then 10.10.10.10 after DC promotion"
Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host ""
