#Requires -RunAsAdministrator
$SwitchName = "GRC-Lab-Switch"
$NatName    = "GRC-Lab-NAT"
$HostIP     = "10.10.10.1"
$Prefix     = "10.10.10.0/24"

if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    New-VMSwitch -Name $SwitchName -SwitchType Internal
    $adapter = Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" }
    New-NetIPAddress -IPAddress $HostIP -PrefixLength 24 -InterfaceIndex $adapter.ifIndex
    Write-Host "[OK] Switch '$SwitchName' created. Host IP: $HostIP" -ForegroundColor Green
} else {
    Write-Host "[INFO] Switch already exists." -ForegroundColor Yellow
}

if (-not (Get-NetNat -Name $NatName -ErrorAction SilentlyContinue)) {
    New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $Prefix
    Write-Host "[OK] NAT created – VMs have internet access via host." -ForegroundColor Green
}
