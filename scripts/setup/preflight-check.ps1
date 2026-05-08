#Requires -RunAsAdministrator
param()
$pass = 0; $fail = 0; $warn = 0

function Write-Check($label, $result, $detail = "") {
    if ($result -eq "PASS") {
        Write-Host "  [PASS] $label" -ForegroundColor Green; $script:pass++
    } elseif ($result -eq "WARN") {
        Write-Host "  [WARN] $label – $detail" -ForegroundColor Yellow; $script:warn++
    } else {
        Write-Host "  [FAIL] $label – $detail" -ForegroundColor Red; $script:fail++
    }
}

Write-Host "`n=== GRC Hyper-V Lab Preflight Check ===`n" -ForegroundColor Cyan

$hvFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
Write-Check "Hyper-V Enabled" (if ($hvFeature.State -eq "Enabled") { "PASS" } else { "FAIL" }) `
    "Run: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All"

$switch = Get-VMSwitch -Name "GRC-Lab-Switch" -ErrorAction SilentlyContinue
Write-Check "Hyper-V Switch 'GRC-Lab-Switch'" (if ($switch) { "PASS" } else { "FAIL" }) `
    "Run: .\scripts\setup\create-hyperv-switch.ps1"

$ramGB = [math]::Round((Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB)
Write-Check "Host RAM >= 32 GB (found: ${ramGB}GB)" `
    (if ($ramGB -ge 32) { "PASS" } elseif ($ramGB -ge 24) { "WARN" } else { "FAIL" }) `
    "Consider staged deployment or reducing VM RAM in Vagrantfile"

$freeGB = [math]::Round((Get-PSDrive C).Free / 1GB)
Write-Check "Free Disk >= 500 GB (found: ${freeGB}GB)" `
    (if ($freeGB -ge 500) { "PASS" } elseif ($freeGB -ge 200) { "WARN" } else { "FAIL" }) `
    "Lab requires ~320 GB thin-provisioned"

$vagrant = Get-Command vagrant -ErrorAction SilentlyContinue
Write-Check "Vagrant Installed" (if ($vagrant) { "PASS" } else { "FAIL" }) "choco install vagrant -y"

$ansible = Get-Command ansible -ErrorAction SilentlyContinue
Write-Check "Ansible Installed" (if ($ansible) { "PASS" } else { "FAIL" }) "pip install ansible"

$pywinrm = python -c "import winrm; print('ok')" 2>&1
Write-Check "pywinrm Installed" (if ($pywinrm -eq "ok") { "PASS" } else { "FAIL" }) `
    "pip install pywinrm requests-ntlm"

Write-Host "`n=== Summary ===`n  PASS: $pass  WARN: $warn  FAIL: $fail`n" -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 } else { exit 0 }
