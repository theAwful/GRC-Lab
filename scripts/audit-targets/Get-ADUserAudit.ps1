<#
.SYNOPSIS  GRC Audit – AD User Enumeration and Stale Account Detection
.EXAMPLE   .\Get-ADUserAudit.ps1 -DomainController 10.10.10.10 -StaleThresholdDays 90
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DomainController,
    [int]$StaleThresholdDays = 90,
    [switch]$CheckGuestAccount,
    [string]$OutputPath = ".\audit-users-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
)

$cutoff  = (Get-Date).AddDays(-$StaleThresholdDays)
$results = @()

$users = Get-ADUser -Server $DomainController -Filter * `
    -Properties LastLogonDate, PasswordLastSet, PasswordNeverExpires,
                Enabled, Department, MemberOf, Created

foreach ($u in $users) {
    $stale      = $u.LastLogonDate -and ($u.LastLogonDate -lt $cutoff)
    $privGroups = $u.MemberOf | Where-Object { $_ -match "Domain Admins|Enterprise Admins|Schema Admins" }

    $results += [PSCustomObject]@{
        SamAccountName      = $u.SamAccountName
        Enabled             = $u.Enabled
        LastLogonDate       = $u.LastLogonDate
        PasswordNeverExpires= $u.PasswordNeverExpires
        IsStale             = $stale
        IsPrivileged        = ($privGroups.Count -gt 0)
        Department          = $u.Department
        Finding             = if ($stale -and $u.Enabled) { "MC-002: Stale account active" }
                              elseif ($u.PasswordNeverExpires) { "MC-009: Password never expires" }
                              else { "OK" }
    }
}

if ($CheckGuestAccount) {
    $guest = Get-LocalUser -Name Guest -ErrorAction SilentlyContinue
    if ($guest -and $guest.Enabled) { Write-Warning "[MC-006] Guest account ENABLED" }
}

$staleActive = $results | Where-Object { $_.IsStale -and $_.Enabled }
Write-Host "`n=== AD User Audit Results ==="
Write-Host "  Total Users    : $($results.Count)"
Write-Host "  Stale & Active : $($staleActive.Count)" -ForegroundColor (if ($staleActive.Count) { "Red" } else { "Green" })
Write-Host "  Privileged     : $(($results | Where-Object IsPrivileged).Count)"

$results | Export-Csv -Path $OutputPath -NoTypeInformation
Write-Host "[+] Report saved: $OutputPath`n"
