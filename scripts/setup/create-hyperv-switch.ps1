#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates the GRC Lab Hyper-V switches.

    Two switches are created:
      1. GRC-Lab-Switch  (Internal) -- isolated lab network, 10.10.10.0/24
                                       all VMs connect here for lab traffic
                                       host is at 10.10.10.1

      2. GRC-External-Switch (External, bridged to your Ethernet NIC)
                                       AUDIT-BOX connects here to get a
                                       real DHCP address from your router
                                       and full internet access

    This is the same as VMware's bridged networking -- the VM appears as
    a real device on your LAN with internet access, no NAT or ICS needed.
    Requires a wired Ethernet adapter (not WiFi).
#>

$LabSwitchName  = "GRC-Lab-Switch"
$ExtSwitchName  = "GRC-External-Switch"
$HostIP         = "10.10.10.1"
$Prefix         = "10.10.10.0/24"
$PrefixLen      = 24

Write-Host ""
Write-Host "=== GRC Lab - Hyper-V Switch Setup ===" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# 1. GRC-Lab-Switch (Internal) -- lab-only isolated network
# =============================================================================
$existing = Get-VMSwitch -Name $LabSwitchName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  [OK] Internal switch '$LabSwitchName' already exists." -ForegroundColor Green
} else {
    New-VMSwitch -Name $LabSwitchName -SwitchType Internal | Out-Null
    Write-Host "  [+] Internal switch '$LabSwitchName' created." -ForegroundColor Green
}

# Assign host IP 10.10.10.1 on the lab switch adapter
$adapter = Get-NetAdapter | Where-Object { $_.Name -like "*$LabSwitchName*" }
if (-not $adapter) {
    Write-Error "Cannot find adapter for '$LabSwitchName'"
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

# =============================================================================
# 2. GRC-External-Switch (External, bridged to Ethernet NIC)
#    Gives AUDIT-BOX a real LAN IP + internet access -- same as VMware bridged
# =============================================================================
$existingExt = Get-VMSwitch -Name $ExtSwitchName -ErrorAction SilentlyContinue
if ($existingExt) {
    Write-Host "  [OK] External switch '$ExtSwitchName' already exists." -ForegroundColor Green
} else {
    # Find the physical Ethernet adapter that has internet access
    # Prefers adapters with a default gateway (i.e. internet-connected)
    $physicalAdapters = Get-NetAdapter |
        Where-Object {
            $_.Status -eq 'Up' -and
            $_.PhysicalMediaType -ne 'Unspecified' -and
            $_.Name -notlike '*vEthernet*' -and
            $_.Name -notlike '*Hyper-V*' -and
            $_.Name -notlike '*Loopback*'
        } | Sort-Object -Property { 
            # Prefer adapters with a default gateway
            $gw = (Get-NetRoute -InterfaceIndex $_.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)
            if ($gw) { 0 } else { 1 }
        }

    if (-not $physicalAdapters) {
        Write-Error "No physical Ethernet adapters found. Cannot create external switch."
        exit 1
    }

    # Show available adapters so user can confirm
    Write-Host ""
    Write-Host "  Available Ethernet adapters:" -ForegroundColor Cyan
    $physicalAdapters | ForEach-Object {
        $gw = (Get-NetRoute -InterfaceIndex $_.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)
        $hasInternet = if ($gw) { "(internet-connected)" } else { "" }
        Write-Host "    - $($_.Name): $($_.InterfaceDescription) $hasInternet"
    }

    $selectedAdapter = $physicalAdapters | Select-Object -First 1
    Write-Host ""
    Write-Host "  Using: $($selectedAdapter.Name) ($($selectedAdapter.InterfaceDescription))" -ForegroundColor Yellow
    Write-Host "  (Edit this script and set -NetAdapterName manually to choose a different adapter)"
    Write-Host ""

    New-VMSwitch -Name $ExtSwitchName `
        -NetAdapterName $selectedAdapter.Name `
        -AllowManagementOS $true | Out-Null
    Write-Host "  [+] External switch '$ExtSwitchName' created on '$($selectedAdapter.Name)'." -ForegroundColor Green
}

# =============================================================================
# 3. Verify
# =============================================================================
Write-Host ""
Write-Host "=== Verification ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  GRC-Lab-Switch   : Internal | Host IP: $HostIP | All lab VMs connect here"
Write-Host "  GRC-External-Switch : External | Bridged to Ethernet | AUDIT-BOX internet NIC"
Write-Host ""
Write-Host "  VM network config:" -ForegroundColor Cyan
Write-Host "    Windows VMs   -> GRC-Lab-Switch only"
Write-Host "                     IP: 10.10.10.x, Mask: 255.255.255.0, GW: (none needed)"
Write-Host "    AUDIT-BOX     -> GRC-Lab-Switch (10.10.10.50, static)"
Write-Host "                  -> GRC-External-Switch (DHCP from your router)"
Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host ""
